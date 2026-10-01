import CedarPooSpec.Pseudonymization.TableBatch

/-!
Pure shape contract for one Google Table de-identification response. The
provider does not return MRR row ordinals; callers associate returned rows
with selected rows by their ordered positions. This check cannot authenticate
the provider or establish atomic execution of an external request.
-/

namespace CedarPooSpec.Pseudonymization

structure TableBatchWireRowV1 where
  value : String
  context : String
  deriving DecidableEq, Inhabited

structure TableBatchWireResponseV1 where
  rows : List TableBatchWireRowV1
  successCount : Nat
  errorCount : Nat
  deriving DecidableEq

/-- Admit no local output unless the whole ordered response has the selected
    row count, unchanged contexts, a changed nonempty value in every row, and
    an exact successful transformation count with no reported errors. The
    Rust provider bridge additionally checks AES-SIV token syntax. -/
def TableBatchWireResponseV1.admitted (response : TableBatchWireResponseV1)
    (selected : List AesSivTableBatchInput) : Bool :=
  !selected.isEmpty && selected.length ≤ 256 &&
  response.rows.length == selected.length &&
  response.successCount == selected.length && response.errorCount == 0 &&
  (selected.zip response.rows).all fun (input, output) =>
    !output.value.isEmpty && output.value != input.input.value &&
    output.context == input.input.context

end CedarPooSpec.Pseudonymization
