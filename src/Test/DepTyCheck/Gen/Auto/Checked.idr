module Test.DepTyCheck.Gen.Auto.Checked

import public Control.Monad.Reader
import public Control.Monad.Trans
import public Control.Monad.Writer

import public Data.SortedMap
import public Data.SortedSet

import public Language.Reflection.Types

import public Test.DepTyCheck.Gen.Auto.Util

%default total

-----------------------------------------------------
--- Data types for the safe signature formulation ---
-----------------------------------------------------

public export
data ArgExplicitness = ExplicitArg | ImplicitArg

public export
Eq ArgExplicitness where
  ExplicitArg == ExplicitArg = True
  ImplicitArg == ImplicitArg = True
  _ == _ = False

namespace ArgExplicitness

  public export
  (.toTT) : ArgExplicitness -> PiInfo a
  (.toTT) ExplicitArg = ExplicitArg
  (.toTT) ImplicitArg = ImplicitArg

------------------------------------------------------------------
--- Datatypes to describe signatures after checking user input ---
------------------------------------------------------------------

public export
record GenSignature where
  constructor MkGenSignature
  targetType : TypeInfo
  givenParams : SortedMap (Fin targetType.args.length) (ArgExplicitness, Name)

namespace GenSignature

  characteristics : GenSignature -> (String, List Nat)
  characteristics (MkGenSignature ty giv) = (show ty.name, toNatList $ keys giv)

public export
Eq GenSignature where
  (==) = (==) `on` characteristics

public export
Ord GenSignature where
  compare = comparing characteristics

public export
record GenExternals where
  constructor MkGenExternals
  externals : SortedSet GenSignature

-----------------------------------
--- "Canonical" functions stuff ---
-----------------------------------

--- Main interfaces ---

public export
interface Monad m => CanonicName m where
  canonicName : GenSignature -> m Name

--- Canonic signature functions --

-- Must respect names from the `givenParams` field, at least for implicit parameters
export
canonicSig : GenSignature -> TTImp
canonicSig sig = piAll returnTy $ arg <$> toList sig.givenParams where

  -- should be a memoized constant
  givensRenamingRules : List (TTImp -> TTImp)
  givensRenamingRules = mapMaybeI' sig.targetType.args $ \idx, (MkArg _ _ name _) => substNameIn name . snd <$> lookup idx sig.givenParams

  -- Renames all names that are present in the target type declaration to their according names in the gen signature
  renameGivens : TTImp -> TTImp
  renameGivens expr = foldr apply expr givensRenamingRules

  arg : (Fin sig.targetType.args.length, ArgExplicitness, Name) -> Arg False
  arg (idx, expl, name) = MkArg MW .| expl.toTT .| Just name .| renameGivens (index' sig.targetType.args idx).type

  returnTy : TTImp
  returnTy = var `{Test.DepTyCheck.Gen.Gen} .$ buildDPair targetTypeApplied generatedArgs where

    targetTypeApplied : TTImp
    targetTypeApplied = foldr apply (var sig.targetType.name) $ reverse $ mapI' sig.targetType.args $ \idx, (MkArg {name, piInfo, _}) =>
                          let name = maybe name snd $ lookup idx sig.givenParams in
                          case piInfo of
                            ExplicitArg   => (.$ var name)
                            ImplicitArg   => \f => namedApp f name $ var name
                            DefImplicit _ => \f => namedApp f name $ var name
                            AutoImplicit  => (`autoApp` var name)

    generatedArgs : List (Name, TTImp)
    generatedArgs = mapMaybeI' sig.targetType.args $ \idx, (MkArg _ _ name type) =>
                      case lookup idx sig.givenParams of
                        Nothing => Just (name, renameGivens type)
                        Just _  => Nothing

export
callCanonicGen : CanonicName m => (sig : GenSignature) -> Vect sig.givenParams.asList.length TTImp -> m TTImp
callCanonicGen sig values = canonicName sig <&> (`appAll` toList values)

export
deriveCanonical : CanonicName m => GenSignature -> m Decl
deriveCanonical sig = do
  ?deriveCanonical_rhs

--- Implementations for the canonic interfaces ---

MonadReader (SortedMap GenSignature Name) m =>
MonadWriter (SortedMap GenSignature $ Lazy Decl) m =>
CanonicName m where
  canonicName sig = do
    let Nothing = lookup sig !ask
      | Just n => pure n
    ?canonocName_impl
--    tell $ singleton sig $ delay !(deriveCanonical sig) -- looks like `deriveCanonical` is called not in a lazy way
--    pure $ MN "\{show sig.targetType.name} given \{show sig.givenParams}" 0

--- Canonic-dischagring function ---

export
runCanonic : GenExternals -> (forall m. CanonicName m => m a) -> Elab (a, List Decl)
runCanonic exts calc = ?runCanonic_rhs
