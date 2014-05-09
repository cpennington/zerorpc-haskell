{-# LANGUAGE PackageImports #-}

module Network.ZeroRPC.Types where

import "mtl" Control.Monad.State.Lazy (StateT)
import Data.ByteString (ByteString)
import Data.MessagePack (Object)
import Data.Text (Text)
import System.ZMQ4.Monadic (Socket, ZMQ)

type Header = (Object, Object)
type Name = Text

data Event a = Event {
    eMsgId :: !ByteString
  , eVersion :: !Int
  , eResponseTo :: !(Maybe ByteString)
  , eHeaders :: ![Header]
  , eName :: !Name
  , eArgs :: !a
} deriving Show

data Message a = Msg ![Header] !Name !a
               | Heartbeat
               | More !a
               | Stream !a
               | StreamDone
    deriving Show
