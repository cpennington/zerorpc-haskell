{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}

module Network.ZeroRPC where

import qualified "mtl" Control.Monad.State.Lazy as S

import Control.Applicative ((<$>), (<*>))
import "mtl" Control.Monad.Trans (lift)
import Data.MessagePack (pack, unpack, toObject, Object(..), OBJECT, Packable, from, Unpackable(..))
import Data.Text (Text)
import Data.UUID.V4 (nextRandom)
import System.ZMQ4.Monadic (runZMQ, socket, connect, send, receive, Req(..), liftIO, Receiver, Socket, ZMQ, Sender)
import Text.Show.Pretty (ppShow)

import Network.ZeroRPC.Types (Header(..), Event(..), Name(..))
import Network.ZeroRPC.Wire (event, sendEvent, recvEvent)

heartbeat = event "_zpc_hb" ()
more = event "_zpc_more"

stream = event "STREAM"
streamDone = event "STREAM_DONE" ()

ping serverName = return ("pong", serverName)

inspect :: Event [String]
inspect = event "_zerorpc_inspect" []

testInspect :: S.StateT (Socket z Req) (ZMQ z) (Event Object)
testInspect = do
    req <- lift $ socket Req
    lift $ connect req "tcp://127.0.0.1:1234"
    S.put req
    sendEvent inspect
    recvEvent

main = do
    value <- runZMQ $ S.evalStateT testInspect undefined
    putStrLn $ ppShow (value :: Event Object)

