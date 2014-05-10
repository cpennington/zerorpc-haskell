{-# LANGUAGE PackageImports #-}

module Network.ZeroRPC.Types where

import Data.ByteString (ByteString)
import Data.MessagePack (Object)
import Data.Text (Text)
import Control.Concurrent.STM (TBQueue, TVar)
import System.Random (StdGen)

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