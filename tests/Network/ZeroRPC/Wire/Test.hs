module Network.ZeroRPC.Wire.Test where

import Test.Tasty (testGroup)
import Test.Tasty.QuickCheck (arbitrary, Arbitrary, oneof, (===), Gen, choose, vectorOf, sample, testProperty, sized, Property)
import Data.MessagePack.Object (fromObject, toObject, Object(..))
import Data.MessagePack.Pack (pack)
import Data.MessagePack.Unpack (unpack)
import Control.Applicative ((<*>), (<$>))
import Network.ZeroRPC.Wire (Event(..))
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import qualified Data.Text as T

instance Arbitrary B.ByteString where
    arbitrary = BC.pack <$> arbitrary

instance Arbitrary T.Text where
    arbitrary = T.pack <$> arbitrary

instance Arbitrary Event where
    arbitrary = Event
        <$> arbitrary
        <*> arbitrary
        <*> arbitrary
        <*> arbitrary
        <*> arbitrary
        <*> arbitrary

instance Arbitrary Object where
  arbitrary = sized sizedArbObject

arbObjLiteral = oneof [
      return ObjectNil
    , ObjectBool <$> arbitrary
    , ObjectInteger <$> arbitrary
    , ObjectFloat <$> arbitrary
    , ObjectDouble <$> arbitrary
    , (ObjectRAW . B.pack) <$> arbitrary
    , return $ ObjectArray []
    , return $ ObjectMap []
    ]


sizedArbObject :: Int -> Gen Object
sizedArbObject 0 = arbObjLiteral
sizedArbObject n = oneof [
      arbObjLiteral
    , ObjectArray <$> smallListOf subobject
    , ObjectMap <$> smallListOf ((,) <$> arbObjLiteral <*> subobject)
    ]
    where
      subobject = sizedArbObject $ n `div` 5
      smallListOf g = do
        size <- choose (0, 10)
        vectorOf size g

printSamples = sample (arbitrary :: Gen Object)

prop_ObjectRoundtrip :: Event -> Property
prop_ObjectRoundtrip e = e === (fromObject $ toObject e)

prop_BytestringRoundtrip :: Event -> Property
prop_BytestringRoundtrip e = e === (unpack $ pack e)

qcProps = testGroup "(checked by QuickCheck)" [
    testProperty "fromObject . toObject == id" prop_BytestringRoundtrip,
    testProperty "unpack . pack == id" prop_ObjectRoundtrip
    ]