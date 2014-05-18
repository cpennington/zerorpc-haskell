import Test.Tasty (defaultMain, testGroup)

import qualified Network.ZeroRPC.Wire.Test as W
import qualified Network.ZeroRPC.Channel.Test as C
import qualified Network.ZeroRPC.RPC.Test as R

tests = testGroup "Tests" [W.qcProps, R.qcProps, C.qcProps]
main = defaultMain tests