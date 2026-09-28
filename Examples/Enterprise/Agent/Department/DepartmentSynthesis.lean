import Examples.Enterprise.Agent.Fanout.CrossAgentEgress
import CedarPooSpec.SchemaJson

/-!
One delegated agent reads Sales and Finance records through separate owners.
Neither read is individually marked sensitive, but their joint result may not
be sent externally. This proposed workflow extends the existing cross-agent
history and budget model rather than copying its policies.
-/

namespace CedarPooSpec.DepartmentSynthesisExample

open Cedar.Spec Cedar.Data Cedar.Validation CedarPooSpec.PolicyModules

def workerA : EntityUID := CedarPooSpec.CrossAgentEgressExample.workerA
def workerB : EntityUID := CedarPooSpec.CrossAgentEgressExample.workerB
def readAction : EntityUID := CedarPooSpec.CrossAgentEgressExample.readAction
def sendAction : EntityUID := CedarPooSpec.CrossAgentEgressExample.sendAction
def endpoint : EntityUID := CedarPooSpec.CrossAgentEgressExample.externalEndpoint
def documentType : EntityType := CedarPooSpec.BoundedSessionExample.documentType
def salesRecord : EntityUID := ⟨documentType, "sales-contract"⟩
def financeRecord : EntityUID := ⟨documentType, "finance-invoice"⟩

def contextType : RecordType := Map.make
  (CedarPooSpec.CrossAgentEgressExample.contextType.toList ++ [
    ("originDept", .required .string),
    ("salesSeen", .required (.bool .anyBool)),
    ("financeSeen", .required (.bool .anyBool)),
    ("delegationActive", .required (.bool .anyBool))])
def readEntry : ActionSchemaEntry :=
  ⟨Set.make [CedarPooSpec.BoundedSessionExample.agentType],
    Set.make [documentType], Set.empty, contextType⟩
def sendEntry : ActionSchemaEntry :=
  ⟨Set.make [CedarPooSpec.BoundedSessionExample.agentType],
    Set.make [CedarPooSpec.BoundedSessionExample.endpointType],
    Set.empty, contextType⟩
def documentEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.make [
    ("sensitive", .required (.bool .anyBool)),
    ("department", .required .string)], none⟩
def schema : Schema :=
  ⟨Map.make [
      (CedarPooSpec.BoundedSessionExample.agentType,
        CedarPooSpec.BoundedSessionExample.emptyEntry),
      (documentType, documentEntry),
      (CedarPooSpec.BoundedSessionExample.endpointType,
        CedarPooSpec.BoundedSessionExample.endpointEntry)],
    Map.make [(readAction, readEntry), (sendAction, sendEntry)]⟩

def documentData (department : String) : EntityData :=
  { CedarPooSpec.BoundedSessionExample.emptyData with attrs := Map.make [
      ("sensitive", .prim (.bool false)),
      ("department", .prim (.string department))] }
def entities : Entities := Map.make [
  (workerA, CedarPooSpec.BoundedSessionExample.emptyData),
  (workerB, CedarPooSpec.BoundedSessionExample.emptyData),
  (salesRecord, documentData "Sales"),
  (financeRecord, documentData "Finance"),
  (endpoint, CedarPooSpec.BoundedSessionExample.endpointData true),
  (readAction, actionSchemaEntryToEntityData readEntry),
  (sendAction, actionSchemaEntryToEntityData sendEntry)]

def fact (name : String) : Expr := .getAttr (.var .context) name
def neq (left right : Expr) : Expr :=
  .unaryApp .not (.binaryApp .eq left right)
def departmentVeto (id : String) (record : EntityUID)
    (department : String) : Policy :=
  let body : Expr := .and
    (neq (fact "originDept") (.lit (.string department)))
    (neq (fact "originDept") (.lit (.string "Joint")))
  { id, effect := .forbid,
    principalScope := .principalScope .any,
    actionScope := .actionScope (.eq readAction),
    resourceScope := .resourceScope (.eq record),
    condition := [{ kind := .when, body }] }
def salesVeto : Policy :=
  departmentVeto "sales-owner-boundary" salesRecord "Sales"
def financeVeto : Policy :=
  departmentVeto "finance-owner-boundary" financeRecord "Finance"
def aggregationVeto : Policy :=
  let body : Expr := .and (fact "salesSeen") (fact "financeSeen")
  { id := "cross-department-aggregate-egress", effect := .forbid,
    principalScope := .principalScope .any,
    actionScope := .actionScope (.eq sendAction),
    resourceScope := .resourceScope (.eq endpoint),
    condition := [{ kind := .when, body }] }
def expiredDelegationVeto : Policy :=
  let body : Expr := .unaryApp .not (fact "delegationActive")
  { id := "expired-delegation", effect := .forbid,
    principalScope := .principalScope .any,
    actionScope := .actionInAny [readAction, sendAction],
    resourceScope := .resourceScope .any,
    condition := [{ kind := .when, body }] }

/-- Four independent owners extend the inherited cross-agent controls. -/
def modelResult : Except LeanPoo.C4.Error Model := do
  let base := CedarPooSpec.CrossAgentEgressExample.model
  let sales ← base.extend "Sales" "CrossAgentGoverned" [.extend salesVeto]
  let finance ← sales.extend "Finance" "CrossAgentGoverned" [.extend financeVeto]
  let aggregate ← finance.extend "Aggregate" "CrossAgentGoverned"
    [.extend aggregationVeto]
  let temporal ← aggregate.extend "Temporal" "CrossAgentGoverned"
    [.extend expiredDelegationVeto]
  let governed ← temporal.mix "DepartmentGoverned"
    ["Sales", "Finance", "Aggregate", "Temporal"]
  let incident ← governed.mix "DepartmentIncident"
    ["DepartmentGoverned", "CrossAgentIncident"]
  incident.extend "DepartmentRecovered" "DepartmentIncident"
    [.remove CedarPooSpec.SharedBudgetExample.incidentVeto.id]

def model : Model := modelResult.toOption.get (by native_decide)

/-- The composed root retains each new owner and the inherited history owner. -/
theorem composedOwnersPresent :
    ["Sales", "Finance", "Aggregate", "Temporal", "History"].all (fun owner =>
      ((model.compileWithProvenance "DepartmentGoverned").toOption.get
        (by native_decide)).any (fun policy => policy.introducedBy == owner)) = true := by
  native_decide

/-- Adding the four owners changes exactly four policy identities. -/
theorem revisionAddsFourPolicies :
    ((model.compileRevision "CrossAgentGoverned" "DepartmentGoverned").toOption.get
      (by native_decide)).changedPolicyIds.length = 4 := by
  native_decide

structure State where
  lineage : CedarPooSpec.CrossAgentEgressExample.State := {}
  salesSeen : Bool := false
  financeSeen : Bool := false
  originDept : String := "Joint"
  delegationActive : Bool := true

abbrev Attempt := CedarPooSpec.CrossAgentEgressExample.Attempt
def readSales : Attempt := ⟨workerA, readAction, salesRecord, "report"⟩
def readFinance : Attempt := ⟨workerA, readAction, financeRecord, "report"⟩
def sendReport : Attempt := ⟨workerB, sendAction, endpoint, "report"⟩

def request (state : State) (attempt : Attempt) : Request :=
  let base := CedarPooSpec.CrossAgentEgressExample.request
    .delegationShared state.lineage attempt
  { base with context := Map.make (base.context.toList ++ [
      ("originDept", .prim (.string state.originDept)),
      ("salesSeen", .prim (.bool state.salesSeen)),
      ("financeSeen", .prim (.bool state.financeSeen)),
      ("delegationActive", .prim (.bool state.delegationActive))]) }

def authorized (root : String) (state : State) (attempt : Attempt) : Bool :=
  if attempt.worker != workerA && attempt.worker != workerB then false else
    match model.compile root with
    | .error _ => false
    | .ok policies =>
        let response := isAuthorized (request state attempt) entities policies
        response.decision == .allow && response.erroringPolicies.isEmpty

def advance (state : State) (attempt : Attempt) : State :=
  let next := CedarPooSpec.CrossAgentEgressExample.advance state.lineage attempt
  { state with
    lineage := { next with epoch := state.lineage.epoch + 1 },
    salesSeen := state.salesSeen ||
      (attempt.action == readAction && attempt.resource == salesRecord),
    financeSeen := state.financeSeen ||
      (attempt.action == readAction && attempt.resource == financeRecord) }

def replay (root : String) (initial : State) (attempts : List Attempt) :
    List (Request × Bool) × State :=
  let (state, rows) := attempts.foldl (fun (state, rows) attempt =>
    let req := request state attempt
    let allowed := authorized root state attempt
    let next := if allowed then advance state attempt else state
    (next, rows ++ [(req, allowed)])) (initial, [])
  (rows, state)

def decisions (root : String) (state : State) (attempts : List Attempt) :
    List Bool := (replay root state attempts).1.map Prod.snd

/-- Authority can change after an admitted read and before a proposed send. -/
def afterSalesThenRevoked : State :=
  { (replay "DepartmentGoverned" {} [readSales]).2 with
    delegationActive := false }

def cases : List (String × String × State × List Attempt × List Bool) := [
  ("baseline-sales-reads-finance", "CrossAgentGoverned",
    { originDept := "Sales" }, [readFinance], [true]),
  ("sales-owner-alone-misses-finance", "Sales",
    { originDept := "Sales" }, [readFinance], [true]),
  ("finance-owner-closes-sales-leak", "DepartmentGoverned",
    { originDept := "Sales" }, [readFinance], [false]),
  ("sales-owner-closes-finance-leak", "DepartmentGoverned",
    { originDept := "Finance" }, [readSales], [false]),
  ("single-department-report", "DepartmentGoverned",
    {}, [readSales, sendReport], [true, true]),
  ("baseline-joint-result-egress", "CrossAgentGoverned",
    {}, [readSales, readFinance, sendReport], [true, true, true]),
  ("governed-joint-result-denied", "DepartmentGoverned",
    {}, [readSales, readFinance, sendReport], [true, true, false]),
  ("revoked-read-denied", "DepartmentGoverned",
    { delegationActive := false }, [readSales], [false]),
  ("revoked-send-denied", "DepartmentGoverned",
    { delegationActive := false }, [sendReport], [false]),
  ("revoked-after-read-denied", "DepartmentGoverned",
    afterSalesThenRevoked, [sendReport], [false]),
  ("incident-denies-unaffected-sales", "DepartmentIncident",
    {}, [readSales, sendReport], [true, false]),
  ("recovered-retains-aggregation", "DepartmentRecovered",
    {}, [readSales, readFinance, sendReport], [true, true, false]),
  ("recovered-allows-single-department", "DepartmentRecovered",
    {}, [readSales, sendReport], [true, true])]

theorem casesExact :
    cases.all (fun (_, root, state, attempts, expected) =>
      decisions root state attempts == expected) = true := by native_decide

theorem aggregationNeedsBothDepartments :
    decisions "DepartmentGoverned" {} [readSales, sendReport] = [true, true] ∧
    decisions "DepartmentGoverned" {} [readSales, readFinance, sendReport] =
      [true, true, false] := by native_decide

theorem revocationAfterRead :
    decisions "DepartmentGoverned" {} [readSales] = [true] ∧
    decisions "DepartmentGoverned" afterSalesThenRevoked [sendReport] = [false] := by
  native_decide

theorem allRootsValidate :
    ["Sales", "Finance", "Aggregate", "Temporal", "DepartmentGoverned",
      "DepartmentIncident", "DepartmentRecovered"].all (fun root =>
        (CedarPooSpec.PolicyJson.publish model root schema).isOk) = true := by
  native_decide

end CedarPooSpec.DepartmentSynthesisExample
