{-# LANGUAGE PackageImports #-}

module Network.ZeroRPC.Wire where

import qualified "mtl" Control.Monad.State.Lazy as S
import Data.MessagePack (Object(ObjectMap), OBJECT, Packable, Unpackable(get))
import Data.MessagePack (pack, unpack, toObject, from)
import System.ZMQ4.Monadic (Req(..), Receiver, Socket, ZMQ, Sender)
import System.ZMQ4.Monadic (runZMQ, socket, connect, send, receive, liftIO)
import Data.UUID.V4 (nextRandom)
import Data.Maybe (Maybe(..), listToMaybe, fromJust)
import Data.ByteString (ByteString)
import Control.Monad.IO.Class (MonadIO)
import Data.ByteString.Lazy (toStrict)
import Data.UUID (toByteString)
import "mtl" Control.Monad.Trans (lift)

import Network.ZeroRPC.Types (Header(..), Event(..), Name(..), ZeroRPC)

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

ensureMsgId :: MonadIO m => Event a -> m (Event a)
ensureMsgId e = do
    uuid <- liftIO nextRandom
    let isMsgId (k, v) = k == msgIdKey
        newMsgId = toStrict $ toByteString uuid
    return $ setDefault msgIdKey newMsgId e

ensureVersion3 :: Event a -> Event a
ensureVersion3 = setHeader versionKey (3 :: Int)

replaceOrAppend :: (a -> Bool) -> (a -> a) -> a -> [a] -> [a]
replaceOrAppend cond f d [] = [d]
replaceOrAppend cond f d (x:xs) | cond x = (f x):xs
replaceOrAppend cond f d (x:xs) | otherwise = x:(replaceOrAppend cond f d xs)

replaceOrAppendHeader :: (OBJECT k, OBJECT v) => (Header -> Header) -> k -> v -> Event a -> Event a
replaceOrAppendHeader update key val (Event hs n v) = Event hs' n v
    where
        key' = toObject key
        header = key' .= toObject val
        hs' = replaceOrAppend ((== key') . fst) update header hs

setDefault :: (OBJECT k, OBJECT v) => k -> v -> Event a -> Event a
setDefault = replaceOrAppendHeader id

setHeader :: (OBJECT k, OBJECT v) => k -> v -> Event a -> Event a
setHeader key val = replaceOrAppendHeader (const $ key .= val) key val

sendEvent :: (Sender t, Packable a) => Event a -> ZeroRPC z t ()
sendEvent e = do
    sock <- S.get
    e' <- ensureMsgId $ ensureVersion3 e
    lift $ send (fromJust sock) [] $ toStrict $ pack e'

recvEvent :: (Receiver t, Unpackable a) => ZeroRPC z t (Event a)
recvEvent = do
    sock <- S.get
    result <- lift $ receive (fromJust sock)
    return $ unpack result
