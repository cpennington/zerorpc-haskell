{-# LANGUAGE PackageImports #-}

module Network.ZeroRPC.Wire where

import qualified "mtl" Control.Monad.State.Lazy as S
import Data.MessagePack (
    Object(..), OBJECT, Packable, Unpackable(..),
    pack, unpack, toObject, from
    )
import System.ZMQ4.Monadic (
    Req(..), Receiver, Socket, ZMQ, Sender,
    runZMQ, socket, connect, send, receive, liftIO
    )
import Data.UUID.V4 (nextRandom)
import Data.Maybe (Maybe(..), listToMaybe)
import Data.ByteString (ByteString)
import Control.Monad.IO.Class (MonadIO)
import Data.ByteString.Lazy (toStrict)
import Data.UUID (toByteString)
import "mtl" Control.Monad.Trans (lift)

import Network.ZeroRPC.Types (Header(..), Event(..), Name(..))

msgIdKey :: Object
msgIdKey = toObject ("message_id" :: String)

versionKey :: Object
versionKey = toObject ("v" :: String)

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

msgId :: ByteString -> Header
msgId i = msgIdKey .= i

version3 :: Header
version3 = versionKey .= (3 :: Int)

ensureMsgId :: MonadIO m => [Header] -> m [Header]
ensureMsgId hs = do
    uuid <- liftIO nextRandom
    let isMsgId (k, v) = k == msgIdKey
        newMsgId = msgId $ toStrict $ toByteString uuid
    return $ replaceOrAppend isMsgId id newMsgId hs

ensureVersion3 :: [Header] -> [Header]
ensureVersion3 hs = replaceOrAppend isVersionKey (const version3) version3 hs
    where isVersionKey (k, v) = k == versionKey

replaceOrAppend :: (a -> Bool) -> (a -> a) -> a -> [a] -> [a]
replaceOrAppend cond f d [] = [d]
replaceOrAppend cond f d (x:xs) | cond x = (f x):xs
replaceOrAppend cond f d (x:xs) | otherwise = x:(replaceOrAppend cond f d xs)

sendEvent :: (Sender t, Packable a) => Event a -> S.StateT (Socket z t) (ZMQ z) ()
sendEvent (Event hs n v) = do
    sock <- S.get
    hs' <- ensureMsgId hs
    lift $ send sock [] (toStrict $ pack (Event hs' n v))

recvEvent :: (Receiver t, Unpackable a) => S.StateT (Socket z t) (ZMQ z) (Event a)
recvEvent = do
    sock <- S.get
    result <- lift $ receive sock
    return $ unpack result
