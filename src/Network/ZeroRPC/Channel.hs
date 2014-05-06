{-# LANGUAGE PackageImports #-}
{-# LANGUAGE RankNTypes #-}

module Network.ZeroRPC.Channel where

import Control.Applicative ((<$>), (<*>), pure)
import Control.Concurrent (forkIO)
import Control.Concurrent.STM (atomically, STM)
import Control.Concurrent.STM (isEmptyTBQueue, isFullTBQueue, newTBQueue, readTBQueue, writeTBQueue, TBQueue)
import Control.Concurrent.STM (readTVar, writeTVar, newTVar, TVar)
import Control.Exception (throw)
import Control.Monad (forever, void)
import Control.Monad (when, liftM, filterM)
import Data.ByteString (ByteString)
import Data.List (lookup, find)
import Data.Maybe (fromJust, listToMaybe)
import Data.MessagePack (Object, toObject, fromObject)
import Data.MessagePack (Packable, Unpackable)
import System.ZMQ4.Monadic (Sender, Receiver, liftIO, runZMQ, async, ZMQ, Socket, Poll(..), poll)
import qualified System.ZMQ4.Monadic as Z
import "mtl" Control.Monad.Trans (lift)

import Network.ZeroRPC.Types (Event(..))
import Network.ZeroRPC.Wire (msgIdKey, (.=), sendEvent, recvEvent, setDefault, ensureVersion3, ensureMsgId)

import Control.Exception (Exception)
import Control.Concurrent.STM (throwSTM, catchSTM, tryPeekTBQueue)
import Debug.Trace

data ZChan a = ZChan {
    zcOut :: TBQueue (Event a)
  , zcIn :: TBQueue (Event a)
  , zcId :: TVar (Maybe ByteString)
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
replyToKey = toObject ("response_to" :: String)

ensureReplyTo :: ZChan a -> Event a -> STM (Event a)
ensureReplyTo chan event = do
    cid <- readTVar $ zcId chan
    case cid of
        Nothing -> do
            writeTVar (zcId chan) $ Just $ chanId event
            return event
        Just id -> return $ setDefault replyToKey id event

bufferSize = 100

chanId :: Event a -> ByteString
chanId (Event hs n v) = fromObject $ case lookup replyToKey hs of
    Nothing -> fromJust $ lookup msgIdKey hs
    Just replyTo -> replyTo

getZChan :: ZChannels a -> Event a -> STM (Created (ZChan a))
getZChan zchans event = do
    chans <- readTVar $ zcsChans zchans
    let cid = chanId event
    newChan <- ZChan <$> (newTBQueue bufferSize) <*> (newTBQueue bufferSize) <*> (newTVar Nothing)
    chanIds <- mapM (readTVar . zcId) chans
    case (find ((== (Just cid)) . fst) $ zip chanIds chans) of
        Nothing -> do
            writeTVar (zcsChans zchans) (newChan:chans)
            return $ New newChan
        Just (_, chan) -> return $ Existing chan

multiplexRecv :: (Show a) => ZChannels a -> IO ()
multiplexRecv zchans = atomically $ do
    let incoming = zcsIn zchans
    chans <- readTVar $ zcsChans zchans
    event <- readTBQueue incoming
    chan <- getZChan zchans event
    event' <- ensureReplyTo (raw chan) event
    writeTBQueue (zcIn $ raw chan) (traceShow ("multirecv", event') $ event')

_multiplexSend :: (Show a) => TBQueue (Event a) -> ZChan a -> STM ()
_multiplexSend outgoing zchan = do
    event  <- readTBQueue $ zcOut zchan
    event' <- ensureReplyTo zchan event
    writeTBQueue outgoing (traceShow ("multisend", event') $ event')

_channelSend :: (Sender t, Packable a, Show a) => TBQueue (Event a) -> Socket z t -> ZMQ z ()
_channelSend outgoing sock = do
    event <- liftIO $ atomically $ readTBQueue outgoing
    sendEvent sock (traceShow ("channelSend", event) $ event)

channelSend :: (Sender t, Packable a, Show a) => ZChannels a -> Socket z t -> ZMQ z ()
channelSend = _channelSend . zcsOut

_channelRecv :: (Receiver t, Unpackable a, Show a) => TBQueue (Event a) -> Socket z t -> ZMQ z ()
_channelRecv incoming sock = do
    event <- recvEvent sock
    liftIO $ atomically $ writeTBQueue incoming (traceShow ("recv", event) $ event)

channelRecv :: (Receiver t, Unpackable a, Show a) => ZChannels a -> Socket z t -> ZMQ z ()
channelRecv = _channelRecv . zcsIn

channelPoll :: (Sender t, Receiver t, Unpackable a, Packable a, Show a) => Socket z t -> ZChannels a -> ZMQ z ()
channelPoll sock chans = void $ poll 1000 [sendPoll sock chans, recvPoll sock chans]

sendPoll :: (Sender t, Packable a, Show a) => Socket z t -> ZChannels a -> Poll (Socket z) (ZMQ z)
sendPoll sock chans = Sock sock [Z.Out] (Just callback)
    where
        callback [Z.Out] = channelSend chans sock
        callback _ = return ()

recvPoll :: (Receiver t, Unpackable a, Show a) => Socket z t -> ZChannels a -> Poll (Socket z) (ZMQ z)
recvPoll sock chans = Sock sock [Z.In] (Just callback)
    where
        callback [Z.In] = channelRecv chans sock
        callback _ = return ()

send :: (Show a) => ZChannels a -> Event a -> IO (Created (ZChan a))
send zchans event = do
    event' <- ensureMsgId $ ensureVersion3 event
    zchan <- atomically $ do
        chans <- readTVar $ zcsChans zchans
        zchan <- getZChan zchans event
        writeTBQueue (zcOut $ raw zchan) (traceShow ("send", event') $ event')
        return zchan
    case zchan of
        New chan -> do
            forkIO $ forever $ atomically $ _multiplexSend (zcsOut zchans) chan
            return ()
        Existing chan -> return ()
    return zchan

newZChannels = ZChannels <$> newTBQueue bufferSize <*> newTBQueue bufferSize <*> newTVar []

setupZChannels :: (Receiver t, Sender t, Unpackable a, Packable a, Show a) => (forall z. ZMQ z (Socket z t)) -> IO (ZChannels a)
setupZChannels mkSock = do
    zchans <- atomically newZChannels
    forkIO $ forever $ multiplexRecv zchans
    forkIO $ runZMQ $ do
        sock <- mkSock
        forever $ channelPoll sock zchans
    return zchans
