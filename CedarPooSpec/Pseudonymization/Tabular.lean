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
  surrogateInfoType : Option String := none

structure AesSivTableInput where
  value : String
  context : String
  deriving DecidableEq

inductive TableSelectionError where
  | invalidRecipe
  | missingOrDuplicateValue
  | missingOrDuplicateContext
  | contextOutsideScope
  deriving DecidableEq, Repr

/-- Select the exact value and context used by a structured AES-SIV
    operation. The scope is an admitted context partition, not a substitute
    for the column value passed to the cryptographic provider. -/
def AesSivTableRecipe.select (recipe : AesSivTableRecipe)
    (row : TableRow) : Except TableSelectionError AesSivTableInput := do
  if recipe.profile.mode != .aesSiv || recipe.dataset.isEmpty ||
      recipe.valueField.isEmpty || recipe.contextField.isEmpty ||
      recipe.profile.scope.isEmpty ||
      recipe.valueField == recipe.contextField then
    throw .invalidRecipe
  let value ← match row.readUnique recipe.valueField with
    | some value => pure value
    | none => throw .missingOrDuplicateValue
  if value.isEmpty then throw .missingOrDuplicateValue
  let context ← match row.readUnique recipe.contextField with
    | some context => pure context
    | none => throw .missingOrDuplicateContext
  if context != recipe.profile.scope then throw .contextOutsideScope
  return ⟨value, context⟩

end CedarPooSpec.Pseudonymization
