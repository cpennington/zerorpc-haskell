{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Network.ZeroRPC where

import System.ZMQ4.Monadic (liftIO)
import Text.Show.Pretty (ppShow)
import Control.Monad (forever)
import Control.Concurrent (threadDelay)

import Network.ZeroRPC.RPC (mkClient, mkServer, inspect, connect, bind, call, ObjectSpec(..))

main :: IO ()
main = do
    client <- mkClient $ do
        connect "tcp://127.0.0.1:1234"
    (inspect client :: IO ObjectSpec) >>= liftIO . putStrLn . ppShow
    (call client "_zerorpc_ping" () :: IO (String, String)) >>= liftIO . putStrLn . ppShow
    (call client "time" () :: IO Double) >>= liftIO . putStrLn . ppShow

server :: IO ()
server = do
    mkServer "test" [] $ do
        bind "tcp://*:1234"
    forever $ threadDelay 1000

