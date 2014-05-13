{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Network.ZeroRPC where

import System.ZMQ4.Monadic (liftIO)
import Text.Show.Pretty (ppShow)

import Network.ZeroRPC.RPC (mkClient, inspect, connect, call)

testInspect :: IO ()
testInspect = do
    client <- mkClient $ do
        connect "tcp://127.0.0.1:1234"
    (resp :: Double) <- call client "time" ()
    liftIO $ putStrLn $ ppShow resp

main :: IO ()
main = testInspect

