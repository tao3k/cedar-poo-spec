import Examples.Enterprise.AWS.AgentCore.Gateway
import CedarPooSpec.Revision

/-! Cedar Gateway projection of the AWS reconciliation-agent sample. The
Gateway policies authorize individual calls; the sample's persisted proposal,
evidence-quality, status-transition, and email-draft checks are owned by its
request interceptor and are not asserted by this model. -/

namespace CedarPooSpec.AWS.Reconciliation

open Cedar.Spec Cedar.Data Cedar.Validation CedarPooSpec.PolicyModules
open CedarPooSpec.AWS.AgentCore

def iamType : EntityType := ⟨"IamEntity", ["AgentCore"]⟩
def agent : EntityUID := ⟨iamType, "recon-agent"⟩
def worker : EntityUID := ⟨iamType, "recon-worker"⟩
def platform : EntityUID := ⟨iamType, "recon-bff"⟩
def gateway : EntityUID := CedarPooSpec.AWS.AgentCore.gateway "recon-egress-gateway"

def searchLedger : EntityUID := action "general-ledger___search_ledger"
def searchNotices : EntityUID := action "notices___search_notices"
def retrieve : EntityUID := action "managed-kb___Retrieve"
def searchCorrespondence : EntityUID := action "correspondence-search___search_correspondence"
def listContacts : EntityUID := action "contacts___list_contacts"
def listTemplates : EntityUID := action "templates___list_templates"
def graphList : EntityUID := action "microsoft-graph___listSharedMailboxMessages"
def graphSend : EntityUID := action "microsoft-graph___sendSharedMailboxMail"
def setDrawStatus : EntityUID := action "set-draw-status___set_draw_status"
def updateStatus : EntityUID := action "recon-status___recon_update_status"

def ledgerActions : List EntityUID := [searchLedger, searchNotices]
def knowledgeActions : List EntityUID := [retrieve]
def correspondenceActions : List EntityUID :=
  [searchCorrespondence, graphList, graphSend]
def directoryActions : List EntityUID := [listContacts, listTemplates]
def readActions : List EntityUID :=
  ledgerActions ++ knowledgeActions ++ correspondenceActions ++ directoryActions
def allActions : List EntityUID := readActions ++ [setDrawStatus, updateStatus]

def readEntry : ActionSchemaEntry := actionEntryFor [iamType] Map.empty
def confidenceInput : RecordType := Map.make [("confidence", .optional (.ext .decimal))]
def writeEntry : ActionSchemaEntry :=
  actionEntryFor [iamType] (Map.make [("input", .required (.record confidenceInput))])
def schema : Schema :=
  ⟨Map.make [
    (iamType, .standard ⟨Set.empty, Map.empty, none⟩),
    (gatewayType, .standard ⟨Set.empty, Map.empty, none⟩)],
    Map.make (readActions.map (·, readEntry) ++
      [(setDrawStatus, writeEntry), (updateStatus, readEntry)])⟩

def entities : Entities := Map.make
  ([(agent, entityData), (worker, entityData),
    (platform, entityData), (gateway, entityData)] ++
    allActions.map (·, entityData))

def decimal (value : String) : Cedar.Spec.Ext.Decimal :=
  match Cedar.Spec.Ext.Decimal.decimal value with
  | some parsed => parsed
  | none => panic! s!"invalid confidence percent: {value}"

def readRequest (principal actionUID : EntityUID) : Request :=
  ⟨principal, actionUID, gateway, Map.empty⟩

def writeRequest (principal : EntityUID) (confidence : Option String) : Request :=
  let attrs := confidence.toList.map fun value =>
    ("confidence", Value.ext (.decimal (decimal value)))
  ⟨principal, setDrawStatus, gateway,
    Map.make [("input", .record (Map.make attrs))]⟩

def input : Expr := .getAttr (.var .context) "input"
def confidenceAtLeast (threshold : String) : Expr :=
  .and (.hasAttr input "confidence")
    (.call .greaterThanOrEqual [
      .getAttr input "confidence", .call .decimal [.lit (.string threshold)]])

def permit (id : String) (principal : PrincipalScope)
    (actions : List EntityUID) (condition : Conditions := []) : Policy :=
  gatewayPolicy id .permit principal gateway (.actionInAny actions) condition

def sourceReads : Policy :=
  permit "recon_reads" (.principalScope .any) readActions
def ledgerReads : Policy :=
  permit "recon_ledger_reads" (.principalScope .any) ledgerActions
def knowledgeReads : Policy :=
  permit "recon_knowledge_reads" (.principalScope .any) knowledgeActions
def correspondenceReads : Policy :=
  permit "recon_correspondence_reads" (.principalScope .any) correspondenceActions
def directoryReads : Policy :=
  permit "recon_directory_reads" (.principalScope .any) directoryActions

def writeGate (threshold : String) : Policy :=
  gatewayPolicy "recon_write_gate" .permit (.principalScope .any)
    gateway (.actionScope (.eq setDrawStatus))
    [{ kind := .when, body := confidenceAtLeast threshold }]
def write85 : Policy := writeGate "85.0"
def write90 : Policy := writeGate "90.0"

/-! The source scopes these platform grants to IAM role names using principal.id
patterns. Exact representative principal UIDs are used here, so the model
does not assert equivalence for every possible AWS session ARN. -/
def humanWrite : Policy :=
  gatewayPolicy "recon_write_human" .permit (.principalScope (.eq platform))
    gateway (.actionScope (.eq setDrawStatus))
def statusPlatform : Policy :=
  gatewayPolicy "recon_status_platform" .permit (.principalScope (.eq platform))
    gateway (.actionScope (.eq updateStatus))

def correspondencePaused : Policy :=
  { correspondenceReads with
    actionScope := .actionInAny (correspondenceActions.filter (· != graphSend)) }

def model : Model := { modules := [
  { name := "SourceReads", edits := [.extend sourceReads] },
  { name := "Ledger", edits := [.extend ledgerReads] },
  { name := "Knowledge", edits := [.extend knowledgeReads] },
  { name := "Correspondence", edits := [.extend correspondenceReads] },
  { name := "Directory", edits := [.extend directoryReads] },
  { name := "Write", edits := [.extend write85] },
  { name := "Human", edits := [.extend humanWrite] },
  { name := "Status", edits := [.extend statusPlatform] },
  { name := "SourceCombined", parentOrders :=
      [["SourceReads", "Write", "Human", "Status"]] },
  { name := "OwnerCombined", parentOrders :=
      [["Ledger", "Knowledge", "Correspondence", "Directory",
        "Write", "Human", "Status"]] },
  { name := "Threshold90", parentOrders := [["OwnerCombined"]],
    edits := [.overlay write90] },
  { name := "GraphPaused", parentOrders := [["OwnerCombined"]],
    edits := [.overlay correspondencePaused] },
  { name := "JointIncident", parentOrders := [["Threshold90", "GraphPaused"]] },
  { name := "Recovered", parentOrders := [["JointIncident"]],
    edits := [.overlay write85, .overlay correspondenceReads] }] }

def decideAt (root : String) (request : Request) : Option Decision := do
  let policies ← (model.compile root).toOption
  let response := isAuthorized request entities policies
  if response.erroringPolicies.isEmpty then some response.decision else none

theorem namedReadsEquivalent :
    [agent, worker, platform].all (fun principal =>
      readActions.all (fun tool =>
        decideAt "SourceCombined" (readRequest principal tool) ==
        decideAt "OwnerCombined" (readRequest principal tool))) = true := by
  native_decide

theorem thresholdAndHumanPaths :
    decideAt "OwnerCombined" (writeRequest worker (some "84.9999")) = some .deny ∧
    decideAt "OwnerCombined" (writeRequest worker (some "85.0000")) = some .allow ∧
    decideAt "OwnerCombined" (writeRequest worker none) = some .deny ∧
    decideAt "OwnerCombined" (writeRequest platform none) = some .allow ∧
    decideAt "Threshold90" (writeRequest worker (some "85.0000")) = some .deny ∧
    decideAt "Threshold90" (writeRequest worker (some "90.0000")) = some .allow := by
  native_decide

theorem platformStatusBoundary :
    decideAt "OwnerCombined" (readRequest agent updateStatus) = some .deny ∧
    decideAt "OwnerCombined" (readRequest platform updateStatus) = some .allow := by
  native_decide

/-- The source Gateway's unconditional Graph send permit requires the separate
    interceptor confirmation and approved-draft checks. -/
theorem gatewayAloneAllowsGraphSend :
    decideAt "SourceCombined" (readRequest agent graphSend) = some .allow ∧
    decideAt "GraphPaused" (readRequest agent graphSend) = some .deny ∧
    decideAt "GraphPaused" (readRequest agent searchCorrespondence) = some .allow ∧
    decideAt "GraphPaused" (readRequest agent graphList) = some .allow := by
  native_decide

theorem independentIncidentEdits :
    ((model.compileRevision "OwnerCombined" "Threshold90").toOption.get
      (by native_decide)).changedPolicyIds = [write85.id] ∧
    ((model.compileRevision "OwnerCombined" "GraphPaused").toOption.get
      (by native_decide)).changedPolicyIds = [correspondenceReads.id] := by
  native_decide

theorem jointIncidentAndRecovery :
    decideAt "JointIncident" (writeRequest worker (some "85.0000")) = some .deny ∧
    decideAt "JointIncident" (readRequest agent graphSend) = some .deny ∧
    decideAt "JointIncident" (readRequest agent searchLedger) = some .allow ∧
    decideAt "Recovered" (writeRequest worker (some "85.0000")) = some .allow ∧
    decideAt "Recovered" (readRequest agent graphSend) = some .allow := by
  native_decide

theorem allRootsValidated :
    ["SourceCombined", "OwnerCombined", "Threshold90", "GraphPaused",
      "JointIncident", "Recovered"].all (fun root =>
        (CedarPooSpec.PolicyJson.publish model root schema).isOk) = true := by
  native_decide

end CedarPooSpec.AWS.Reconciliation
