import Examples.Health.MyHealthRecord.ConsumerPlatform
import CedarPooSpec.Admission.BoundOperation

/-!
Finite Host projection for a consumer-platform workflow. These transitions do
not call the Australian FHIR Gateway, persist records, or prove deletion.
-/

namespace CedarPooSpec.MyHealthRecordExample.Lifecycle

open Cedar.Spec CedarPooSpec.MyHealthRecordExample CedarPooSpec.Admission

inductive Step where
  | fetch | summarize | release | purge
  deriving BEq, DecidableEq

structure Effect where
  step : Step
  patient : String := "patient-a"
  sourceDigest : String := ""
  summaryDigest : String := ""
  payloadDigest : String
  deriving BEq, DecidableEq

inductive Root where
  | consumerPlatform | agentIncident | recovered
  deriving BEq, DecidableEq

def Root.name : Root → String
  | .consumerPlatform => "ConsumerPlatform"
  | .agentIncident => "AgentIncident"
  | .recovered => "Recovered"

structure State where
  epoch : Nat := 0
  deployedRoot : Root := .consumerPlatform
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
  deriving DecidableEq

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

def operationRequest (effect : Effect) (state : State) : Request :=
  request effect.step.actor effect.step.action effect.step.resource
    (projectedFacts state effect)

structure Ticket where
  root : Root
  operation : BoundOperation Effect State operationRequest

def authorized (root : Root) (operation : BoundOperation Effect State operationRequest)
    (state : State) (effect : Effect) : Bool :=
  if root != state.deployedRoot || !state.auditAvailable then false else
    match operation.authorize effect state model root.name entities with
    | .ok receipt => receipt.allowed
    | .error _ => false

def allowed (state : State) (effect : Effect) : Bool :=
  authorized state.deployedRoot ⟨effect, state⟩ state effect

def prepare (state : State) (effect : Effect) : Option Ticket :=
  let operation : BoundOperation Effect State operationRequest := ⟨effect, state⟩
  if effect.payloadDigest.isEmpty ||
      !authorized state.deployedRoot operation state effect then none
  else some ⟨state.deployedRoot, operation⟩

/-- A pure admission model; the Host must atomically write its real audit. -/
def redeem (state : State) (ticket : Ticket) (effect : Effect) : Option State :=
  if !authorized ticket.root ticket.operation state effect then none
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

def step (state : State) (effect : Effect) : Option State := do
  let ticket ← prepare state effect
  redeem state ticket effect

def revoke (state : State) : State :=
  { state with
    accessActive := false
    consentRevision := state.consentRevision + 1
    epoch := state.epoch + 1 }

def enterAgentIncident (state : State) : State :=
  { state with
    deployedRoot := .agentIncident
    policyRevision := state.policyRevision + 1
    epoch := state.epoch + 1 }

def recoverAgent (state : State) : State :=
  { state with
    deployedRoot := .recovered
    policyRevision := state.policyRevision + 1
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
  let afterFetch ← step {} fetched
  let afterSummary ← step afterFetch summarized
  let afterRelease ← step afterSummary released
  step (revoke afterRelease) purged

theorem revocationStillAllowsPurge :
    (lifecycle.map fun state =>
      (state.removed, state.intermediaryCached, state.fetchedDigest,
        state.summaryDigest, state.audit.length)) =
      some (true, false, none, none, 4) := by native_decide

def beforeRevocation : Option State := do
  let afterFetch ← step {} fetched
  step afterFetch summarized

theorem staleReleaseTicketRejected :
    (beforeRevocation.bind fun state => do
      let ticket ← prepare state released
      redeem (revoke state) ticket released) = none := by native_decide

theorem changedPolicyRevisionRejectsTicket :
    (prepare {} fetched).bind (fun ticket =>
      redeem { ({} : State) with policyRevision := 1 } ticket fetched) = none := by
  native_decide

theorem incidentSwitchRejectsOldTicket :
    (beforeRevocation.bind fun state => do
      let ticket ← prepare state released
      redeem (enterAgentIncident state) ticket released) = none := by
  native_decide

theorem incidentBlocksAgentButKeepsConsumerRead :
    (beforeRevocation.map fun state =>
      let incident := enterAgentIncident state
      (prepare incident summarized).isNone &&
      (prepare incident fetched).isSome) = some true := by native_decide

theorem recoveryRestoresAgentAdmission :
    (beforeRevocation.map fun state =>
      (prepare (recoverAgent (enterAgentIncident state)) summarized).isSome) =
      some true := by native_decide

theorem substitutedEffectRejectedBeforeCedar :
    (match (⟨fetched, {}⟩ : BoundOperation Effect State operationRequest).authorize
        { fetched with payloadDigest := "substituted-record" } {}
        model "ConsumerPlatform" entities with
    | .error .effectMismatch => true
    | _ => false) = true := by native_decide

theorem changedStateRejectedBeforeCedar :
    (match (⟨fetched, {}⟩ : BoundOperation Effect State operationRequest).authorize
        fetched { ({} : State) with policyRevision := 1 }
        model "ConsumerPlatform" entities with
    | .error .stateMismatch => true
    | _ => false) = true := by native_decide

theorem revokedDataOperationsDenied :
    (beforeRevocation.map fun state =>
      let revoked := revoke state
      (prepare revoked fetched).isNone &&
      (prepare revoked summarized).isNone &&
      (prepare revoked released).isNone) =
      some true := by native_decide

theorem replayedTicketRejected :
    (prepare {} fetched).bind (fun ticket =>
      (redeem {} ticket fetched).bind fun state =>
        redeem state ticket fetched) = none := by native_decide

theorem staleSourceCannotSummarize :
    (step {} fetched).bind
      (fun state => step state
        { summarized with sourceDigest := "other-record" }) = none := by native_decide

theorem auditFailureBlocksRelease :
    (beforeRevocation.bind fun state =>
      prepare { state with auditAvailable := false }
        released) = none := by native_decide

end CedarPooSpec.MyHealthRecordExample.Lifecycle
