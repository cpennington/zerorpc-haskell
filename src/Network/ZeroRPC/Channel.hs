{-# LANGUAGE PackageImports #-}

module Network.ZeroRPC.Channel where

import Control.Applicative ((<$>), (<*>), pure)
import Control.Concurrent (forkIO)
import Control.Concurrent.STM (atomically, STM)
import Control.Concurrent.STM.TBQueue (isEmptyTBQueue, isFullTBQueue, newTBQueue, readTBQueue, writeTBQueue, TBQueue)
import Control.Concurrent.STM.TVar (readTVar, newTVar, TVar)
import Control.Exception (throw)
import Control.Monad (forever)
import Control.Monad (when, liftM, filterM)
import Data.ByteString (ByteString)
import Data.List (lookup, find)
import Data.Maybe (fromJust, listToMaybe)
import Data.MessagePack (Object, toObject, fromObject)
import Data.MessagePack (Packable, Unpackable)
import System.ZMQ4.Monadic (Sender, Receiver, liftIO, runZMQ, async)
import "mtl" Control.Monad.Trans (lift)

import Network.ZeroRPC.Types (Event(..), ZeroRPC)
import Network.ZeroRPC.Wire (msgIdKey, (.=), sendEvent, recvEvent, setDefault)

data ZChan a = ZChan {
    zcOut :: TBQueue (Event a)
  , zcIn :: TBQueue (Event a)
  , zcId :: ByteString
}

data ZChannels a = ZChannels {
    zcsIn :: TBQueue (Event a)
  , zcsOut :: TBQueue (Event a)
  , zcsChans :: TVar [ZChan a]
}

data Created a = New a | Existing a

raw x = case x of
    New x' -> x'
    Existing x' -> x'

replyToKey :: Object
replyToKey = toObject ("reply_to" :: String)

ensureReplyTo :: Event a -> Event a
ensureReplyTo e = setDefault replyToKey (chanId e) e

bufferSize = 100

chanId :: Event a -> ByteString
chanId (Event hs n v) = fromObject $ case lookup replyToKey hs of
    Nothing -> fromJust $ lookup msgIdKey hs
    Just replyTo -> replyTo

getZChan :: [ZChan a] -> Event a -> STM (Created (ZChan a))
getZChan chans event = do
    let cid = chanId event
    newChan <- ZChan <$> (newTBQueue bufferSize) <*> (newTBQueue bufferSize) <*> pure cid
    return $ maybe (New newChan) Existing (find ((== cid) . zcId) chans)

_multiplexRecv :: TBQueue (Event a) -> [ZChan a] -> STM ()
_multiplexRecv incoming chans = do
    e@(Event hs n v) <- readTBQueue incoming
    chan <- getZChan chans e
    writeTBQueue (zcIn $ raw chan) $ ensureReplyTo e

multiplexRecv :: ZChannels a -> IO ()
multiplexRecv zchans = atomically $ do
    chans <- readTVar $ zcsChans zchans
    _multiplexRecv (zcsIn zchans) chans

_multiplexSend :: TBQueue (Event a) -> ZChan a -> STM ()
_multiplexSend outgoing zchan = do
    event  <- readTBQueue $ zcOut zchan
    writeTBQueue outgoing $ ensureReplyTo event

_channelSend :: (Sender t, Packable a) => TBQueue (Event a) -> ZeroRPC z t ()
_channelSend outgoing = do
    event <- liftIO $ atomically $ readTBQueue outgoing
    sendEvent event

channelSend :: (Sender t, Packable a) => ZChannels a -> ZeroRPC z t ()
channelSend = _channelSend . zcsOut

_channelRecv :: (Receiver t, Unpackable a) => TBQueue (Event a) -> ZeroRPC z t ()
_channelRecv incoming = do
    event <- recvEvent
    liftIO $ atomically $ writeTBQueue incoming event

channelRecv :: (Receiver t, Unpackable a) => ZChannels a -> ZeroRPC z t ()
channelRecv = _channelRecv . zcsIn

send :: ZChannels a -> Event a -> IO (Created (ZChan a))
send zchans event = do
    zchan <- atomically $ do
        chans <- readTVar $ zcsChans zchans
        zchan <- getZChan chans event
        writeTBQueue (zcOut $ raw zchan) event
        return zchan
    case zchan of
        New chan -> do
            forkIO $ forever $ atomically $ _multiplexSend (zcsOut zchans) chan
            return ()
        Existing chan -> return ()
    return zchan

newZChannels = ZChannels <$> newTBQueue bufferSize <*> newTBQueue bufferSize <*> newTVar []

setupZChannels :: (Receiver t, Sender t, Packable a, Unpackable a) => ZeroRPC z t (ZChannels a)
setupZChannels = do
    zchans <- lift $ liftIO $ atomically $ newZChannels
    lift $ async $ forever $ liftIO $ multiplexRecv zchans
    recvForever <- forever $ channelRecv zchans
    lift $ async recvForever
    sendForever <- forever $ channelSend zchans
    lift $ async sendForever
    return zchans
