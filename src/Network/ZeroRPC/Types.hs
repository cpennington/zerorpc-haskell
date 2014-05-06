{-# LANGUAGE PackageImports #-}

module Network.ZeroRPC.Types where

import Data.MessagePack (Object)
import Data.Text (Text)
import "mtl" Control.Monad.State.Lazy (StateT)
import System.ZMQ4.Monadic (Socket, ZMQ)

type Header = (Object, Object)
type Name = Text

data Event a = Event ![Header] !Name !a
    deriving Show
