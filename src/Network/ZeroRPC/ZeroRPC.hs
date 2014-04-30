{-# LANGUAGE OverloadedStrings #-}

module Network.ZeroRPC where

import Control.Applicative ((<$>), (<*>))
import System.ZMQ4.Monadic (runZMQ, socket, connect, send, receive, Req(..), liftIO)
import Data.MessagePack (pack, unpack, toObject, Object(..), OBJECT, Packable, from, Unpackable(..))
import Data.Text (Text)
import Data.ByteString.Lazy (toStrict)
import Data.ByteString (ByteString)
import Text.Show.Pretty (ppShow)
import Data.UUID (toByteString, UUID)
import Data.UUID.V4 (nextRandom)
import Data.Maybe (Maybe(..), listToMaybe)

type Header = (Object, Object)
type Name = Text
type MsgId = Maybe ByteString

data Event a = Event MsgId ![Header] !Name !a
    deriving Show

msgIdKey :: Object
msgIdKey = toObject ("message_id" :: String)

versionKey :: Object
versionKey = toObject ("v" :: String)

instance (Packable a) => Packable (Event a) where
    from (Event Nothing hs n v) = from (ObjectMap $ version3:hs, n, v)
    from (Event (Just i) hs n v) = from (ObjectMap $ (msgId i):version3:hs, n, v)

instance (Unpackable a) => Unpackable (Event a) where
    get = do
        (ObjectMap headers, name, value) <- get
        let msgIdOjbect = listToMaybe $ map snd $ filter (\(k, v) -> k == msgIdKey) headers
            msgId = case msgIdOjbect of
                Just (ObjectRAW i) -> Just i
                _ -> Nothing
            headers' = filter (\(k, v) -> k /= versionKey) headers
        return $ Event msgId headers name value

event :: Name -> a -> Event a
event = Event Nothing []

(.=) :: (OBJECT k, OBJECT v) => k -> v -> Header
key .= value = (toObject key, toObject value)
{-# INLINE (.=) #-}

heartbeat = event "_zpc_hb" ()
more = event "_zpc_more"

stream = event "STREAM"
streamDone = event "STREAM_DONE" ()

msgId :: ByteString -> Header
msgId i = msgIdKey .= i

version3 :: Header
version3 = versionKey .= (3 :: Int)

ping serverName = return ("pong", serverName)

inspect :: Event [String]
inspect = event "_zerorpc_inspect" []

sendEvent sock event@(Event Nothing hs n v) = do
    uuid <- liftIO nextRandom
    sendEvent sock (Event (Just $ toStrict $ toByteString uuid) hs n v)
sendEvent sock event = do
    send sock [] (toStrict $ pack event)

main = do
    value <- runZMQ $ do
        req <- socket Req
        connect req "tcp://127.0.0.1:1234"
        sendEvent req inspect
        result <- receive req
        return $ unpack result
    putStr $ ppShow (value :: Event Object)
