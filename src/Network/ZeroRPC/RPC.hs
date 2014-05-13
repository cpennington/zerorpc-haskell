{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE PackageImports #-}

module Network.ZeroRPC.RPC where

import Control.Concurrent.STM (atomically)
import Data.MessagePack (OBJECT, fromObject, toObject, Object(..))
import Control.Monad.Reader (runReaderT, ReaderT, ask)
import qualified System.ZMQ4.Monadic as Z
import "mtl" Control.Monad.Trans (lift)

import Network.ZeroRPC.Channel (send, recv, mkChannel, setupZChannels)
import Network.ZeroRPC.Types (Message(..), Client(..), Name, ARGS(..))

_reqSingle :: (ARGS a) => Client -> Message -> IO a
_reqSingle client msg = do
    zchan <- atomically $ mkChannel $ clChans client
    atomically $ send zchan msg
    resp <- atomically $ recv zchan
    case resp of
        OK value -> return $ fromArgs value
        otherwise -> fail $ show resp

call :: (ARGS a, ARGS b) => Client -> Name -> a -> IO b
call client fn args = _reqSingle client (Call fn $ toArgs args)

inspect :: Client -> IO Object
inspect = flip _reqSingle Inspect

mkClient :: (forall z. ReaderT (Z.Socket z Z.Req) (Z.ZMQ z) ()) -> IO Client
mkClient confSock = do
    let mkSock = do
            req <- Z.socket Z.Req
            runReaderT confSock req
            return req
    zchans <- setupZChannels mkSock
    return $ Client zchans

connect s = do
    sock <- ask
    lift $ Z.connect sock s