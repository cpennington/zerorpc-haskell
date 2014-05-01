module Network.ZeroRPC.Types where

import Data.MessagePack (Object)
import Data.Text (Text)

type Header = (Object, Object)
type Name = Text

data Event a = Event ![Header] !Name !a
    deriving Show
