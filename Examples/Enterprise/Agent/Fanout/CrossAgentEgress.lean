import Examples.Enterprise.Agent.Fanout.SharedBudget
import CedarPooSpec.SchemaJson

/-!
One worker reads a sensitive document and another proposes external egress.
The policy owners reuse the bounded-session history and intent controls and
the fanout budget controls. The admission host owns the shared lineage ledger.
-/

namespace CedarPooSpec.CrossAgentEgressExample

open Cedar.Spec Cedar.Data Cedar.Validation CedarPooSpec.PolicyModules

def workerA : EntityUID := CedarPooSpec.SharedBudgetExample.workerA
def workerB : EntityUID := CedarPooSpec.SharedBudgetExample.workerB
def secretDoc : EntityUID := CedarPooSpec.BoundedSessionExample.secretDoc
def publicDoc : EntityUID := CedarPooSpec.BoundedSessionExample.publicDoc
def externalEndpoint : EntityUID := CedarPooSpec.SharedBudgetExample.endpoint
def readAction : EntityUID := CedarPooSpec.BoundedSessionExample.readAction
def sendAction : EntityUID := CedarPooSpec.SharedBudgetExample.sendAction

def contextType : RecordType := Map.make [
  ("localUsed", .required .int), ("localMax", .required .int),
  ("sharedUsed", .required .int), ("sharedMax", .required .int),
  ("sensitiveSeen", .required (.bool .anyBool)),
  ("intent", .required .string), ("delegatedIntent", .required .string)]
def readEntry : ActionSchemaEntry :=
  ⟨Set.make [CedarPooSpec.BoundedSessionExample.agentType],
    Set.make [CedarPooSpec.BoundedSessionExample.documentType],
    Set.empty, contextType⟩
def sendEntry : ActionSchemaEntry :=
  ⟨Set.make [CedarPooSpec.BoundedSessionExample.agentType],
    Set.make [CedarPooSpec.BoundedSessionExample.endpointType],
    Set.empty, contextType⟩
def schema : Schema :=
  ⟨Map.make [
      (CedarPooSpec.BoundedSessionExample.agentType,
        CedarPooSpec.BoundedSessionExample.emptyEntry),
      (CedarPooSpec.BoundedSessionExample.documentType,
        CedarPooSpec.BoundedSessionExample.documentEntry),
      (CedarPooSpec.BoundedSessionExample.endpointType,
        CedarPooSpec.BoundedSessionExample.endpointEntry)],
    Map.make [(readAction, readEntry), (sendAction, sendEntry)]⟩
def entities : Entities := Map.make [
  (workerA, CedarPooSpec.BoundedSessionExample.emptyData),
  (workerB, CedarPooSpec.BoundedSessionExample.emptyData),
  (secretDoc, CedarPooSpec.BoundedSessionExample.documentData true),
  (publicDoc, CedarPooSpec.BoundedSessionExample.documentData false),
  (externalEndpoint, CedarPooSpec.BoundedSessionExample.endpointData true),
  (readAction, actionSchemaEntryToEntityData readEntry),
  (sendAction, actionSchemaEntryToEntityData sendEntry)]

/-- Reuse the session policy bodies while widening the principal to the
    workers bound by the admission host. -/
def workerRead : Policy :=
  { CedarPooSpec.BoundedSessionExample.readPermit with
    principalScope := .principalScope .any }
def lineageHistory : Policy :=
  { CedarPooSpec.BoundedSessionExample.historyVeto with
    principalScope := .principalScope .any }
def delegatedIntent : Policy :=
  { CedarPooSpec.BoundedSessionExample.intentVeto with
    principalScope := .principalScope .any }

/-- Actual LeanPOO construction: inherited fanout budgets, then independently
    editable read, history, and intent owners, followed by a C4 mix. -/
def modelResult : Except LeanPoo.C4.Error Model := do
  let budget := CedarPooSpec.SharedBudgetExample.model
  let read ← budget.extend "Read" "Integrated" [.extend workerRead]
  let history ← read.extend "History" "Read" [.extend lineageHistory]
  let intent ← history.extend "Intent" "Read" [.extend delegatedIntent]
  let governed ← intent.mix "CrossAgentGoverned" ["History", "Intent"]
  let incident ← governed.extend "CrossAgentIncident" "CrossAgentGoverned"
    [.extend CedarPooSpec.SharedBudgetExample.incidentVeto]
  incident.extend "CrossAgentRecovered" "CrossAgentIncident"
    [.remove CedarPooSpec.SharedBudgetExample.incidentVeto.id]

def model : Model := modelResult.toOption.get (by native_decide)

inductive LedgerView where
  | workerLocal
  | delegationShared
  deriving BEq, Repr

structure State where
  budget : CedarPooSpec.SharedBudgetExample.State := {}
  aSeen : Bool := false
  bSeen : Bool := false
  sharedSeen : Bool := false
  delegated : String := "report"
  epoch : Nat := 0
  deriving BEq, Repr

structure Attempt where
  worker : EntityUID
  action : EntityUID
  resource : EntityUID
  intent : String := "report"
  deriving BEq

def readSecretA : Attempt := ⟨workerA, readAction, secretDoc, "report"⟩
def readPublicA : Attempt := ⟨workerA, readAction, publicDoc, "report"⟩
def sendA (intent := "report") : Attempt :=
  ⟨workerA, sendAction, externalEndpoint, intent⟩
def sendB (intent := "report") : Attempt :=
  ⟨workerB, sendAction, externalEndpoint, intent⟩

def seenBy (view : LedgerView) (state : State) (worker : EntityUID) : Bool :=
  match view with
  | .workerLocal => if worker == workerA then state.aSeen else state.bSeen
  | .delegationShared => state.sharedSeen

def request (view : LedgerView) (state : State) (attempt : Attempt) : Request :=
  ⟨attempt.worker, attempt.action, attempt.resource, Map.make [
    ("localUsed", .prim (.int
      (CedarPooSpec.SharedBudgetExample.localUsed state.budget attempt.worker))),
    ("localMax", .prim (.int state.budget.localMax)),
    ("sharedUsed", .prim (.int state.budget.sharedUsed)),
    ("sharedMax", .prim (.int state.budget.sharedMax)),
    ("sensitiveSeen", .prim (.bool (seenBy view state attempt.worker))),
    ("intent", .prim (.string attempt.intent)),
    ("delegatedIntent", .prim (.string state.delegated))]⟩

def authorized (root : String) (view : LedgerView) (state : State)
    (attempt : Attempt) : Bool :=
  if attempt.worker != workerA && attempt.worker != workerB then false else
    match model.compile root with
    | .error _ => false
    | .ok policies =>
        let response := isAuthorized (request view state attempt) entities policies
        response.decision == .allow && response.erroringPolicies.isEmpty

def advance (state : State) (attempt : Attempt) : State :=
  if attempt.action == readAction && attempt.resource == secretDoc then
    { state with
      aSeen := state.aSeen || attempt.worker == workerA
      bSeen := state.bSeen || attempt.worker == workerB
      sharedSeen := true }
  else if attempt.action == sendAction && attempt.resource == externalEndpoint then
    { state with budget :=
        CedarPooSpec.SharedBudgetExample.advance state.budget attempt.worker }
  else state

/-- The transition is serialized over the delegation ledger. -/
def admit (root : String) (view : LedgerView) (state : State)
    (attempt : Attempt) : Bool × State :=
  let allowed := authorized root view state attempt
  let next := advance state attempt
  (allowed, if allowed then { next with epoch := state.epoch + 1 } else state)

/-- The host binds a checked request to the exact proposed tool effect. The
    digest and ticket must come from authenticated host state in deployment. -/
structure BoundEffect where
  attempt : Attempt
  payloadDigest : String
  deriving BEq

structure AdmissionTicket where
  root : String
  view : LedgerView
  epoch : Nat
  effect : BoundEffect
  deriving BEq

def prepare (root : String) (view : LedgerView) (state : State)
    (effect : BoundEffect) : Option AdmissionTicket :=
  if authorized root view state effect.attempt then
    some ⟨root, view, state.epoch, effect⟩
  else none

/-- A compare-and-swap admission contract. A real host must persist the
    ledger and execute this check and reservation atomically. -/
def commit (root : String) (view : LedgerView) (state : State)
    (ticket : AdmissionTicket) (effect : BoundEffect) : Option State :=
  if ticket.root == root && ticket.view == view &&
      ticket.epoch == state.epoch && ticket.effect == effect &&
      authorized root view state effect.attempt then
    let next := advance state effect.attempt
    some { next with epoch := state.epoch + 1 }
  else none

def replay (root : String) (view : LedgerView) (initial : State)
    (attempts : List Attempt) : List (Request × Bool) × State :=
  let (state, rows) := attempts.foldl (fun (state, rows) attempt =>
    let req := request view state attempt
    let (allowed, next) := admit root view state attempt
    (next, rows ++ [(req, allowed)])) (initial, [])
  (rows, state)

def decisions (root : String) (view : LedgerView) (attempts : List Attempt) :
    List Bool := (replay root view {} attempts).1.map Prod.snd

def cases : List (String × String × LedgerView × List Attempt × List Bool) := [
  ("read-only-owner-leaks-across-workers", "Read", .delegationShared,
    [readSecretA, sendB], [true, true]),
  ("history-owner-blocks-shared-egress", "History", .delegationShared,
    [readSecretA, sendB], [true, false]),
  ("intent-owner-leaves-history-gap", "Intent", .delegationShared,
    [readSecretA, sendB], [true, true]),
  ("history-owner-leaves-intent-gap", "History", .delegationShared,
    [sendB "off-task"], [true]),
  ("governed-local-ledger-still-leaks", "CrossAgentGoverned", .workerLocal,
    [readSecretA, sendB], [true, true]),
  ("governed-shared-ledger-blocks", "CrossAgentGoverned", .delegationShared,
    [readSecretA, sendB], [true, false]),
  ("governed-public-report", "CrossAgentGoverned", .delegationShared,
    [readPublicA, sendB], [true, true]),
  ("governed-off-task-send", "CrossAgentGoverned", .delegationShared,
    [sendB "off-task"], [false]),
  ("governed-shared-budget", "CrossAgentGoverned", .delegationShared,
    [sendA, sendB], [true, false]),
  ("incident-freezes-otherwise-valid-egress", "CrossAgentIncident", .delegationShared,
    [readPublicA, sendB], [true, false]),
  ("recovered-keeps-lineage-history", "CrossAgentRecovered", .delegationShared,
    [readSecretA, sendB], [true, false])]

theorem casesExact :
    cases.all (fun (_, root, view, attempts, expected) =>
      decisions root view attempts == expected) = true := by native_decide

theorem sharedLineageClosesCrossWorkerGap :
    decisions "CrossAgentGoverned" .workerLocal [readSecretA, sendB] =
      [true, true] ∧
    decisions "CrossAgentGoverned" .delegationShared [readSecretA, sendB] =
      [true, false] := by native_decide

theorem rejectedEgressDoesNotSpendBudget :
    (replay "CrossAgentGoverned" .delegationShared {}
      [readSecretA, sendB]).2.budget.sharedUsed = 0 := by native_decide

theorem survivingOwners :
    (model.compileWithProvenance "CrossAgentGoverned").toOption.map
      (·.map (fun p => p.introducedBy)) =
      some ["Base", "Shared", "Local", "Read", "Intent", "History"] := by
  native_decide

def publicSendA : BoundEffect := ⟨sendA, "payload-a"⟩
def publicSendB : BoundEffect := ⟨sendB, "payload-b"⟩
def secretReadA : BoundEffect := ⟨readSecretA, "document-version-1"⟩

private theorem firstTicketExists :
    (prepare "CrossAgentGoverned" .delegationShared {} publicSendA).isSome = true := by
  native_decide
private theorem secondTicketExists :
    (prepare "CrossAgentGoverned" .delegationShared {} publicSendB).isSome = true := by
  native_decide
private theorem readTicketExists :
    (prepare "CrossAgentGoverned" .delegationShared {} secretReadA).isSome = true := by
  native_decide

/-- Two tickets prepared on one budget snapshot cannot both commit. -/
theorem staleFanoutTicketRejected :
    let root := "CrossAgentGoverned"
    let first := (prepare root .delegationShared {} publicSendA).get firstTicketExists
    let second := (prepare root .delegationShared {} publicSendB).get secondTicketExists
    ((commit root .delegationShared {} first publicSendA).bind fun state =>
      commit root .delegationShared state second publicSendB) = none := by
  native_decide

/-- A checked call cannot be exchanged for different tool payload bytes. -/
theorem substitutedPayloadRejected :
    let root := "CrossAgentGoverned"
    let ticket := (prepare root .delegationShared {} publicSendA).get firstTicketExists
    commit root .delegationShared {} ticket ⟨sendA, "substituted-payload"⟩ = none := by
  native_decide

/-- A sensitive read invalidates an earlier send ticket. Rechecking against
    shared history then refuses a new send ticket. -/
theorem sensitiveReadInvalidatesPreparedSend :
    let root := "CrossAgentGoverned"
    let sendTicket := (prepare root .delegationShared {} publicSendB).get secondTicketExists
    let readTicket := (prepare root .delegationShared {} secretReadA).get readTicketExists
    (((commit root .delegationShared {} readTicket secretReadA).map fun state =>
      (commit root .delegationShared state sendTicket publicSendB,
       prepare root .delegationShared state publicSendB)) ==
      some (none, none)) = true := by
  native_decide

theorem allRootsValidate :
    ["Read", "History", "Intent", "CrossAgentGoverned",
      "CrossAgentIncident", "CrossAgentRecovered"].all (fun root =>
        (CedarPooSpec.PolicyJson.publish model root schema).isOk) = true := by
  native_decide

end CedarPooSpec.CrossAgentEgressExample
