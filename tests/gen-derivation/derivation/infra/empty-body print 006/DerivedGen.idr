module DerivedGen

import AlternativeCore
import PrintDerivation

import Data.Vect

%default total

%language ElabReflection

%runElab printDerived @{EmptyBody} $ Fuel -> (a : Type) -> Gen (n : Nat ** Vect n a)
