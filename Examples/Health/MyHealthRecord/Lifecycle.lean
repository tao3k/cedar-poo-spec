import Examples.Health.MyHealthRecord.ConsumerPlatform

/-!
Finite Host projection for a consumer-platform workflow. These transitions do
not call the Australian FHIR Gateway, persist records, or prove deletion.
-/

namespace CedarPooSpec.MyHealthRecordExample.Lifecycle

open Cedar.Spec CedarPooSpec.MyHealthRecordExample

inductive Step where
  | fetch | summarize | release | purge
  deriving BEq

structure Effect where
  step : Step
  patient : String := "patient-a"
  sourceDigest : String := ""
  summaryDigest : String := ""
  payloadDigest : String
  deriving BEq

structure State where
  epoch : Nat := 0
  policyRevision : Nat := 0
  consentRevision : Nat := 0
  accessActive : Bool := true
  oauthActive : Bool := true
  sessionActive : Bool := true
  withinInactivityWindow : Bool := true
  modelApproved : Bool := true
  humanReviewed : Bool := true
  auditAvailable : Bool := true
  fetchedDigest : Option String := none
  summaryDigest : Option String := none
  intermediaryCached : Bool := false
  removed : Bool := false
  audit : List String := []

structure Ticket where
  root : String
  epoch : Nat
  policyRevision : Nat
  consentRevision : Nat
  effect : Effect
  deriving BEq

def Step.action : Step → EntityUID
  | .fetch => MyHealthRecordExample.fetch
  | .summarize => MyHealthRecordExample.summarize
  | .release => MyHealthRecordExample.release
  | .purge => MyHealthRecordExample.purge

def Step.actor : Step → EntityUID
  | .summarize => assistant
  | _ => app

def Step.resource : Step → EntityUID
  | .fetch | .summarize => summaryA
  | .release | .purge => outputA

def projectedFacts (state : State) (effect : Effect) : Facts :=
  { subjectPatient := effect.patient,
    patientMatches := effect.patient == "patient-a",
    oauthActive := state.oauthActive,
    sessionActive := state.sessionActive,
    withinInactivityWindow := state.withinInactivityWindow,
    appAccessActive := state.accessActive,
    fetchedDigestMatches := state.fetchedDigest == some effect.sourceDigest,
    summaryDigestMatches := state.summaryDigest == some effect.summaryDigest,
    modelApproved := state.modelApproved,
    humanReviewed := state.humanReviewed,
    auditReady := state.auditAvailable }

def allowed (root : String) (state : State) (effect : Effect) : Bool :=
  if !state.auditAvailable then false else
    let req := request effect.step.actor effect.step.action effect.step.resource
      (projectedFacts state effect)
    let result := observed root req
    result.1 == .allow && result.2

def prepare (root : String) (state : State) (effect : Effect) : Option Ticket :=
  if effect.payloadDigest.isEmpty || !allowed root state effect then none
  else some ⟨root, state.epoch, state.policyRevision,
    state.consentRevision, effect⟩

/-- A pure admission model; the Host must atomically write its real audit. -/
def redeem (state : State) (ticket : Ticket) (effect : Effect) : Option State :=
  if ticket.epoch != state.epoch ||
      ticket.policyRevision != state.policyRevision ||
      ticket.consentRevision != state.consentRevision ||
      ticket.effect != effect || !allowed ticket.root state effect then none
  else
    let next := { state with
      epoch := state.epoch + 1,
      audit := state.audit ++ [effect.payloadDigest] }
    let next := match effect.step with
      | .fetch => { next with
          fetchedDigest := some effect.payloadDigest,
          intermediaryCached := true, removed := false }
      | .summarize => { next with summaryDigest := some effect.payloadDigest }
      | .release => next
      | .purge => { next with
          fetchedDigest := none, summaryDigest := none,
          intermediaryCached := false, removed := true }
    some next

def step (root : String) (state : State) (effect : Effect) : Option State := do
  let ticket ← prepare root state effect
  redeem state ticket effect

def revoke (state : State) : State :=
  { state with
    accessActive := false
    consentRevision := state.consentRevision + 1
    epoch := state.epoch + 1 }

def fetched : Effect :=
  { step := .fetch, payloadDigest := "fhir-summary-a-digest" }
def summarized : Effect :=
  { step := .summarize, sourceDigest := "fhir-summary-a-digest",
    payloadDigest := "ai-summary-a-digest" }
def released : Effect :=
  { step := .release, sourceDigest := "fhir-summary-a-digest",
    summaryDigest := "ai-summary-a-digest", payloadDigest := "release-a-digest" }
def purged : Effect :=
  { step := .purge, payloadDigest := "purge-a-digest" }

def lifecycle : Option State := do
  let afterFetch ← step "ConsumerPlatform" {} fetched
  let afterSummary ← step "ConsumerPlatform" afterFetch summarized
  let afterRelease ← step "ConsumerPlatform" afterSummary released
  step "ConsumerPlatform" (revoke afterRelease) purged

theorem revocationStillAllowsPurge :
    (lifecycle.map fun state =>
      (state.removed, state.intermediaryCached, state.fetchedDigest,
        state.summaryDigest, state.audit.length)) =
      some (true, false, none, none, 4) := by native_decide

def beforeRevocation : Option State := do
  let afterFetch ← step "ConsumerPlatform" {} fetched
  step "ConsumerPlatform" afterFetch summarized

theorem staleReleaseTicketRejected :
    (beforeRevocation.bind fun state => do
      let ticket ← prepare "ConsumerPlatform" state released
      redeem (revoke state) ticket released) = none := by native_decide

theorem revokedDataOperationsDenied :
    (beforeRevocation.map fun state =>
      let revoked := revoke state
      (prepare "ConsumerPlatform" revoked fetched).isNone &&
      (prepare "ConsumerPlatform" revoked summarized).isNone &&
      (prepare "ConsumerPlatform" revoked released).isNone) =
      some true := by native_decide

theorem replayedTicketRejected :
    (prepare "ConsumerPlatform" {} fetched).bind (fun ticket =>
      (redeem {} ticket fetched).bind fun state =>
        redeem state ticket fetched) = none := by native_decide

theorem staleSourceCannotSummarize :
    (step "ConsumerPlatform" {} fetched).bind
      (fun state => step "ConsumerPlatform" state
        { summarized with sourceDigest := "other-record" }) = none := by native_decide

theorem auditFailureBlocksRelease :
    (beforeRevocation.bind fun state =>
      prepare "ConsumerPlatform" { state with auditAvailable := false }
        released) = none := by native_decide

end CedarPooSpec.MyHealthRecordExample.Lifecycle
