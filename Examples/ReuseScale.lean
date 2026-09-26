import CedarPooSpec.Evaluation
import LeanPoo.Object.Debug

namespace CedarPooSpec.ReuseScaleExample

open LeanPoo.Proof
open LeanPoo.Proof.Debug

abbrev Key := Nat × Evaluation.Key
def Value (key : Key) : Type := Evaluation.Value key.2

def snapshot : Evaluation.Snapshot :=
  Evaluation.Snapshot.evaluate (.lit (.bool true)) default Cedar.Data.Map.empty

/-- Each indexed obligation has the actual Cedar evaluator dependency footprint. -/
def obligation (index : Nat) : Obligation Key Value where
  dependencies := [(index, .expr), (index, .request),
    (index, .entities), (index, .result)]
  holds := fun state =>
    state (index, .result) = Cedar.Spec.evaluate
      (state (index, .expr)) (state (index, .request))
      (state (index, .entities))
  stable := by
    intro before after equal holds
    have he := equal (index, .expr) (by simp)
    have hr := equal (index, .request) (by simp)
    have hs := equal (index, .entities) (by simp)
    have hv := equal (index, .result) (by simp)
    simpa [he, hr, hs, hv] using holds

def object (count : Nat) : ProofObject Key Value where
  state := fun key => snapshot.state key.2
  obligations := (List.range count).map obligation

def impactCounts (count changed : Nat) : Nat × Nat := Id.run do
  let patch : Patch Key Value :=
    Patch.set (changed, .expr) (.lit (.bool false))
  let impacts := explainPatch (object count) patch
  let repair := impacts.filter (·.needsRepair) |>.length
  return (impacts.length - repair, repair)

-- This is a dependency-scale receipt, not a 10,000-policy Cedar proof corpus.
#guard impactCounts 10000 7 == (9999, 1)
#guard impactCounts 10000 10001 == (10000, 0)
#eval impactCounts 10000 7

end CedarPooSpec.ReuseScaleExample
