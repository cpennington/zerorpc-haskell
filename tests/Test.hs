import Test.Tasty (defaultMain, testGroup)

import qualified Network.ZeroRPC.Wire.Test as W

tests = testGroup "Tests" [W.qcProps]
main = defaultMain tests