{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}

module Network.ZeroRPC where

import qualified "mtl" Control.Monad.State.Lazy as S

import "mtl" Control.Monad.Trans (lift)
import Control.Applicative ((<$>), (<*>))
import Control.Concurrent (forkIO)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TBQueue (readTBQueue, TBQueue, tryReadTBQueue)
import Control.Monad (forever)
import Data.MessagePack (pack, unpack, toObject, Object(..), OBJECT, Packable, from, Unpackable(..))
import Data.Text (Text)
import Data.UUID.V4 (nextRandom)
import System.ZMQ4.Monadic (runZMQ, socket, connect, Req(..), liftIO, Receiver, Socket, ZMQ, Sender, async)
import Text.Show.Pretty (ppShow)

import Network.ZeroRPC.Types (Header(..), Event(..), Name(..), Message(..))
import Network.ZeroRPC.Wire (sendEvent, recvEvent)
import Network.ZeroRPC.Channel

import Control.Concurrent.STM.TBQueue (tryPeekTBQueue)
import Control.Concurrent.STM.TVar (readTVar)
import Control.Concurrent (threadDelay)
import Debug.Trace

ping serverName = return ("pong", serverName)

inspect :: Message Object
inspect = Msg [] "_zerorpc_inspect" (ObjectArray [])

sendAndPrint :: ZChannels Object -> Message Object -> IO ()
sendAndPrint zchans msg = do
    zchan <- atomically $ mkChannel zchans
    atomically $ send zchan msg
    forever $ printChannel $ zcIn zchan

testInspect :: IO ()
testInspect = do
    let mkSock = do
            req <- socket Req
            connect req "tcp://127.0.0.1:1234"
            return req
    zchans <- setupZChannels mkSock
    sendAndPrint zchans inspect

printChannel :: TBQueue (Message Object) -> IO ()
printChannel queue = do
    event <- atomically $ readTBQueue queue
    putStrLn $ ppShow event

main :: IO ()
main = testInspect

