{-# LANGUAGE OverloadedStrings #-}

module Network.ZeroRPC where

import System.ZMQ4.Monadic (runZMQ, socket, connect, send, receive, Req(..))
import Data.MessagePack (Object, pack, unpack, Assoc(..))
import Data.Text (Text)
import Data.ByteString.Lazy (toStrict)
import Text.Show.Pretty (ppShow)

type Header = [(Object, Object)]
type Name = Text

data Event a = Event Header Name a

heartbeat = Event [] "_zpc_hb" ()
more = Event [] "_zpc_more"

stream = Event [] "STREAM"
streamDone = Event [] "STREAM_DONE" ()

ping serverName = return ("pong", serverName)

inspect :: (Assoc [(String, String)], String, [String])
inspect = (Assoc [("message_id", "foo"), ("v", "3")], "_zerorpc_inspect", [])

main = do
    value <- runZMQ $ do
        req <- socket Req
        connect req "tcp://127.0.0.1:1234"
        send req [] (toStrict $ pack inspect)
        result <- receive req
        return $ unpack result
    putStr $ ppShow (value :: Object)
