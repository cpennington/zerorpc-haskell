{-# LANGUAGE PackageImports #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE OverloadedStrings #-}

module Network.ZeroRPC.Channel where

import Control.Applicative ((<$>), (<*>), pure)
import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.STM (atomically, STM)
import Control.Concurrent.STM (isEmptyTBQueue, isFullTBQueue, newTBQueue, newTBQueueIO, readTBQueue, writeTBQueue, TBQueue)
import Control.Concurrent.STM (readTVar, writeTVar, newTVarIO, newTVar, TVar, modifyTVar', newEmptyTMVarIO)
import Control.Exception (throw)
import Control.Monad (forever, void, when, liftM, filterM)
import Data.ByteString (ByteString)
import Data.List (lookup, find)
import Data.Maybe (fromJust, listToMaybe, isNothing)
import Data.MessagePack (Object(..), toObject, fromObject, OBJECT)
import Data.MessagePack (Packable, Unpackable)
import System.ZMQ4.Monadic (Sender, Receiver, liftIO, runZMQ, async, ZMQ, Socket, Poll(..), poll)
import qualified System.ZMQ4.Monadic as Z
import "mtl" Control.Monad.Trans (lift)
import System.Random (StdGen, Random(..), split, newStdGen)
import Data.UUID (toASCIIBytes)
import Data.Text (Text)

import Network.ZeroRPC.Wire (Event(..), Header, Name, msgIdKey, (.=), sendEvent, recvEvent, replyToKey)

import Control.Exception (Exception)
import Control.Concurrent.STM (throwSTM, catchSTM, tryPeekTBQueue)
import Debug.Trace

type Callback = Maybe (ZChan -> IO ())

data Message = Call !Name !Object
             | Heartbeat
             | More !Int
             | Stream !Object
             | StreamDone
             | Inspect
             | OK !Object
             | Err !Name !Text !Text  -- (error name, error message, traceback)
    deriving (Show, Eq)

data ZChan = ZChan {
    zcOut :: TBQueue (Message)
  , zcIn :: TBQueue (Message)
  , zcId :: TVar (Maybe ByteString)
  , zcGen :: TVar StdGen
}

data ZChannels = ZChannels {
    zcsIn :: TBQueue Event
  , zcsOut :: TBQueue Event
  , zcsChans :: TVar [ZChan]
  , zcsGen :: TVar StdGen
  , zcsNewChans :: TBQueue ZChan
  , zcsCallback :: Callback
}

ensureReplyTo :: ZChan -> Event -> STM Event
ensureReplyTo chan event = do
    cid <- readTVar $ zcId chan
    case cid of
        Nothing -> do
            writeTVar (zcId chan) $ Just $ chanId event
            return event
        Just id -> return $ event {eResponseTo = Just id}

bufferSize = 100

chanId :: Event -> ByteString
chanId event = maybe (eMsgId event) id (eResponseTo event)

getZChan :: ZChannels -> Event -> STM (Maybe ZChan)
getZChan zchans event = do
    chans <- readTVar $ zcsChans zchans
    let cid = chanId event
    chanIds <- mapM (readTVar . zcId) chans
    return $ lookup (Just cid) $ zip chanIds chans

multiplexRecv :: ZChannels -> IO ()
multiplexRecv zchans = atomically $ do
    let incoming = zcsIn zchans
    chans <- readTVar $ zcsChans zchans
    event <- readTBQueue incoming
    maybeChan <- getZChan zchans event
    chan <- case maybeChan of
        Nothing -> addNewChannel zchans
        Just chan -> return chan
    msg <- toMsg chan event
    writeTBQueue (zcIn chan) (traceShow ("multirecv", msg) $ msg)

_multiplexSend :: TBQueue Event -> ZChan -> STM ()
_multiplexSend outgoing chan = do
    msg <- readTBQueue $ zcOut chan
    event <- toEvent chan msg
    writeTBQueue outgoing (traceShow ("multisend", event) $ event)

_channelSend :: (Sender t) => TBQueue Event -> Socket z t -> ZMQ z ()
_channelSend outgoing sock = do
    event <- liftIO $ atomically $ readTBQueue outgoing
    sendEvent sock (traceShow ("channelSend", event) $ event)

channelSend :: (Sender t) => ZChannels -> Socket z t -> ZMQ z ()
channelSend = _channelSend . zcsOut

_channelRecv :: (Receiver t) => TBQueue Event -> Socket z t -> ZMQ z ()
_channelRecv incoming sock = do
    event <- recvEvent sock
    liftIO $ atomically $ writeTBQueue incoming (traceShow ("recv", event) $ event)

channelRecv :: (Receiver t) => ZChannels -> Socket z t -> ZMQ z ()
channelRecv = _channelRecv . zcsIn

channelPoll :: (Sender t, Receiver t) => Socket z t -> ZChannels -> ZMQ z ()
channelPoll sock chans = void $ poll 1000 [sendPoll sock chans, recvPoll sock chans]

sendPoll :: (Sender t) => Socket z t -> ZChannels -> Poll (Socket z) (ZMQ z)
sendPoll sock chans = Sock sock [Z.Out] (Just callback)
    where
        callback [Z.Out] = channelSend chans sock
        callback _ = return ()

recvPoll :: (Receiver t) => Socket z t -> ZChannels -> Poll (Socket z) (ZMQ z)
recvPoll sock chans = Sock sock [Z.In] (Just callback)
    where
        callback [Z.In] = channelRecv chans sock
        callback _ = return ()

nextMsgId :: ZChan -> STM ByteString
nextMsgId chan = do
    gen <- readTVar (zcGen chan)
    let (uuid, gen') = random gen
    writeTVar (zcGen chan) gen'
    return $ toASCIIBytes uuid

setChanId :: ZChan -> ByteString -> STM ()
setChanId chan msgId = do
    chanId <- readTVar $ zcId chan
    when (isNothing chanId) $ writeTVar (zcId chan) (Just msgId)

getResponseTo :: ZChan -> ByteString -> STM (Maybe ByteString)
getResponseTo chan msgId = do
    chanId <- readTVar $ zcId chan
    setChanId chan msgId
    return chanId

_toEvent :: ZChan -> [Header] -> Name -> Object -> STM Event
_toEvent chan headers name value = do
    msgId <- nextMsgId chan
    responseTo <- getResponseTo chan msgId
    return $ Event msgId 3 responseTo headers name value


toEvent :: ZChan -> Message -> STM Event
toEvent chan msg =
    case msg of
        Heartbeat -> empty "_zpc_hb"
        Inspect -> empty "_zerorpc_inspect"
        (Call name value) -> val name value
        (More count) -> val "_zpc_more" count
        (Stream value) -> val "STREAM" value
        StreamDone -> empty "STREAM_DONE"
        (OK value) -> val "OK" value
        (Err name err trace) -> val "ERR" (name, err, trace)
    where
        val name value = _toEvent chan [] name $ toObject value
        empty name = _toEvent chan [] name $ ObjectArray []

toMsg :: ZChan -> Event -> STM (Message)
toMsg chan event = do
    -- This initializes the ZChan with the appropriate channel id
    setChanId chan (eMsgId event)
    let val cons = return $ cons $ fromObject $ eArgs event
        empty cons = return cons
    case eName event of
        "OK" -> val OK
        "_zpc_hb" -> empty Heartbeat
        "_zerorpc_inspect" -> empty Inspect
        "_zpc_more" -> val More
        "STREAM" -> val Stream
        "STREAM_DONE" -> empty StreamDone
        "ERR" -> do
            let (name, err, trace) = fromObject $ eArgs event
            return $ Err name err trace
        otherwise -> val $ Call (eName event)

mkGen :: ZChannels -> STM StdGen
mkGen zchans = do
    baseGen <- readTVar $ zcsGen zchans
    let (baseGen', newGen) = split baseGen
    writeTVar (zcsGen zchans) baseGen
    return newGen

addChan :: ZChannels -> ZChan -> STM ()
addChan zchans chan = do
    modifyTVar' (zcsChans zchans) (chan:)
    writeTBQueue (zcsNewChans zchans) chan

mkChannel :: StdGen -> STM ZChan
mkChannel gen = ZChan <$> (newTBQueue bufferSize) <*> (newTBQueue bufferSize) <*> (newTVar Nothing) <*> (newTVar gen)

addNewChannel :: ZChannels -> STM ZChan
addNewChannel zchans = do
    gen <- mkGen zchans
    chan <- mkChannel gen
    addChan zchans chan
    return chan

mkZChannels :: Callback -> IO ZChannels
mkZChannels callback = ZChannels
    <$> newTBQueueIO bufferSize
    <*> newTBQueueIO bufferSize
    <*> newTVarIO []
    <*> (newStdGen >>= newTVarIO)
    <*> newTBQueueIO bufferSize
    <*> pure callback

setupNewChannel zchans = do
    chan <- atomically $ readTBQueue $ zcsNewChans zchans
    case zcsCallback zchans of
        Nothing -> return ()
        Just callback -> callback chan
    forkIO $ forever $ atomically $ _multiplexSend (zcsOut zchans) chan
    forkIO $ forever $ sendHeartbeat chan

heartbeatInterval = 5000000

sendHeartbeat :: ZChan -> IO ()
sendHeartbeat chan = do
    threadDelay heartbeatInterval
    atomically $ send chan Heartbeat

send :: ZChan -> Message -> STM ()
send chan msg = writeTBQueue (zcOut chan) msg

recv :: ZChan -> STM Message
recv chan = readTBQueue (zcIn chan)

setupZChannels :: (Receiver t, Sender t) => (forall z. ZMQ z (Socket z t)) -> Callback -> IO ZChannels
setupZChannels mkSock callback = do
    zchans <- mkZChannels callback
    forkIO $ forever $ setupNewChannel zchans
    forkIO $ forever $ multiplexRecv zchans
    forkIO $ runZMQ $ do
        sock <- mkSock
        forever $ channelPoll sock zchans
    return zchans