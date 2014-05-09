{-# LANGUAGE PackageImports #-}

module Network.ZeroRPC.Types where

import Data.ByteString (ByteString)
import Data.MessagePack (Object)
import Data.Text (Text)

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

data Message a = Msg !Name !a
               | Heartbeat
               | More !a
               | Stream !a
               | StreamDone
               | Inspect
    deriving Show
