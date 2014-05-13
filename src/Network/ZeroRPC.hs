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
import System.ZMQ4.Monadic (runZMQ, socket, Req(..), liftIO, Receiver, Socket, ZMQ, Sender, async)
import Text.Show.Pretty (ppShow)

import Network.ZeroRPC.Types (Header(..), Event(..), Name(..), Message(..))
import Network.ZeroRPC.RPC (mkClient, inspect, connect)

import Control.Concurrent.STM.TBQueue (tryPeekTBQueue)
import Control.Concurrent.STM.TVar (readTVar)
import Control.Concurrent (threadDelay)
import Debug.Trace

testInspect :: IO ()
testInspect = do
    client <- mkClient $ do
        connect "tcp://127.0.0.1:1234"
    resp <- inspect client
    liftIO $ putStrLn $ ppShow resp

main :: IO ()
main = testInspect

