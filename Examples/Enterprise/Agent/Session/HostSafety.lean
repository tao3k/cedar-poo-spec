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

/-- The executable step uses the same Cedar check and Host effect as replay. -/
def step (before : Session) (operation : Operation) : Session :=
  if authorized "Integrated" before operation.attempt then
    advance before operation.attempt else before

def run (before : Session) : List Operation → Session
  | [] => before
  | operation :: rest => run (step before operation) rest

def stepReceipt (before : Session) (operation : Operation) :
    Receipt before (step before operation) operation :=
  { observedRequest := request before operation.attempt
    allowed := authorized "Integrated" before operation.attempt
    requestExact := rfl
    decisionExact := rfl
    effectExact := rfl }

/-- The executable runner constructs a valid receipt chain for every finite
    operation list; the length is unrestricted. -/
theorem reachableRunFrom (operations : List Operation) :
    ∀ before, Reachable before → Reachable (run before operations) := by
  induction operations with
  | nil => intro before h; exact h
  | cons operation rest ih =>
      intro before h
      exact ih (step before operation) (Reachable.next h (stepReceipt before operation))

theorem reachableRun (operations : List Operation) :
    Reachable (run {} operations) :=
  reachableRunFrom operations {} Reachable.initial

/-- Fields supplied by the Host before their consistency is checked. Receipt
    authenticity and serialization are obligations of the Host transport. -/
structure ClaimedReceipt where
  before : Session
  after : Session
  operation : Operation
  observedRequest : Cedar.Spec.Request
  allowed : Bool

/-- Check a claimed receipt against the current committed ledger and Cedar. -/
def verifyReceipt (before : Session) (claim : ClaimedReceipt) :
    Option (Receipt before claim.after claim.operation) := do
  if _hBefore : claim.before = before then pure () else none
  if hRequest : claim.observedRequest = request before claim.operation.attempt then
    if hDecision : claim.allowed = authorized "Integrated" before claim.operation.attempt then
      if hEffect : claim.after = step before claim.operation then
        some { observedRequest := claim.observedRequest
               allowed := claim.allowed
               requestExact := hRequest
               decisionExact := hDecision
               effectExact := by simpa [step, hDecision] using hEffect }
      else none
    else none
  else none

/-- Only a fully checked serialized chain yields a reachable final ledger. -/
def verifyChain (before : Session) (reachable : Reachable before) :
    List ClaimedReceipt → Option {after : Session // Reachable after}
  | [] => some ⟨before, reachable⟩
  | claim :: rest => do
      let receipt ← verifyReceipt before claim
      verifyChain claim.after (Reachable.next reachable receipt) rest

def verifyClaims (claims : List ClaimedReceipt) :
    Option {after : Session // Reachable after} :=
  verifyChain {} Reachable.initial claims

/-- The trusted runner can emit the same raw fields that the verifier checks. -/
def claimFor (before : Session) (operation : Operation) : ClaimedReceipt :=
  { before
    after := step before operation
    operation
    observedRequest := request before operation.attempt
    allowed := authorized "Integrated" before operation.attempt }

def claimsFor (before : Session) : List Operation → List ClaimedReceipt
  | [] => []
  | operation :: rest =>
      claimFor before operation :: claimsFor (step before operation) rest

private theorem verifyClaimFor (before : Session) (operation : Operation) :
    verifyReceipt before (claimFor before operation) =
      some (stepReceipt before operation) := by
  simp [verifyReceipt, claimFor, stepReceipt]

/-- Checked raw receipts from the runner recover the same final ledger. -/
theorem verifyChainClaimsFor (operations : List Operation) :
    ∀ (before : Session) (reachable : Reachable before),
      (verifyChain before reachable (claimsFor before operations)).map Subtype.val =
        some (run before operations) := by
  induction operations with
  | nil =>
      intro before reachable
      rfl
  | cons operation rest ih =>
      intro before reachable
      simp only [claimsFor, verifyChain, verifyClaimFor]
      exact ih (step before operation) (Reachable.next reachable (stepReceipt before operation))

theorem verifyClaimsFor (operations : List Operation) :
    (verifyClaims (claimsFor {} operations)).map Subtype.val =
      some (run {} operations) :=
  verifyChainClaimsFor operations {} Reachable.initial

private theorem replayFoldlState (root : String) (attempts : List Attempt) :
    ∀ (state : Session) (rows : List (Cedar.Spec.Request × Bool)),
      (attempts.foldl (fun (state, rows) attempt =>
        let req := request state attempt
        let allowed := authorized root state attempt
        let next := if allowed then advance state attempt else state
        (next, rows ++ [(req, allowed)])) (state, rows)).1 =
      attempts.foldl (fun state attempt =>
        if authorized root state attempt then advance state attempt else state) state := by
  induction attempts with
  | nil => intro state rows; rfl
  | cons attempt rest ih =>
      intro state rows
      simpa only [List.foldl] using
        ih (if authorized root state attempt then advance state attempt else state)
          (rows ++ [(request state attempt, authorized root state attempt)])

private theorem runFoldl (operations : List Operation) :
    ∀ state,
      run state operations =
        (operations.map Operation.attempt).foldl (fun state attempt =>
          if authorized "Integrated" state attempt then
            advance state attempt else state) state := by
  induction operations with
  | nil => intro state; rfl
  | cons operation rest ih =>
      intro state
      simpa only [run, step, List.map, List.foldl] using
        ih (step state operation)

/-- The proof runner and the earlier replay implementation have the same
    final committed ledger for every operation list. -/
theorem runEqReplayFinal (operations : List Operation) (initial : Session) :
    run initial operations =
      (replay "Integrated" initial (operations.map Operation.attempt)).2 := by
  rw [runFoldl]
  unfold replay
  exact (replayFoldlState "Integrated" (operations.map Operation.attempt) initial []).symm

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

/-- A verifier result carries a proof that the submitted receipt chain stayed
    in the four-state enclosure. -/
theorem verifiedClaimsEnclosed (claims : List ClaimedReceipt)
    {result : {after : Session // Reachable after}}
    (_accepted : verifyClaims claims = some result) : Enclosed result.val :=
  reachableEnclosed result.property

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

theorem externalSendSafeAfterRun (operations : List Operation)
    (allowed : authorized "Integrated" (run {} operations)
      CedarPooSpec.BoundedSessionExample.sendExternal = true) :
    (run {} operations).sensitiveSeen = false ∧
      (run {} operations).usedExports = 0 :=
  safeExternalFromEnclosed _ (reachableEnclosed (reachableRun operations)) allowed

theorem externalSendSafeAfterVerifiedClaims (claims : List ClaimedReceipt)
    {result : {after : Session // Reachable after}}
    (accepted : verifyClaims claims = some result)
    (allowed : authorized "Integrated" result.val
      CedarPooSpec.BoundedSessionExample.sendExternal = true) :
    result.val.sensitiveSeen = false ∧ result.val.usedExports = 0 :=
  safeExternalFromEnclosed _ (verifiedClaimsEnclosed claims accepted) allowed

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

/-- Changes to any checked field of a valid public-read receipt are rejected. -/
theorem alteredClaimsRejected :
    (verifyReceipt {} { (claimFor {} .readPublic) with
      before := { sensitiveSeen := true } }).isNone = true ∧
    (verifyReceipt {} { (claimFor {} .readPublic) with
      observedRequest := request {} CedarPooSpec.BoundedSessionExample.sendExternal }).isNone = true ∧
    (verifyReceipt {} { (claimFor {} .readPublic) with
      allowed := false }).isNone = true ∧
    (verifyReceipt {} { (claimFor {} .readPublic) with
      after := { sensitiveSeen := true } }).isNone = true := by
  native_decide

end CedarPooSpec.BoundedSessionHostSafety
