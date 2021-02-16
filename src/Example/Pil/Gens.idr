module Example.Pil.Gens

import Data.DPair
import Data.List.Lazier
import Data.Fuel

import Decidable.Equality

import public Example.Pil.Lang

import public Test.DepTyCheck.Gen

%default total

------------------
--- Generation ---
------------------

--- General methodology of writing generators ---

-- Determine the desired (root) data component and its parameters.
-- Say, it is a `X (a : A) (b : B)`.
-- Determine which parameters finally would be user-defined and which are generated.
-- Say, `x` is user-defined and `y` is generated.
-- Then the type of the main generator would be `(a : A) -> Gen (b : B ** X a b)`.

-- Determine also the types which has external generators and add their `Gen Y =>` to the final signature.

-- For each constructor of the desired type (`X` in the example) do the following.
-- Determine its arguments
-- TBD

-- For recursion, mutuality or separate signature predeclaration is required.
-- The latter is, probably, the most universal way since it would always work
-- because there is no need of reduction of `Gen`-producing functions.

--- Universal patterns (particular cases) ---

asp : {0 indexed : index -> Type} ->
      {0 fin : {0 idx : index} -> indexed idx -> Type} ->
      Gen (n ** indexed n) ->
      ({0 idx : index} -> {p : indexed idx} -> Gen $ fin p) ->
      Gen (n : index ** p : indexed n ** fin p)
asp rl lr = do (n ** i) <- rl
               pure (n ** i ** !lr)

--- Common ---

lookupGen : (vars : Variables) -> Gen (n : Name ** Lookup n vars)
lookupGen vars = uniform $ fromList $ mapLk vars where
  mapLk : (vars : Variables) -> List (n ** Lookup n vars)
  mapLk []            = []
  mapLk ((n, ty)::xs) = (n ** Here ty) :: map (\(n ** lk) => (n ** There lk)) (mapLk xs)

--- Expressions ---

export
varExprGen : {a : Type'} -> {vars : Variables} -> {regs : Registers rc} -> Gen $ Expression vars regs a
varExprGen = do Element (n ** _) prf <- lookupGen vars `suchThat_invertedEq` a $ \(_ ** lk) => reveal lk
                pure rewrite prf in V n

||| Generator of non-recursive expressions (thus those that can be used with zero recursion bound).
nonRec_exprGen : {a : Type'} -> {vars : Variables} -> {regs : Registers rc} -> Gen (idrTypeOf a) -> Gen $ Expression vars regs a
nonRec_exprGen g = [| C g |] <|> varExprGen
                   -- TODO to add the register access expression

export
exprGen : (fuel : Fuel) ->
          {a : Type'} ->
          ({b : Type'} -> Gen $ idrTypeOf b) ->
          {vars : Variables} ->
          {regs : Registers rc} ->
          ((subGen : {x : Type'} -> Gen $ Expression vars regs x) -> {b : Type'} -> Gen $ Expression vars regs b) ->
          Gen (Expression vars regs a)
exprGen Dry      g _   = nonRec_exprGen g
exprGen (More f) g rec = nonRec_exprGen g <|> rec (exprGen f g rec)

--- Statements ---

public export
SpecGen : (Nat -> Type) -> Type
SpecGen res =
  (fuel : Fuel) ->
  {0 rc : Nat} ->
  Gen Type' =>
  Gen Name =>
  ({a : Type'} -> {vars : Variables} -> {regs : Registers rc} -> Gen (Expression vars regs a)) =>
  res rc

namespace Equal_registers

  public export
  EqRegisters_Gen : Type
  EqRegisters_Gen = SpecGen \rc => (regs : Registers rc) -> Gen (regs' ** regs' =%= regs)

  export
  eq_registers_gen : EqRegisters_Gen

namespace Statements_given_preV_preR_postV_postR

  public export
  Statement''_Gen : Type
  Statement''_Gen = SpecGen \rc => (preV : Variables) -> (preR : Registers rc) -> (postV : Variables) -> (postR : Registers rc) ->
                                   Gen (Statement preV preR postV postR)

  nop_gen   : Statement''_Gen
  dot_gen   : Statement''_Gen
  ass_gen   : Statement''_Gen
  for_gen   : Statement''_Gen
  if_gen    : Statement''_Gen
  seq_gen   : Statement''_Gen
  block_gen : Statement''_Gen
  print_gen : Statement''_Gen

  export
  statement_gen : Statement''_Gen
  statement_gen Dry preV preR postV postR = nop_gen   Dry preV preR postV postR
                                          <|> dot_gen   Dry preV preR postV postR
                                          <|> ass_gen   Dry preV preR postV postR
                                          <|> print_gen Dry preV preR postV postR
  statement_gen (More f) preV preR postV postR = nop_gen   f preV preR postV postR
                                               <|> dot_gen   f preV preR postV postR
                                               <|> ass_gen   f preV preR postV postR
                                               <|> for_gen   f preV preR postV postR
                                               <|> if_gen    f preV preR postV postR
                                               <|> seq_gen   f preV preR postV postR
                                               <|> block_gen f preV preR postV postR
                                               <|> print_gen f preV preR postV postR

namespace Statements_given_preV_preR_postR

  public export
  Statement'_Gen : Type
  Statement'_Gen = SpecGen \rc => (preV : Variables) -> (preR : Registers rc) -> (postR : Registers rc) ->
                                 Gen (postV ** Statement preV preR postV postR)

  nop_gen   : Statement'_Gen
  dot_gen   : Statement'_Gen
  ass_gen   : Statement'_Gen
  for_gen   : Statement'_Gen
  if_gen    : Statement'_Gen
  seq_gen   : Statement'_Gen
  block_gen : Statement'_Gen
  print_gen : Statement'_Gen

  export
  statement_gen : Statement'_Gen
  statement_gen Dry preV preR postR = nop_gen   Dry preV preR postR
                                   <|> dot_gen   Dry preV preR postR
                                   <|> ass_gen   Dry preV preR postR
                                   <|> print_gen Dry preV preR postR
  statement_gen (More f) preV preR postR = nop_gen   f preV preR postR
                                        <|> dot_gen   f preV preR postR
                                        <|> ass_gen   f preV preR postR
                                        <|> for_gen   f preV preR postR
                                        <|> if_gen    f preV preR postR
                                        <|> seq_gen   f preV preR postR
                                        <|> block_gen f preV preR postR
                                        <|> print_gen f preV preR postR

namespace Statements_given_preV_preR

  public export
  StmtGen : Type
  StmtGen = SpecGen \rc => (preV : Variables) -> (preR : Registers rc) -> Gen (postV ** postR ** Statement preV preR postV postR)

  nop_gen   : StmtGen
  dot_gen   : StmtGen
  ass_gen   : StmtGen
  for_gen   : StmtGen
  if_gen    : StmtGen
  seq_gen   : StmtGen
  block_gen : StmtGen
  print_gen : StmtGen

  export
  statement_gen : StmtGen
  statement_gen Dry preV preR = nop_gen   Dry preV preR
                            <|> dot_gen   Dry preV preR
                            <|> ass_gen   Dry preV preR
                            <|> print_gen Dry preV preR
  statement_gen (More f) preV preR = nop_gen   f preV preR
                                 <|> dot_gen   f preV preR
                                 <|> ass_gen   f preV preR
                                 <|> for_gen   f preV preR
                                 <|> if_gen    f preV preR
                                 <|> seq_gen   f preV preR
                                 <|> block_gen f preV preR
                                 <|> print_gen f preV preR

namespace Statements_given_preV_preR

  nop_gen _ preV preR = pure (_ ** _ ** nop)

  dot_gen @{type'} @{name} @{_} _ preV preR = pure (_ ** _ ** !type'. !name)

  ass_gen @{_} @{_} @{expr} _ preV preR = do
    (n ** lk) <- lookupGen preV
    pure (_ ** _ ** n #= !expr)

  for_gen @{_} @{_} @{expr} f preV preR = do
    (insideV ** insideR ** init) <- statement_gen f preV preR
    (updR ** _) <- eq_registers_gen f insideR
    upd         <- statement_gen f insideV insideR insideV updR
    (bodyR ** _) <- eq_registers_gen f insideR
    (_ ** body)  <- statement_gen f insideV insideR bodyR
    pure (_ ** _ ** for init !expr upd body)

  if_gen @{_} @{_} @{expr} f preV preR = do
    (_ ** _ ** th) <- statement_gen f preV preR
    (_ ** _ ** el) <- statement_gen f preV preR
    pure (_ ** _ ** if__ !expr th el)

  seq_gen f preV preR = do
    (midV ** midR ** l) <- statement_gen f preV preR
    (_    ** _    ** r) <- statement_gen f midV midR
    pure (_ ** _ ** l *> r)

  block_gen f preV preR = do
    (_ ** _ ** s) <- statement_gen f preV preR
    pure (_ ** _ ** block s)

  print_gen @{_} @{_} @{expr} _ preV preR = pure (_ ** _ ** print !(expr {a=String'}))
