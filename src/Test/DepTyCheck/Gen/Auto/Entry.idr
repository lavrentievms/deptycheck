||| External generation interface and aux stuff for that
module Test.DepTyCheck.Gen.Auto.Entry

import public Data.Either
import public Data.Fuel

import public Decidable.Equality

import public Debug.Reflection

import public Test.DepTyCheck.Gen -- for `Gen` data type
import public Test.DepTyCheck.Gen.Auto.Parsed

%default total

-----------------------------------------
--- Utility `TTImp`-related functions ---
-----------------------------------------

--- Parsing `TTImp` stuff ---

unDPair : TTImp -> (List (Count, PiInfo TTImp, Maybe Name, TTImp), TTImp)
unDPair (IApp _ (IApp _ (IVar _ `{Builtin.DPair.DPair}) typ) (ILam _ cnt piInfo mbname _ lamTy)) =
    mapFst ((cnt, piInfo, mbname, typ)::) $ unDPair lamTy
unDPair expr = ([], expr)

unDPairUnAlt : TTImp -> Maybe (List (Count, PiInfo TTImp, Maybe Name, TTImp), TTImp)
unDPairUnAlt (IAlternative _ _ alts) = case filter (not . force . null . Builtin.fst) $ unDPair <$> alts of
  [x] => Just x
  _   => Nothing
unDPairUnAlt x = Just $ unDPair x

--- Utility functions working on `TTImp`-related values ---

isSameTypeAs : Name -> Name -> Elab Bool
isSameTypeAs checked expected = let eq = (==) `on` name in [| getInfo' checked `eq` getInfo' expected |]

----------------------------------------
--- Internal functions and instances ---
----------------------------------------

--- Info of code position ---

public export
record GenSignatureFC where
  constructor MkGenSignatureFC
  sigFC        : FC
  genFC        : FC
  targetTypeFC : FC

--- Analysis functions ---

checkTypeIsGen : (hinted : List TTImp) -> TTImp -> Elab (GenSignatureFC, ParsedUserGenSignature, ParsedUserGenExternals)
checkTypeIsGen hinted sig = do

  -- check the given expression is a type
  _ <- check {expected=Type} sig

  -- treat the given type expression as a (possibly 0-ary) function type
  (sigArgs, sigResult) <- unPiNamed sig

  -----------------------------------------
  -- First checks in the given arguments --
  -----------------------------------------

  -- check that there are at least some parameters in the signature
  let (firstArg::sigArgs) = sigArgs
    | [] => failAt (getFC sig) "No arguments in the generator function signature, at least a fuel argument must be present"

  -- check that the first argument an explicit unnamed one
  let MkArg MW ExplicitArg (MN _ _) (IVar firstArgFC firstArgTypeName) = firstArg
    | _ => failAt (getFC firstArg.type) "The first argument must be explicit, unnamed, present at runtime and of type `Fuel`"

  -- check the type of the fuel argument
  unless !(firstArgTypeName `isSameTypeAs` `{Data.Fuel.Fuel}) $
    failAt firstArgFC "The first argument must be of type `Fuel`"

  ---------------------------------------------------------------
  -- First looks at the resulting type of a generator function --
  ---------------------------------------------------------------

  -- check the resulting type is `Gen`
  let IApp _ (IVar genFC topmostResultName) targetType = sigResult
    | _ => failAt (getFC sigResult) "The result type of the generator function must be of type \"`Gen` of desired result\""

  unless !(topmostResultName `isSameTypeAs` `{Test.DepTyCheck.Gen.Gen}) $
    failAt (getFC sigResult) "The result type of the generator function must be of type \"`Gen` of desired result\""

  -- treat the generated type as a dependent pair
  let Just (paramsToBeGenerated, targetType) = unDPairUnAlt targetType
    | Nothing => failAt (getFC targetType) "Unable to interpret type under `Gen` as a dependent pair"

  -- remember the right target type
  let targetTypeFC = getFC targetType

  -- treat the target type as a function application
  let (targetType, targetTypeArgs) = unApp targetType

  ------------------------------------------
  -- Working with the target type familly --
  ------------------------------------------

  -- check it's applied to some name
  let IVar _ targetType = targetType
    | _ => failAt targetTypeFC "Target type is not a simple name"

  -- check that desired `Gen` is not a generator of `Gen`s
  when !(targetType `isSameTypeAs` `{Test.DepTyCheck.Gen.Gen}) $
    failAt targetTypeFC "Target type of a derived `Gen` cannot be a `Gen`"

  -- check we can analyze the target type itself
  targetType <- getInfo' targetType

  -- check that there are at least non-zero constructors
  let (_::_) = targetType.cons
    | [] => fail "No constructors found for the type `\{show targetType.name}`"

  --------------------------------------------------
  -- Target type family's arguments' first checks --
  --------------------------------------------------

  -- check all the arguments of the target type are variable names, not complex expressions
  targetTypeArgs <- for targetTypeArgs $ \case
    IVar _ (UN argName) => pure $ UserName argName
    nonVarArg => failAt (getFC nonVarArg) "Target type's argument must be a variable name"

  -- check that all arguments names are unique
  let [] = findDiffPairWhich (==) targetTypeArgs
    | _ :: _ => failAt targetTypeFC "All arguments of the target type must be different"

  -- check the given type info corresponds to the given type application, and convert a `List` to an appropriate `Vect`
  let Yes targetTypeArgsLengthCorrect = targetType.args.length `decEq` targetTypeArgs.length
    | No _ => fail "INTERNAL ERROR: unequal argument lists lengths: \{show targetTypeArgs.length} and \{show targetType.args.length}"

  ------------------------------------------------------------
  -- Parse `Reflect` structures to what's needed to further --
  ------------------------------------------------------------

  -- check that all parameters of `DPair` are as expected
  paramsToBeGenerated <- for paramsToBeGenerated $ \case
    (MW, ExplicitArg, Just (UN nm), t) => pure (UserName nm, t)
    (_,  _,           _           , _) => failAt (getFC sigResult) "Argument of dependent pair under the resulting `Gen` must be named"
    _                                  => failAt (getFC sigResult) "INTERNAL ERROR: bad lambda in dpair under `Gen`"

  -- check that all arguments are omega, not erased or linear; and that all arguments are properly named
  sigArgs <- for {b = Either _ TTImp} sigArgs $ \case
    MkArg MW ImplicitArg (UN name) type => pure $ Left (Parsed.ImplicitArg, UserName name, type)
    MkArg MW ExplicitArg (UN name) type => pure $ Left (Parsed.ExplicitArg, UserName name, type)
    MkArg MW AutoImplicit (MN _ _) type => pure $ Right type

    MkArg MW ImplicitArg     _ ty => failAt (getFC ty) "Implicit argument must be named"
    MkArg MW ExplicitArg     _ ty => failAt (getFC ty) "Explicit argument must be named"
    MkArg MW AutoImplicit    _ ty => failAt (getFC ty) "Auto-implicit argument must be unnamed"

    MkArg M0 _               _ ty => failAt (getFC ty) "Erased arguments are not supported in generator function signatures"
    MkArg M1 _               _ ty => failAt (getFC ty) "Linear arguments are not supported in generator function signatures"
    MkArg MW (DefImplicit _) _ ty => failAt (getFC ty) "Default implicit arguments are not supported in generator function signatures"
  let givenParams := lefts sigArgs
  let autoImplArgs := rights sigArgs
  --let (givenParams, autoImplArgs) := (lefts sigArgs, rights sigArgs) -- `partitionEithers sigArgs` does not reduce here somewhy :-(

  ----------------------------------------------------------------------
  -- Check that generated and given parameter lists are actually sets --
  ----------------------------------------------------------------------

  -- check that all parameters in `parametersToBeGenerated` have different names
  let [] = findDiffPairWhich ((==) `on` fst) paramsToBeGenerated
    | (_, (_, ty)) :: _ => failAt (getFC ty) "Name of the argument is not unique in the dependent pair under the resulting `Gen`"

  -- check that all given parameters have different names
  let [] = findDiffPairWhich ((==) `on` (Builtin.fst . snd)) givenParams
    | (_, (_, _, ty)) :: _ => failAt (getFC ty) "Name of the generator function's argument is not unique"

  -----------------------------------------------------------------------
  -- Link generated and given parameters lists to the `targetTypeArgs` --
  -----------------------------------------------------------------------

  -- check that all parameters to be generated are actually used inside the target type
  paramsToBeGenerated <- for paramsToBeGenerated $ \(name, ty) => case findIndex (== name) targetTypeArgs of
    Just found => pure $ rewrite targetTypeArgsLengthCorrect in found
    Nothing => failAt (getFC ty) "Generated parameter is not used in the target type"

  -- check that all target type's parameters classied as "given" are present in the given params list
  givenParams <- for givenParams $ \(explicitness, name, ty) => case findIndex (== name) targetTypeArgs of
    Just found => pure (explicitness, rewrite targetTypeArgsLengthCorrect in found)
    Nothing => failAt (getFC ty) "Given parameter is not used in the target type"

  ------------------------------------------------
  -- Auto-implicit and hinted generators checks --
  ------------------------------------------------

  -- check all auto-implicit arguments pass the checks for the `Gen` and do not contain their own auto-implicits
  autoImplArgs <- subCheck "Auto-implicit" autoImplArgs

  -- check all hinted arguments pass the checks for the `Gen`
  hinted <- subCheck "Hinted" hinted

  -- check that all auto-imlicit arguments are unique
  let [] = findDiffPairWhich ((==) `on` snd) autoImplArgs
    | (_, (fc, _)) :: _ => failAt fc.targetTypeFC "Repetition of an auto-implicit external generator"

  -- check that all hinted arguments are unique
  let [] = findDiffPairWhich ((==) `on` snd) hinted
    | (_, (fc, _)) :: _ => failAt fc.targetTypeFC "Repetition of a hinted external generator"

  -- check that hinted and auto-implicit arguments do not intersect
  let [] = findPairWhich ((==) `on` snd) autoImplArgs hinted
    | (_, (fc, _)) :: _ => failAt fc.targetTypeFC "Repetition between auto-implicit and hinted external generators"

  -- forget FCs of subparsed externals
  let autoImplArgs = snd <$> autoImplArgs
  let hinted       = snd <$> hinted

  ------------
  -- Result --
  ------------

  let genSig = MkParsedUserGenSignature {targetType, paramsToBeGenerated, givenParams}
  let fc = MkGenSignatureFC {sigFC=getFC sig, genFC, targetTypeFC}
  let externals = MkParsedUserGenExternals autoImplArgs hinted
  pure (fc, genSig, externals)

  -----------------------
  -- Utility functions --
  -----------------------

  where
    subCheck : (desc : String) -> List TTImp -> Elab $ List (GenSignatureFC, ParsedUserGenSignature)
    subCheck desc = traverse $ checkTypeIsGen [] >=> \case
      (fc, s, MkParsedUserGenExternals {autoImplExternals=[], hintedExternals=[]}) => pure (fc, s)
      (fc, _, MkParsedUserGenExternals {autoImplExternals=_::_, _}) => failAt fc.genFC "\{desc} argument should not contain its own auto-implicit arguments"
      (fc, _, MkParsedUserGenExternals {hintedExternals=_::_, _})   => failAt fc.genFC "INTERNAL ERROR: parsed hinted externals are unexpectedly non empty"

    data UserDefinedName = UserName String

    Eq UserDefinedName where
      (==) = (==) `on` \(UserName n) => n

------------------------------
--- Functions for the user ---
------------------------------

||| The entry-point function of automatic derivation of `Gen`'s.
|||
||| Consider, you have a `data X (a : A) (b : B n) (c : C) where ...` and
||| you want a derived `Gen` for `X`.
||| Say, you want to have `a` and `c` parameters of `X` to be set by the caller and the `b` parameter to be generated.
||| For this your generator function should have a signature like `(a : A) -> (c : C) -> (n ** b : B n ** X a b c)`.
||| So, you need to define a function with this signature, say, named as `genX` and
||| to write `genX = deriveGen` as an implementation to make the body to be derived.
|||
||| Say, you want `n` to be set by the caller and, as the same time, to be an implicit argument.
||| In this case, the signature of the main function to be derived,
||| becomes `{n : _} -> (a : A) -> (c : C) -> (b : B n ** X a b c)`.
||| But still, you can use this function `deriveGen` to derive a function with such signature.
|||
||| Say, you want your generator to be parameterized with some external `Gen`'s.
||| Some of these `Gen`'s are known declared `%hint x : Gen Y`, some of them should go as an `auto` parameters.
||| Consider types `data Y where ...`, `data Z1 where ...` and `data Z2 (b : B n) where ...`.
||| For this, `auto`-parameters can be listed with `=>`-syntax in the signature.
||| External generators declared with `%hint` need to be listed separately in the implicit argument of `deriveGen`.
|||
||| For example, if you want to use `%hint` for `Gen Y` and `Gen`'s for `Z1` and `Z2` to be `auto` parameters,
||| you can define your function in the following way:
|||
|||   ```idris
|||   genX : Gen Z1 => ({n : _} -> {b : B n} -> Gen (Z2 b)) => {n : _} -> (a : A) -> (c : C) -> (b : B n ** X a b c)
|||   genX = deriveGen { externalHintedGens = [ `(Gen Y) ] }
|||   ```
|||
||| `%hint _ : Gen Y` from the current scope will be used as soon as a value of type `Y` will be needed for generation.
|||
||| Consider another example, where all generators for `Y`, `Z1` and `Z2` are means to be defined with `%hint`.
||| In this case, you are meant to declare it in the following way:
|||
|||   ```idris
|||   genX : {n : _} -> (a : A) -> (c : C) -> (b : B n ** X a b c)
|||   genX = deriveGen { externalHintedGens = [ `(Gen Z1), `({n : _} -> {b : B n} -> Gen (Z2 b)), `(Gen Y) ] }
|||   ```
|||
||| Consider also, that you may be asked for having the `Fuel` argument as the first argument in the signature
||| due to (maybe, temporary) unability of `Gen`'s to manage infinite processes of values generation.
|||
export %macro
deriveGen : {a : Type} -> {default [] externalHintedGens : List TTImp} -> Elab a
deriveGen = do
  Just signature <- goal
     | Nothing => fail "The goal signature is not found. Generators derivation must be used only for fully defined signatures"
  (signature, externals) <- snd <$> checkTypeIsGen externalHintedGens signature
  (lambda, locals) <- runCanonic externals $ wrapExternals externals =<< externalLambda signature
  check $ local locals lambda
