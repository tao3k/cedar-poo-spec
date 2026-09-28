import CedarPooSpec.Pseudonymization.TokenCatalog

/-!
An explicit structured-data selection for deterministic AES-SIV tokens.
The context is read from a named column, rather than trusted as a free
request Boolean. A Host must still authenticate the row, resolve the actual
key, perform encryption, and bind the output to the selected input.
-/

namespace CedarPooSpec.Pseudonymization

structure TableRow where
  fields : List (String × String)

/-- Duplicate columns are ambiguous and cannot select an encryption input. -/
def TableRow.readUnique (row : TableRow) (name : String) : Option String :=
  match row.fields.filter (fun field => field.1 == name) with
  | [(_, value)] => some value
  | _ => none

structure AesSivTableRecipe where
  dataset : String
  valueField : String
  contextField : String
  profile : TokenProfile
  admittedContext : Option String := none
  surrogateInfoType : Option String := none

structure AesSivTableInput where
  value : String
  context : String
  deriving DecidableEq

inductive TableSelectionError where
  | invalidRecipe
  | missingOrDuplicateValue
  | missingOrDuplicateContext
  | contextNotAdmitted
  deriving DecidableEq, Repr

/-- Select the exact value and context used by a structured AES-SIV
    operation. A scenario may restrict the context, but a general table can
    contain different context values under one declared recipe. -/
def AesSivTableRecipe.select (recipe : AesSivTableRecipe)
    (row : TableRow) : Except TableSelectionError AesSivTableInput := do
  if recipe.profile.mode != .aesSiv || recipe.dataset.isEmpty ||
      recipe.valueField.isEmpty || recipe.contextField.isEmpty ||
      recipe.valueField == recipe.contextField then
    throw .invalidRecipe
  let value ← match row.readUnique recipe.valueField with
    | some value => pure value
    | none => throw .missingOrDuplicateValue
  if value.isEmpty then throw .missingOrDuplicateValue
  let context ← match row.readUnique recipe.contextField with
    | some context => pure context
    | none => throw .missingOrDuplicateContext
  if context.isEmpty || recipe.admittedContext.any (· != context) then
    throw .contextNotAdmitted
  return ⟨value, context⟩

/-- A matching catalog recipe is insufficient for a deterministic join when
    the actual per-record context values differ. -/
def AesSivTableRecipe.compatibleInputs (left right : AesSivTableRecipe)
    (leftInput rightInput : AesSivTableInput) : Bool :=
  left.profile.sameRecipe right.profile && leftInput.context == rightInput.context

end CedarPooSpec.Pseudonymization
