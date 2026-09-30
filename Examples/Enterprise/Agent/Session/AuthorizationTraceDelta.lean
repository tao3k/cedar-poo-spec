import CedarPooSpec.AuthorizationDeltaTrace
import CedarPooSpec.PolicyJson
import Examples.Enterprise.Agent.Session.BoundedSession

/-!
One proposed agent action sequence is replayed from the same initial session
under two C4 roots. A denied action leaves its side's Host ledger unchanged,
so later requests may have different context even for the same proposal.
-/

namespace CedarPooSpec.BoundedSessionTraceDelta

open CedarPooSpec.AuthorizationDelta
open CedarPooSpec.BoundedSessionExample

private def observe (state : Session) (attempt : Attempt) : Cedar.Spec.Env :=
  ⟨request state attempt, entities⟩

private def compare (attempts : List Attempt) :
    Except Error (TraceImpact Session) :=
  compareTrace schema model "Base" "Integrated" ({} : Session)
    attempts observe advance

private def receiptCases (name : String) (impact : TraceImpact Session) :
    Except String (List Lean.Json) := do
  let indexed := impact.steps.zipIdx
  let before ← indexed.mapM fun (step, index) =>
    CedarPooSpec.PolicyJson.authorizationCase s!"{name}-before-{index}" "Base"
      model "Base" step.beforeEnv.request step.beforeEnv.entities
  let after ← indexed.mapM fun (step, index) =>
    CedarPooSpec.PolicyJson.authorizationCase s!"{name}-after-{index}" "Integrated"
      model "Integrated" step.afterEnv.request step.afterEnv.entities
  return before ++ after

def run : IO Lean.Json := do
  let .ok sensitive := compare [readSecret, sendExternal]
    | throw (IO.userError "sensitive-read trace comparison failed")
  if sensitive.steps.map TraceStep.beforeAllowed != [true, true] ||
      sensitive.steps.map TraceStep.afterAllowed != [true, false] ||
      sensitive.steps.map TraceStep.sameInput != [true, true] ||
      sensitive.steps.map TraceStep.directDifference != [false, true] ||
      sensitive.steps.any TraceStep.divergentInputDifference ||
      !sensitive.lost || sensitive.gained ||
      !sensitive.beforeFinal.sensitiveSeen ||
      !sensitive.afterFinal.sensitiveSeen ||
      sensitive.beforeFinal.usedExports != 1 ||
      sensitive.afterFinal.usedExports != 0 ||
      !(sensitive.changes.map (·.id)).contains historyVeto.id then
    throw (IO.userError "sensitive-read trace lost its C4/history delta")
  let .ok budget := compare [readPublic, sendExternal, sendExternal, sendExternal]
    | throw (IO.userError "budget trace comparison failed")
  if budget.steps.map TraceStep.beforeAllowed != [true, true, true, true] ||
      budget.steps.map TraceStep.afterAllowed != [true, true, false, false] ||
      budget.steps.map TraceStep.sameInput != [true, true, true, false] ||
      budget.steps.map TraceStep.directDifference != [false, false, true, false] ||
      budget.steps.map TraceStep.divergentInputDifference != [false, false, false, true] ||
      budget.beforeFinal.usedExports != 3 ||
      budget.afterFinal.usedExports != 1 ||
      !(budget.changes.map (·.id)).contains budgetVeto.id then
    throw (IO.userError "budget trace did not preserve separate Host states")
  let some last := budget.steps.getLast?
    | throw (IO.userError "budget trace has no final proposal")
  if last.beforeEnv.request.context == last.afterEnv.request.context then
    throw (IO.userError "later requests did not reflect divergent ledgers")
  let changedProposal := compareTrace schema model "Base" "Integrated"
      ({} : Session) [readPublic, sendExternal, sendExternal, sendExternal]
      (fun state attempt =>
        observe state (if state.usedExports > 1 then sendInternal else attempt))
      advance
  match changedProposal with
  | .error .operationChanged => pure ()
  | _ => throw (IO.userError "state-dependent operation substitution was admitted")
  let alphabet := [readSecret, sendExternal, sendExternal "off-task"]
  let .ok bounded := compareBoundedTraces schema model "Base" "Integrated"
      ({} : Session) alphabet 3 39 observe advance
    | throw (IO.userError "bounded proposal comparison failed")
  let boundedGains := bounded.filter fun (_, impact) => impact.gained
  let boundedDirectLosses := bounded.filter fun (_, impact) =>
    impact.steps.any fun step => step.directDifference && step.lost
  let boundedDivergentLosses := bounded.filter fun (_, impact) =>
    impact.steps.any fun step => step.divergentInputDifference && step.lost
  let boundedByLength := [1, 2, 3].map fun length =>
    (bounded.filter fun (proposals, _) => proposals.length == length).length
  if bounded.length != 39 || boundedByLength != [3, 9, 27] ||
      !boundedGains.isEmpty ||
      boundedDirectLosses.isEmpty || boundedDivergentLosses.isEmpty then
    throw (IO.userError "bounded scope lost a direct or divergent loss")
  match compareBoundedTraces schema model "Base" "Integrated"
      ({} : Session) alphabet 3 38 observe advance with
  | .error .invalidBoundedScope => pure ()
  | _ => throw (IO.userError "undersized bounded-scope cap was admitted")
  let .ok sensitiveCases := receiptCases "sensitive" sensitive
    | throw (IO.userError "cannot export sensitive Cedar replay")
  let .ok budgetCases := receiptCases "budget" budget
    | throw (IO.userError "cannot export budget Cedar replay")
  let .ok boundedCaseLists := bounded.zipIdx.mapM fun ((_, impact), index) =>
      receiptCases s!"bounded-{index}" impact
    | throw (IO.userError "cannot export bounded Cedar replay")
  let boundedCases := boundedCaseLists.flatten
  return Lean.Json.mkObj [
    ("sensitive_before", Lean.toJson (sensitive.steps.map TraceStep.beforeAllowed)),
    ("sensitive_after", Lean.toJson (sensitive.steps.map TraceStep.afterAllowed)),
    ("budget_before", Lean.toJson (budget.steps.map TraceStep.beforeAllowed)),
    ("budget_after", Lean.toJson (budget.steps.map TraceStep.afterAllowed)),
    ("sensitive_same_input", Lean.toJson (sensitive.steps.map TraceStep.sameInput)),
    ("sensitive_direct_difference", Lean.toJson
      (sensitive.steps.map TraceStep.directDifference)),
    ("budget_same_input", Lean.toJson (budget.steps.map TraceStep.sameInput)),
    ("budget_direct_difference", Lean.toJson
      (budget.steps.map TraceStep.directDifference)),
    ("budget_divergent_input_difference", Lean.toJson
      (budget.steps.map TraceStep.divergentInputDifference)),
    ("sensitive_owner", Lean.toJson
      ((sensitive.changes.find? (·.id == historyVeto.id)).bind
        (fun change => change.afterOwner.map (·.lastEditedBy)))),
    ("different_later_context", Lean.toJson true),
    ("operation_substitution_rejected", Lean.toJson true),
    ("bounded_alphabet_size", Lean.toJson alphabet.length),
    ("bounded_horizon", Lean.toJson (3 : Nat)),
    ("bounded_sequence_count", Lean.toJson bounded.length),
    ("bounded_by_length", Lean.toJson boundedByLength),
    ("bounded_gains", Lean.toJson boundedGains.length),
    ("bounded_direct_loss_sequences", Lean.toJson boundedDirectLosses.length),
    ("bounded_divergent_loss_sequences", Lean.toJson boundedDivergentLosses.length),
    ("bounded_cap_rejected", Lean.toJson true),
    ("manifest", Lean.Json.mkObj [
      ("cases", Lean.toJson (sensitiveCases ++ budgetCases ++ boundedCases))])]

end CedarPooSpec.BoundedSessionTraceDelta

def main : IO Unit := do
  IO.println (← CedarPooSpec.BoundedSessionTraceDelta.run).compress
