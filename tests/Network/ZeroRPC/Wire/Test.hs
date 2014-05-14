module Network.ZeroRPC.Wire.Test where

import Test.Tasty (testGroup)
import qualified Test.Tasty.QuickCheck as QC
import Data.MessagePack.Object (fromObject, toObject, Object(..))
import Data.MessagePack.Pack (pack)
import Data.MessagePack.Unpack (unpack)
import Control.Applicative ((<*>), (<$>))
import Network.ZeroRPC.Wire (Event(..))
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import qualified Data.Text as T

instance QC.Arbitrary B.ByteString where
    arbitrary = BC.pack <$> QC.arbitrary

instance QC.Arbitrary T.Text where
    arbitrary = T.pack <$> QC.arbitrary

instance QC.Arbitrary Event where
    arbitrary = Event
        <$> QC.arbitrary
        <*> QC.arbitrary
        <*> QC.arbitrary
        <*> QC.arbitrary
        <*> QC.arbitrary
        <*> QC.arbitrary

instance QC.Arbitrary Object where
  arbitrary = QC.sized sizedArbObject

arbObjLiteral = QC.oneof [
      return ObjectNil
    , ObjectBool <$> QC.arbitrary
    , ObjectInteger <$> QC.arbitrary
    , ObjectFloat <$> QC.arbitrary
    , ObjectDouble <$> QC.arbitrary
    , (ObjectRAW . B.pack) <$> QC.arbitrary
    , return $ ObjectArray []
    , return $ ObjectMap []
    ]


sizedArbObject :: Int -> QC.Gen Object
sizedArbObject 0 = arbObjLiteral
sizedArbObject n = QC.oneof [
      arbObjLiteral
    , ObjectArray <$> smallListOf subobject
    , ObjectMap <$> smallListOf ((,) <$> arbObjLiteral <*> subobject)
    ]
    where
      subobject = sizedArbObject $ n `div` 5
      smallListOf g = do
        size <- QC.choose (0, 10)
        QC.vectorOf size g

printSamples = QC.sample (QC.arbitrary :: QC.Gen Object)

prop_ObjectRoundtrip :: Event -> Bool
prop_ObjectRoundtrip e = e == (fromObject $ toObject e)

prop_BytestringRoundtrip :: Event -> Bool
prop_BytestringRoundtrip e = e == (unpack $ pack e)

qcProps = testGroup "(checked by QuickCheck)" [
    QC.testProperty "fromObject . toObject == id" prop_BytestringRoundtrip,
    QC.testProperty "unpack . pack == id" prop_ObjectRoundtrip
    ]