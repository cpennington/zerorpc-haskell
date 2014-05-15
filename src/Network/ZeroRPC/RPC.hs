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

import Control.Exception (throw)
import Control.Applicative ((<$>), (<*>), pure)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import Data.MessagePack.Unpack (UnpackError(..))
import Data.MessagePack.Assoc (Assoc(..))

import Network.ZeroRPC.Channel (send, recv, mkChannel, setupZChannels, ZChannels(..), Message(..))
import Network.ZeroRPC.Wire (Name)

data Client = Client {
    clChans :: !ZChannels
}

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

instance (OBJECT a1, OBJECT a2) =>  ARGS (a1, a2) where
    toArgs (a1, a2) = ObjectArray [toObject a1, toObject a2]
    tryFromArgs (ObjectArray [o1, o2]) = (,) <$> tryFromObject o1 <*> tryFromObject o2

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

_reqSingle :: (ARGS a) => Client -> Message -> IO a
_reqSingle client msg = do
    zchan <- atomically $ mkChannel $ clChans client
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
    zchans <- setupZChannels mkSock
    return $ Client zchans

connect s = do
    sock <- ask
    lift $ Z.connect sock s