{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}

module Network.ZeroRPC where

import qualified "mtl" Control.Monad.State.Lazy as S

import Control.Applicative ((<$>), (<*>))
import "mtl" Control.Monad.Trans (lift)
import Data.MessagePack (pack, unpack, toObject, Object(..), OBJECT, Packable, from, Unpackable(..))
import Data.Text (Text)
import Data.UUID.V4 (nextRandom)
import System.ZMQ4.Monadic (runZMQ, socket, connect, Req(..), liftIO, Receiver, Socket, ZMQ, Sender)
import Text.Show.Pretty (ppShow)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TBQueue (readTBQueue, TBQueue)


import Network.ZeroRPC.Types (Header(..), Event(..), Name(..), ZeroRPC)
import Network.ZeroRPC.Wire (event, sendEvent, recvEvent)
import Network.ZeroRPC.Channel


heartbeat = event "_zpc_hb" ()
more = event "_zpc_more"

stream = event "STREAM"
streamDone = event "STREAM_DONE" ()

ping serverName = return ("pong", serverName)

inspect :: Event Object
inspect = event "_zerorpc_inspect" (ObjectArray [])

testInspect :: ZeroRPC z Req ()
testInspect = do
    req <- lift $ socket Req
    lift $ connect req "tcp://127.0.0.1:1234"
    S.put $ Just req
    zchans <- setupZChannels
    zchan <- liftIO $ send zchans inspect
    case zchan of
        New chan -> do
            liftIO $ printChannel $ zcIn chan
        Existing chan -> return ()

printChannel :: TBQueue (Event Object) -> IO ()
printChannel queue = do
    event <- atomically $ readTBQueue queue
    putStrLn $ ppShow event

main :: IO ()
main = runZMQ $ S.evalStateT testInspect Nothing

