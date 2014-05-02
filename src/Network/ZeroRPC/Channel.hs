module Network.ZeroRPC.Channel where

import Control.Applicative ((<$>), (<*>), pure)
import Control.Concurrent.STM.TBQueue (isEmptyTBQueue, isFullTBQueue, newTBQueue, readTBQueue, writeTBQueue, TBQueue)
import Control.Concurrent.STM (atomically, STM)
import Data.ByteString (ByteString)
import Data.MessagePack (Object, toObject, fromObject)
import Data.Maybe (fromJust, listToMaybe)
import Control.Monad (when, liftM, filterM)
import Control.Exception (throw)
import Data.List (lookup, find)

import Network.ZeroRPC.Types (Event(..))
import Network.ZeroRPC.Wire (msgIdKey, (.=))

data ZChan a = ZChan {
    zcOut :: TBQueue (Event a)
  , zcIn :: TBQueue (Event a)
  , zcId :: ByteString
  }

replyToKey :: Object
replyToKey = toObject ("reply_to" :: String)

ensureReplyTo = undefined

bufferSize = 100

getZChan chans chanId = do
    newChan <- ZChan <$> (newTBQueue bufferSize) <*> (newTBQueue bufferSize) <*> pure chanId
    return $ maybe newChan id (lookup chanId chans)

multiplexRecv :: TBQueue (Event a) -> [(ByteString, ZChan a)] -> STM ()
multiplexRecv incoming chans = do
    e@(Event hs n v) <- readTBQueue incoming
    case lookup replyToKey hs of
        Nothing -> do
            let messageId = fromObject $ fromJust $ lookup msgIdKey hs
            chan <- getZChan chans messageId
            writeTBQueue (zcIn chan) $ Event ((replyToKey .= messageId):hs) n v
        Just replyTo -> do
            chan <- getZChan chans $ fromObject replyTo
            writeTBQueue (zcIn chan) e

sendReady ::ZChan a -> STM Bool
sendReady zchan = do
    let chan = zcOut zchan
    empty <- isEmptyTBQueue chan
    return $ not empty

multiplexSend :: TBQueue (Event a) -> [(ByteString, ZChan a)] -> STM ()
multiplexSend outgoing chans = do
    readyChans <- filterM sendReady $ map snd chans
    case listToMaybe readyChans of
        Nothing -> return ()
        Just zchan -> do
            (Event hs n v) <- readTBQueue $ zcOut zchan
            writeTBQueue outgoing (Event (ensureReplyTo hs $ zcId zchan) n v)