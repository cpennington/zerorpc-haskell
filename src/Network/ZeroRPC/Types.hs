{-# LANGUAGE PackageImports #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}


module Network.ZeroRPC.Types where

import Data.ByteString (ByteString)
import Data.MessagePack (Object(..), OBJECT(..))
import Data.MessagePack.Unpack (UnpackError(..))
import Data.Text (Text)
import Control.Concurrent.STM (TBQueue, TVar)
import System.Random (StdGen)
import Control.Exception (throw)
import Control.Applicative ((<$>), (<*>), pure)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL

type Header = (Object, Object)
type Name = Text

data Event = Event {
    eMsgId :: !ByteString
  , eVersion :: !Int
  , eResponseTo :: !(Maybe ByteString)
  , eHeaders :: ![Header]
  , eName :: !Name
  , eArgs :: !Object
} deriving Show

data Message = Call !Name !Object
             | Heartbeat
             | More !Int
             | Stream !Object
             | StreamDone
             | Inspect
             | OK !Object
             | Err !Name !Text !Text  -- (error name, error message, traceback)
    deriving Show

data ZChan = ZChan {
    zcOut :: TBQueue (Message)
  , zcIn :: TBQueue (Message)
  , zcId :: TVar (Maybe ByteString)
  , zcGen :: TVar StdGen
}

data ZChannels = ZChannels {
    zcsIn :: TBQueue Event
  , zcsOut :: TBQueue Event
  , zcsChans :: TVar [ZChan]
  , zcsGen :: TVar StdGen
  , zcsNewChans :: TBQueue ZChan
}

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