{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE PackageImports #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}

module Network.ZeroRPC.RPC where

import Control.Concurrent.STM (atomically)
import Data.MessagePack (OBJECT(..), fromObject, toObject, Object(..), Packable(..), Unpackable(..))
import Control.Monad.Reader (runReaderT, ReaderT, ask)
import qualified System.ZMQ4.Monadic as Z
import "mtl" Control.Monad.Trans (lift)
import Control.Concurrent (forkIO)
import Control.Monad (forever, void)
import Data.List (find)

import Control.Exception (throw)
import Control.Applicative ((<$>), (<*>), pure)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import Data.MessagePack.Unpack (UnpackError(..))
import Data.MessagePack.Assoc (Assoc(..))

import Network.ZeroRPC.Channel (send, recv, addNewChannel, setupZChannels, ZChannels(..), Message(..), Callback(..), ZChan(..))
import Network.ZeroRPC.Wire (Name)

data Client = Client {
    clChans :: !ZChannels
}

data Server = Server {
    srvChans :: !ZChannels
  , srvMethods :: [Method]
}

data Method = Method {
    mName :: Name,
    mDoc :: Text,
    mCall :: Call
}

type Call = Object -> IO Object

-- | This class encodes arguments and return values into MessagePack tuples
class OBJECT a => ARGS a where
    toArgs :: a -> Object
    toArgs x = ObjectArray [toObject x]

    fromArgs :: Object -> a
    fromArgs a =
        case tryFromArgs a of
            Left err -> throw $ UnpackError err
            Right ret -> ret

    tryFromArgs :: Object -> Either String a
    tryFromArgs (ObjectArray [x]) = Right $ fromObject x
    tryFromArgs _ = tryFromArgsError

tryFromArgsError = Left "tryFromArgs: cannot cast"

instance ARGS Bool
instance ARGS Double
instance ARGS Float
instance ARGS Int
instance ARGS String
instance ARGS B.ByteString
instance ARGS BL.ByteString
instance ARGS T.Text
instance ARGS TL.Text
instance ARGS Object

instance ARGS () where
    toArgs = const $ ObjectArray []
    tryFromArgs (ObjectArray []) = Right ()
    tryFromArgs _ = tryFromArgsError

instance (OBJECT a1, OBJECT a2) =>  ARGS (a1, a2)

data FunctionSpec = FunctionSpec Name Text Object
    deriving (Show, Eq)

data ObjectSpec = ObjectSpec Name [FunctionSpec]
    deriving (Show, Eq)

instance Packable ObjectSpec where
    from (ObjectSpec name methods) = from $ Assoc [
        ("name", toObject name)
      , ("methods", ObjectMap $ map fnTuple methods)
      ]
        where
            fnTuple (FunctionSpec name doc argspec) = (toObject name, ObjectMap [(toObject "doc", toObject doc), (toObject "args", argspec)])

instance Unpackable ObjectSpec where
    get = do
        Assoc vs <- get
        let name = lookup "name" vs
            methods = lookup "methods" vs
        case (name, methods) of
            (Just name, Just (ObjectMap methods)) -> return $ ObjectSpec (fromObject name) (map parseFunctionSpec methods)
            (Just _, _) -> fail "missing required 'name' key"
            (_, Just _) -> fail "missing required 'methods' key"
            otherwise -> fail "missing required 'name' and 'methods' keys"
        where
            parseFunctionSpec (name, spec) =
                case (lookup "doc" specs, lookup "args" specs) of
                    (Just doc, Just argspec) -> FunctionSpec (fromObject name) (fromObject doc) argspec
                where (Assoc specs) = fromObject spec

instance OBJECT ObjectSpec
instance ARGS ObjectSpec


class Servable a where
    serve :: a -> Call

serveConst :: (ARGS a) => a -> Call
serveConst x = const $ (return $ toArgs x :: IO Object)

instance (OBJECT a, ARGS b) => Servable (a -> IO b) where
    serve f x = (f $ fromObject x) >>= (return . toArgs)

instance (OBJECT a, Servable b) => Servable (a -> b) where
    serve f x = (serve f) x

instance Servable Bool where serve = serveConst
instance Servable Double where serve = serveConst
instance Servable Float where serve = serveConst
instance Servable Int where serve = serveConst
instance Servable String where serve = serveConst
instance Servable B.ByteString where serve = serveConst
instance Servable BL.ByteString where serve = serveConst
instance Servable T.Text where serve = serveConst
instance Servable TL.Text where serve = serveConst
instance Servable Object where serve = serveConst
instance (OBJECT a, OBJECT b) => Servable (a, b) where serve = serveConst

_reqSingle :: (ARGS a) => Client -> Message -> IO a
_reqSingle client msg = do
    zchan <- atomically $ addNewChannel $ clChans client
    atomically $ send zchan msg
    resp <- atomically $ recv zchan
    case resp of
        OK value -> return $ fromArgs value
        otherwise -> fail $ show resp

call :: (ARGS a, ARGS b) => Client -> Name -> a -> IO b
call client fn args = _reqSingle client (Call fn $ toArgs args)

inspect :: Client -> IO ObjectSpec
inspect = flip _reqSingle Inspect

mkClient :: (forall z. ReaderT (Z.Socket z Z.Req) (Z.ZMQ z) ()) -> IO Client
mkClient confSock = do
    let mkSock = do
            req <- Z.socket Z.Req
            runReaderT confSock req
            return req
    zchans <- setupZChannels mkSock Nothing
    return $ Client zchans

mkCallback :: [Method] -> ZChan -> IO ()
mkCallback methods zchan = void $ forkIO $ forever $ do
    runMethod <- atomically $ do
        msg <- recv zchan
        case msg of
            Call name args ->
                case find ((== name) . mName) methods of
                    Just method -> return $ (mCall method) args
                    Nothing -> fail $ show msg
            otherwise -> fail $ show msg
    result <- runMethod
    atomically $ send zchan $ OK result

mkServer :: Name -> [Method] -> (forall z. ReaderT (Z.Socket z Z.Rep) (Z.ZMQ z) ()) -> IO Server
mkServer  name methods confSock = do
    let mkSock = do
            req <- Z.socket Z.Rep
            runReaderT confSock req
            return req
        ping = method (T.pack "_zerorpc_ping") (T.pack "Return pong") ("pong", name)
    zchans <- setupZChannels mkSock $ Just $ mkCallback $ ping:methods

    return $ Server zchans methods

method :: Servable a => Name -> Text -> a -> Method
method name doc f = Method name doc (serve f)

withSock f = ask >>= lift . f

connect :: String -> (forall z. ReaderT (Z.Socket z s) (Z.ZMQ z) ())
connect = withSock . flip Z.connect

bind :: String -> (forall z. ReaderT (Z.Socket z s) (Z.ZMQ z) ())
bind = withSock . flip Z.bind
