{-# LANGUAGE PackageImports #-}

module Network.ZeroRPC.Wire where

import Data.MessagePack (Object(ObjectMap), OBJECT, Packable, Unpackable(get))
import Data.MessagePack (pack, unpack, toObject, from, fromObject)
import System.ZMQ4.Monadic (Receiver, Socket, ZMQ, Sender)
import System.ZMQ4.Monadic (send, receive)
import Data.Maybe (maybeToList, isNothing, fromJust)
import Data.ByteString (ByteString)
import Control.Monad (when)
import Data.ByteString.Lazy (toStrict)
import Data.Text (Text)

type Header = (Object, Object)
type Name = Text

data Event = Event {
    eMsgId :: !ByteString
  , eVersion :: !Int
  , eResponseTo :: !(Maybe ByteString)
  , eHeaders :: ![Header]
  , eName :: !Name
  , eArgs :: !Object
} deriving Show

instance Packable Event where
    from event = from (ObjectMap hs, n, v)
        where
            hs = maybeToList replyTo ++ msgId:version:(strip [msgIdKey, versionKey] $ eHeaders event)
            msgId = (msgIdKey .= eMsgId event)
            version = (versionKey .= eVersion event)
            replyTo = fmap (replyToKey .=) (eResponseTo event)
            n = eName event
            v = eArgs event

instance Unpackable Event where
    get = do
        (ObjectMap headers, name, args) <- get
        let msgId = lookup msgIdKey headers
            version = lookup versionKey headers
            replyTo = lookup replyToKey headers
        when (isNothing msgId) $ fail "message_id is required"
        when (isNothing version) $ fail "version is required"
        return $ Event {
            eMsgId = (fromObject $ fromJust msgId)
          , eVersion = (fromObject $ fromJust version)
          , eResponseTo = (fmap fromObject replyTo)
          , eHeaders = (strip [msgIdKey, versionKey, replyToKey] headers)
          , eName = name
          , eArgs = args
        }

msgIdKey :: Object
msgIdKey = toObject ("message_id" :: String)

versionKey :: Object
versionKey = toObject ("v" :: String)

replyToKey :: Object
replyToKey = toObject ("response_to" :: String)

strip :: [Object] -> [Header] -> [Header]
strip keys = filter ((flip elem keys) . fst)

(.=) :: (OBJECT k, OBJECT v) => k -> v -> Header
key .= value = (toObject key, toObject value)
{-# INLINE (.=) #-}

sendEvent :: (Sender t) => Socket z t -> Event -> ZMQ z ()
sendEvent sock event = send sock [] $ toStrict $ pack event

recvEvent :: (Receiver t) => Socket z t -> ZMQ z Event
recvEvent sock = do
    result <- receive sock
    return $ unpack result
