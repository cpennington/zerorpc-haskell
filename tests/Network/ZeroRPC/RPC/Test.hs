module Network.ZeroRPC.RPC.Test where

import Test.Tasty (testGroup)
import Test.Tasty.QuickCheck (Arbitrary, arbitrary, testProperty, (===), Property)
import Data.MessagePack.Object (fromObject, toObject, Object(..))
import Data.MessagePack.Pack (pack)
import Data.MessagePack.Unpack (unpack)
import Control.Applicative ((<*>), (<$>))
import Network.ZeroRPC.RPC (ObjectSpec(..), FunctionSpec(..))
import qualified Network.ZeroRPC.Wire.Test as WT

instance Arbitrary ObjectSpec where
    arbitrary = ObjectSpec <$> arbitrary <*> arbitrary

instance Arbitrary FunctionSpec where
    arbitrary = FunctionSpec <$> arbitrary <*> arbitrary <*> arbitrary

prop_ObjectRoundtrip :: ObjectSpec -> Property
prop_ObjectRoundtrip os = os === (fromObject $ toObject os)

prop_BytestringRoundtrip :: ObjectSpec -> Property
prop_BytestringRoundtrip os = os === (unpack $ pack os)

qcProps = testGroup "(checked by QuickCheck)" [
    testProperty "fromObject . toObject == id" prop_BytestringRoundtrip,
    testProperty "unpack . pack == id" prop_ObjectRoundtrip
    ]