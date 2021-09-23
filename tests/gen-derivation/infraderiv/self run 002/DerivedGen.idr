module DerivedGen

import AlternativeCore
import RunDerivedGen

%default total

%language ElabReflection

checkedGen : Fuel -> Gen Bool
checkedGen = deriveGen @{CallSelf}

main : IO Unit
main = runGs [ G checkedGen ]
