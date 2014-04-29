{-# LANGUAGE OverloadedStrings #-}

module Network.ZeroRPC where

import Control.Applicative ((<$>), (<*>))
import System.ZMQ4.Monadic (runZMQ, socket, connect, send, receive, Req(..))
import Data.MessagePack (pack, unpack, toObject, Object(..), OBJECT, Packable, from, Unpackable(..))
import Data.Text (Text)
import Data.ByteString.Lazy (toStrict)
import Text.Show.Pretty (ppShow)

type Header = (Object, Object)
type Name = Text

data Event a = Event [Header] Name a
    deriving Show

instance (Packable a) => Packable (Event a) where
    from (Event hs n v) = from (ObjectMap hs, n, v)

instance (Unpackable a) => Unpackable (Event a) where
    get = do
        (ObjectMap headers, name, value) <- get
        return $ Event headers name value

event :: Name -> a -> Event a
event = Event []

(.=) :: (OBJECT k, OBJECT v) => k -> v -> Header
key .= value = (toObject key, toObject value)
{-# INLINE (.=) #-}

heartbeat = Event [] "_zpc_hb" ()
more = Event [] "_zpc_more"

stream = Event [] "STREAM"
streamDone = Event [] "STREAM_DONE" ()

msgId :: Text -> Header
msgId i = ("message_id" :: Text) .= i

version3 :: Header
version3 = ("v" :: Text) .= (3 :: Int)

ping serverName = return ("pong", serverName)

inspect :: Event [String]
inspect = Event [msgId "foo", version3] "_zerorpc_inspect" []

main = do
    value <- runZMQ $ do
        req <- socket Req
        connect req "tcp://127.0.0.1:1234"
        send req [] (toStrict $ pack inspect)
        result <- receive req
        return $ unpack result
    putStr $ ppShow (value :: Event Object)
