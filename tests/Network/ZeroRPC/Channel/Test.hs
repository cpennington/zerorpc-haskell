module Network.ZeroRPC.Channel.Test where

import Test.Tasty (testGroup)
import Test.Tasty.QuickCheck (Arbitrary, arbitrary, oneof, property, ioProperty, testProperty, (===), Property)
import Control.Applicative ((<$>), (<*>), pure)
import Data.MessagePack.Object (fromObject, toObject, Object(..))
import Data.ByteString.Char8 (pack)
import Control.Applicative ((<*>), (<$>))
import Network.ZeroRPC.Channel (toMsg, toEvent, Message(..), mkChannel)
import Network.ZeroRPC.Wire (Event(..))
import Control.Concurrent.STM (atomically)
import qualified Network.ZeroRPC.Wire.Test as WT
import System.Random (mkStdGen)

instance Arbitrary Message where
    arbitrary = oneof [
        Call <$> arbitrary <*> arbitrary
      , pure Heartbeat
      , More <$> arbitrary
      , Stream <$> arbitrary
      , pure StreamDone
      , pure Inspect
      , OK <$> arbitrary
      , Err <$> arbitrary <*> arbitrary <*> arbitrary
      ]

prop_MessageRoundtrip :: Message -> Property
prop_MessageRoundtrip m = ioProperty $ atomically $ do
    chan <- mkChannel $ mkStdGen 0
    (toEvent chan m) >>= (toMsg chan) >>= return . (=== m)

--prop_EventRoundtrip :: Event -> Property
--prop_EventRoundtrip e = ioProperty $ atomically $ do
--    chan <- mkChannel $ mkStdGen 0
--    m <- toMsg chan e
--    e' <- toEvent chan m
--    return (e' {eMsgId = (pack ""), eResponseTo = Nothing} === e {eVersion = 3})

qcProps = testGroup "(checked by QuickCheck)" [
    testProperty "toMsg . toEvent == id" prop_MessageRoundtrip
  --, testProperty "toEvent . toMsg == id" prop_EventRoundtrip
    ]