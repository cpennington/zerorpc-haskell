module Network.ZeroRPC.RPC.Test where

import Test.Tasty (testGroup)
import qualified Test.Tasty.QuickCheck as QC
import Data.MessagePack.Object (fromObject, toObject, Object(..))
import Data.MessagePack.Pack (pack)
import Data.MessagePack.Unpack (unpack)
import Control.Applicative ((<*>), (<$>))
import Network.ZeroRPC.RPC (ObjectSpec(..), FunctionSpec(..))
import qualified Network.ZeroRPC.Wire.Test as WT
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import qualified Data.Text as T

instance QC.Arbitrary ObjectSpec where
    arbitrary = ObjectSpec <$> QC.arbitrary <*> QC.arbitrary

instance QC.Arbitrary FunctionSpec where
    arbitrary = FunctionSpec <$> QC.arbitrary <*> QC.arbitrary <*> QC.arbitrary

prop_ObjectRoundtrip :: ObjectSpec -> Bool
prop_ObjectRoundtrip os = os == (fromObject $ toObject os)

prop_BytestringRoundtrip :: ObjectSpec -> Bool
prop_BytestringRoundtrip os = os == (unpack $ pack os)

qcProps = testGroup "(checked by QuickCheck)" [
    QC.testProperty "fromObject . toObject == id" prop_BytestringRoundtrip,
    QC.testProperty "unpack . pack == id" prop_ObjectRoundtrip
    ]