import CedarPooSpec.Pseudonymization.Tabular

/-!
A bounded, ordered selection of tabular AES-SIV inputs. This is a pure
selection contract: it does not authorize Cloud release, construct a Google
wire request, authenticate Arrow bytes, or call a provider.
-/

namespace CedarPooSpec.Pseudonymization

structure AesSivTableBatchRow where
  ordinal : Nat
  row : TableRow

structure AesSivTableBatchInput where
  ordinal : Nat
  input : AesSivTableInput
  deriving DecidableEq

inductive TableBatchError where
  | empty
  | invalidBudget
  | tooManyRows
  | ordinalOrder
  | selection (error : TableSelectionError)
  | tooManyBytes
  deriving DecidableEq, Repr

private def selectRows (recipe : AesSivTableRecipe) (maxBytes : Nat) :
    Option Nat → Nat → List AesSivTableBatchRow →
      Except TableBatchError (List AesSivTableBatchInput)
  | _, _, [] => pure []
  | previous, used, row :: rest => do
    if previous.any (· >= row.ordinal) then throw .ordinalOrder
    let input ← (recipe.select row.row).mapError TableBatchError.selection
    let next := used + input.value.utf8ByteSize + input.context.utf8ByteSize
    if next > maxBytes then throw .tooManyBytes
    let tail ← selectRows recipe maxBytes (some row.ordinal) next rest
    pure (⟨row.ordinal, input⟩ :: tail)

/-- Preserve row order, reject duplicates, and bound selected UTF-8 bytes.
    The hard ceilings are part of V1 rather than caller-controlled escape
    hatches. Per-row authorization and physical Arrow checks remain separate. -/
def AesSivTableRecipe.selectBatch (recipe : AesSivTableRecipe)
    (rows : List AesSivTableBatchRow) (maxRows maxBytes : Nat) :
    Except TableBatchError (List AesSivTableBatchInput) := do
  if rows.isEmpty then throw .empty
  if maxRows == 0 || maxRows > 256 || maxBytes == 0 || maxBytes > 1048576 then
    throw .invalidBudget
  if rows.length > maxRows then throw .tooManyRows
  selectRows recipe maxBytes none 0 rows

end CedarPooSpec.Pseudonymization
