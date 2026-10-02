import CedarPooSpec.Pseudonymization.TableBatch

/-!
Pure shape contract for one Google Table de-identification response. The
provider does not return MRR row ordinals; callers associate returned rows
with selected rows by a generated marker carried in each response row. This check cannot authenticate
the provider or establish atomic execution of an external request.
-/

namespace CedarPooSpec.Pseudonymization

structure TableBatchWireRow where
  value : String
  context : String
  marker : String
  deriving DecidableEq, Inhabited

structure TableBatchWireResponse where
  rows : List TableBatchWireRow
  successCount : Nat
  errorCount : Nat
  deriving DecidableEq

/-- Admit no local output unless the whole ordered response has the selected
    row count, unchanged contexts, a changed nonempty value in every row, and
    an exact successful transformation count with no reported errors. The
    Rust provider bridge additionally checks AES-SIV token syntax. -/
private def rowsMatch : Nat → List AesSivTableBatchInput → List TableBatchWireRow → Bool
  | _, [], [] => true
  | index, input :: inputs, output :: outputs =>
    !output.value.isEmpty && output.value != input.input.value &&
    output.context == input.input.context &&
    output.marker == s!"r{index}" && rowsMatch (index + 1) inputs outputs
  | _, _, _ => false

def TableBatchWireResponse.admitted (response : TableBatchWireResponse)
    (selected : List AesSivTableBatchInput) : Bool :=
  !selected.isEmpty && selected.length ≤ 256 &&
  response.rows.length == selected.length &&
  response.successCount == selected.length && response.errorCount == 0 &&
  rowsMatch 0 selected response.rows

end CedarPooSpec.Pseudonymization
