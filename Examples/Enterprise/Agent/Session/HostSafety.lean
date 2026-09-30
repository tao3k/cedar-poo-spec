import Examples.Enterprise.Agent.Session.BoundedSession

/-!
An unbounded-length safety argument for the bounded session example. The Host
must authenticate the committed ledger and the request/effect receipts and
serialize admission with ledger updates. The proof covers the declared finite
proposal alphabet and starts from the stated initial ledger.
-/

namespace CedarPooSpec.BoundedSessionHostSafety

open CedarPooSpec.BoundedSessionExample

/-- The finite set of operations admitted by this Host contract. -/
inductive Operation where
  | readPublic | readSecret | sendExternal | sendInternal | sendOffTask
  deriving DecidableEq, Repr

def Operation.attempt : Operation → Attempt
  | .readPublic => CedarPooSpec.BoundedSessionExample.readPublic
  | .readSecret => CedarPooSpec.BoundedSessionExample.readSecret
  | .sendExternal => CedarPooSpec.BoundedSessionExample.sendExternal
  | .sendInternal => CedarPooSpec.BoundedSessionExample.sendInternal
  | .sendOffTask => CedarPooSpec.BoundedSessionExample.sendExternal "off-task"

/-- One authenticated receipt binds the submitted operation to the exact
    committed ledger, Cedar request, decision, and Host effect. The equalities
    are the contract checked after the Host verifies receipt authenticity. -/
structure Receipt (before after : Session) (operation : Operation) where
  observedRequest : Cedar.Spec.Request
  allowed : Bool
  requestExact : observedRequest = request before operation.attempt
  decisionExact : allowed = authorized "Integrated" before operation.attempt
  effectExact : after = if allowed then advance before operation.attempt else before

/-- A serialized chain: each receipt's before ledger is the previous receipt's
    committed after ledger. -/
inductive Reachable : Session → Prop where
  | initial : Reachable {}
  | next {before after : Session} {operation : Operation} :
      Reachable before → Receipt before after operation → Reachable after

private def state0 : Session := {}
private def state1 : Session := { sensitiveSeen := true }
private def state2 : Session := { usedExports := 1 }
private def state3 : Session := { sensitiveSeen := true, usedExports := 1 }

/-- The complete reachable state enclosure for this action alphabet. -/
def Enclosed (state : Session) : Prop :=
  state = state0 ∨ state = state1 ∨ state = state2 ∨ state = state3

private theorem enclosedInitial : Enclosed ({} : Session) := by
  exact Or.inl rfl

private theorem enclosedAfter (before : Session) (operation : Operation)
    (h : Enclosed before) :
    Enclosed (if authorized "Integrated" before operation.attempt then
      advance before operation.attempt else before) := by
  rcases h with h | h | h | h <;> subst before <;>
    cases operation <;> unfold Enclosed <;> native_decide

/-- Every finite sequence of authenticated Host receipts stays within four
    concrete ledger states, regardless of sequence length. -/
theorem reachableEnclosed {state : Session} (h : Reachable state) :
    Enclosed state := by
  induction h with
  | initial => exact enclosedInitial
  | next prior receipt ih =>
      rw [receipt.effectExact, receipt.decisionExact]
      exact enclosedAfter _ _ ih

/-- A granted external send cannot follow a sensitive read or spend an
    exhausted export budget. This checks the actual Cedar decision. -/
private theorem safeExternalFromEnclosed (state : Session)
    (h : Enclosed state)
    (allowed : authorized "Integrated" state
      CedarPooSpec.BoundedSessionExample.sendExternal = true) :
    state.sensitiveSeen = false ∧ state.usedExports = 0 := by
  rcases h with h | h | h | h <;> subst state
  · native_decide
  · have denied : authorized "Integrated" state1
        CedarPooSpec.BoundedSessionExample.sendExternal = false := by native_decide
    simp [denied] at allowed
  · have denied : authorized "Integrated" state2
        CedarPooSpec.BoundedSessionExample.sendExternal = false := by native_decide
    simp [denied] at allowed
  · have denied : authorized "Integrated" state3
        CedarPooSpec.BoundedSessionExample.sendExternal = false := by native_decide
    simp [denied] at allowed

theorem externalSendSafe {state : Session} (h : Reachable state)
    (receipt : Receipt state after .sendExternal)
    (allowed : receipt.allowed = true) :
    state.sensitiveSeen = false ∧ state.usedExports = 0 := by
  apply safeExternalFromEnclosed state (reachableEnclosed h)
  calc
    authorized "Integrated" state CedarPooSpec.BoundedSessionExample.sendExternal =
        receipt.allowed := by simpa [Operation.attempt] using receipt.decisionExact.symm
    _ = true := allowed

theorem deniedReceiptPreservesLedger {before after : Session}
    {operation : Operation} (receipt : Receipt before after operation)
    (denied : receipt.allowed = false) : after = before := by
  rw [receipt.effectExact, denied]
  rfl

theorem offTaskExternalDenied {before after : Session}
    (h : Reachable before) (receipt : Receipt before after .sendOffTask) :
    receipt.allowed = false := by
  have enclosed := reachableEnclosed h
  rcases enclosed with hs | hs | hs | hs <;> subst before <;>
    rw [receipt.decisionExact] <;> native_decide

end CedarPooSpec.BoundedSessionHostSafety
