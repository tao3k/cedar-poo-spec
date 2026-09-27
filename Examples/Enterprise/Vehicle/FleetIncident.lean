import CedarPooSpec.Revision
import CedarPooSpec.PolicyJson
import CedarPooSpec.CompoundAuthorization
import Cedar.Validation.RequestEntityValidator

/-!
Authorization design prompted by a reported fleet MQTT backend compromise.
The fleets, people, packages, and rollout process here are fictive. The host
must authenticate channels and verify package, approval, and safety evidence.
-/

namespace CedarPooSpec.FleetIncidentExample

open Cedar.Spec Cedar.Data Cedar.Validation CedarPooSpec.PolicyModules
open CedarPooSpec.Soundness CedarPooSpec.PolicyValidation LeanPoo.Proof

def securityType : EntityType := ⟨"SecurityReviewer", []⟩
def operatorType : EntityType := ⟨"FleetOperator", []⟩
def batchType : EntityType := ⟨"VehicleBatch", []⟩
def actionType : EntityType := ⟨"Action", []⟩
def reviewer : EntityUID := ⟨securityType, "oem-security"⟩
def operator : EntityUID := ⟨operatorType, "fleet-ops"⟩
def pilotBatch : EntityUID := ⟨batchType, "affected-pilot"⟩
def broadBatch : EntityUID := ⟨batchType, "affected-broad"⟩
def safeBatch : EntityUID := ⟨batchType, "unaffected"⟩
def incompatibleBatch : EntityUID := ⟨batchType, "incompatible"⟩
def approve : EntityUID := ⟨actionType, "approve-update"⟩
def deploy : EntityUID := ⟨actionType, "deploy-update"⟩
def command : EntityUID := ⟨actionType, "publish-command"⟩

def emptyEntry : EntitySchemaEntry := .standard ⟨Set.empty, Map.empty, none⟩
def batchEntry : EntitySchemaEntry := .standard ⟨Set.empty, Map.make [
  ("affected", .required (.bool .anyBool)),
  ("pilot", .required (.bool .anyBool)),
  ("compatible", .required (.bool .anyBool))], none⟩
def contextType : RecordType := Map.make [
  ("channelAuthenticated", .required (.bool .anyBool)),
  ("packageSigned", .required (.bool .anyBool)),
  ("trialPassed", .required (.bool .anyBool)),
  ("releaseApproved", .required (.bool .anyBool)),
  ("safeToUpdate", .required (.bool .anyBool))]
def actionEntry (principal : EntityType) : ActionSchemaEntry :=
  ⟨Set.make [principal], Set.make [batchType], Set.empty, contextType⟩
def schema : Schema :=
  ⟨Map.make [(securityType, emptyEntry), (operatorType, emptyEntry),
    (batchType, batchEntry)],
    Map.make [(approve, actionEntry securityType),
      (deploy, actionEntry operatorType), (command, actionEntry operatorType)]⟩

def emptyData : EntityData :=
  { attrs := Map.empty, ancestors := Set.empty, tags := Map.empty }
def batchData (affected pilot compatible : Bool) : EntityData :=
  { attrs := Map.make [
      ("affected", .prim (.bool affected)),
      ("pilot", .prim (.bool pilot)),
      ("compatible", .prim (.bool compatible))],
    ancestors := Set.empty, tags := Map.empty }
def entities : Entities := Map.make [
  (reviewer, emptyData), (operator, emptyData),
  (pilotBatch, batchData true true true),
  (broadBatch, batchData true false true),
  (safeBatch, batchData false false true),
  (incompatibleBatch, batchData true true false),
  (approve, actionSchemaEntryToEntityData (actionEntry securityType)),
  (deploy, actionSchemaEntryToEntityData (actionEntry operatorType)),
  (command, actionSchemaEntryToEntityData (actionEntry operatorType))]

def ctx (name : String) : Expr := .getAttr (.var .context) name
def batchFact (name : String) : Expr := .getAttr (.var .resource) name
def policy (id : String) (effect : Effect) (principal action : EntityUID)
    (body : Expr) : Policy :=
  { id, effect,
    principalScope := .principalScope (.eq principal),
    actionScope := .actionScope (.eq action),
    resourceScope := .resourceScope .any,
    condition := [{ kind := .when, body }] }

def commandBase : Policy :=
  policy "fleet-command" .permit operator command (.lit (.bool true))
def approveBase : Policy :=
  policy "oem-approval" .permit reviewer approve (.lit (.bool true))
def deployBase : Policy :=
  policy "fleet-deployment" .permit operator deploy (.lit (.bool true))
def supplierEvidence : Expr := .and (ctx "packageSigned") (batchFact "compatible")
def deploySupplier : Policy :=
  { deployBase with condition := [{ kind := .when, body := supplierEvidence }] }
def approveReviewed : Policy :=
  { approveBase with condition := [
      { kind := .when,
        body := .and (ctx "channelAuthenticated")
          (.and (ctx "trialPassed") (ctx "releaseApproved")) }] }
def commandAuthenticated : Policy :=
  { commandBase with condition := [
      { kind := .when, body := ctx "channelAuthenticated" }] }
def deployPilot : Policy :=
  { deployBase with condition := [
      { kind := .when,
        body := .and (ctx "channelAuthenticated")
          (.and supplierEvidence (.and (ctx "safeToUpdate") (batchFact "pilot"))) }] }
def deployExpanded : Policy :=
  { deployBase with condition := [
      { kind := .when,
        body := .and (ctx "channelAuthenticated")
          (.and supplierEvidence (ctx "safeToUpdate")) }] }
def incidentVeto : Policy :=
  { id := "freeze-affected-commands", effect := .forbid,
    principalScope := .principalScope .any,
    actionScope := .actionScope (.eq command),
    resourceScope := .resourceScope .any,
    condition := [{ kind := .when, body := batchFact "affected" }] }

def model : Model := { modules := [
  { name := "Base", edits := [
      .extend commandBase, .extend approveBase, .extend deployBase] },
  { name := "Supplier", parentOrders := [["Base"]],
    edits := [.overlay deploySupplier] },
  { name := "Security", parentOrders := [["Base"]],
    edits := [.overlay approveReviewed] },
  { name := "Fleet", parentOrders := [["Base"]],
    edits := [.overlay commandAuthenticated] },
  { name := "Integrated", parentOrders := [["Supplier", "Security", "Fleet"]],
    edits := [.overlay deployPilot] },
  { name := "Incident", parentOrders := [["Integrated"]],
    edits := [.extend incidentVeto] },
  { name := "Expanded", parentOrders := [["Incident"]],
    edits := [.overlay deployExpanded] },
  { name := "Recovered", parentOrders := [["Expanded"]],
    edits := [.remove incidentVeto.id] }] }

structure Facts where
  channelAuthenticated : Bool := true
  packageSigned : Bool := true
  trialPassed : Bool := true
  releaseApproved : Bool := true
  safeToUpdate : Bool := true

def context (facts : Facts) : Map String Value := Map.make [
  ("channelAuthenticated", .prim (.bool facts.channelAuthenticated)),
  ("packageSigned", .prim (.bool facts.packageSigned)),
  ("trialPassed", .prim (.bool facts.trialPassed)),
  ("releaseApproved", .prim (.bool facts.releaseApproved)),
  ("safeToUpdate", .prim (.bool facts.safeToUpdate))]
def updateChecks (root : String) (batch : EntityUID) (facts : Facts) :
    List (String × Request) := [
  (root, ⟨reviewer, approve, batch, context facts⟩),
  (root, ⟨operator, deploy, batch, context facts⟩)]
def commandRequest (batch : EntityUID) (facts : Facts) : Request :=
  ⟨operator, command, batch, context facts⟩
def authorizeUpdate (root : String) (batch : EntityUID) (facts : Facts) : Bool :=
  match CedarPooSpec.CompoundAuthorization.authorizeLayers model
      (updateChecks root batch facts) entities with
  | .error _ => false
  | .ok receipts => CedarPooSpec.CompoundAuthorization.layersAllowed receipts
def authorizeCommand (root : String) (batch : EntityUID) (facts : Facts) : Bool :=
  match CedarPooSpec.CompoundAuthorization.authorizeLayers model
      [(root, commandRequest batch facts)] entities with
  | .error _ => false
  | .ok receipts => CedarPooSpec.CompoundAuthorization.layersAllowed receipts

def updateCases : List (String × String × EntityUID × Facts × Bool) := [
  ("legacy-unsigned-package", "Base", pilotBatch, { packageSigned := false }, true),
  ("pilot-update", "Integrated", pilotBatch, {}, true),
  ("broad-before-trial", "Integrated", broadBatch, {}, false),
  ("unsigned-package", "Integrated", pilotBatch, { packageSigned := false }, false),
  ("incompatible-vehicle", "Integrated", incompatibleBatch, {}, false),
  ("trial-not-passed", "Integrated", pilotBatch, { trialPassed := false }, false),
  ("release-not-approved", "Integrated", pilotBatch, { releaseApproved := false }, false),
  ("unauthenticated-update", "Integrated", pilotBatch,
    { channelAuthenticated := false }, false),
  ("unsafe-update", "Integrated", pilotBatch, { safeToUpdate := false }, false),
  ("repair-during-freeze", "Incident", pilotBatch, {}, true),
  ("expanded-cohort", "Expanded", broadBatch, {}, true),
  ("expanded-still-requires-signature", "Expanded", broadBatch,
    { packageSigned := false }, false),
  ("recovered-cohort", "Recovered", broadBatch, {}, true)]
def commandCases : List (String × String × EntityUID × Facts × Bool) := [
  ("legacy-unauthenticated-command", "Base", pilotBatch,
    { channelAuthenticated := false }, true),
  ("authenticated-command", "Integrated", pilotBatch, {}, true),
  ("unauthenticated-command", "Integrated", pilotBatch,
    { channelAuthenticated := false }, false),
  ("affected-command-frozen", "Incident", pilotBatch, {}, false),
  ("unaffected-command-survives", "Incident", safeBatch, {}, true),
  ("unauthenticated-unaffected-command", "Incident", safeBatch,
    { channelAuthenticated := false }, false),
  ("affected-command-restored", "Recovered", pilotBatch, {}, true)]

def casesExact : Bool :=
  updateCases.all (fun (_, root, batch, facts, expected) =>
    authorizeUpdate root batch facts == expected) &&
  commandCases.all (fun (_, root, batch, facts, expected) =>
    authorizeCommand root batch facts == expected)
theorem casesExactFully : casesExact = true := by native_decide

def rootsValidated : Bool :=
  ["Base", "Supplier", "Security", "Fleet", "Integrated", "Incident",
    "Expanded", "Recovered"].all fun root =>
      (CedarPooSpec.PolicyJson.publish model root schema).isOk
theorem rootsValidatedFully : rootsValidated = true := by native_decide

def incidentRevision : Revision :=
  (model.compileRevision "Integrated" "Incident").toOption.get (by native_decide)
theorem incidentDelta :
    incidentRevision.changedPolicyIds = ["freeze-affected-commands"] ∧
    incidentRevision.freshPolicies = [incidentVeto] := by native_decide
def recoveryRevision : Revision :=
  (model.compileRevision "Expanded" "Recovered").toOption.get (by native_decide)
theorem recoveryDelta :
    recoveryRevision.changedPolicyIds = ["freeze-affected-commands"] ∧
    recoveryRevision.freshPolicies = [] := by native_decide

def incidentRequest : Request := commandRequest pilotBatch {}
def incidentBefore : AuthorizationSnapshot :=
  incidentRevision.beforeSnapshot schema incidentRequest entities
theorem incidentBaseline : Certificate incidentBefore.proofObject :=
  incidentBefore.certificateOfChecks (by native_decide)
private theorem okOfIsOk {ε : Type} (result : Except ε Unit)
    (accepted : result.isOk = true) : result = .ok () := by
  cases result with
  | ok value => cases value; rfl
  | error _ => cases accepted
theorem incidentFreshCertificates :
    ∀ policy ∈ incidentRevision.freshPolicies,
      Certificate (Snapshot.mk policy schema).proofObject := by
  intro policy member
  rw [incidentDelta.2] at member
  simp only [List.mem_cons, List.not_mem_nil, or_false] at member
  subst policy
  exact (Snapshot.mk incidentVeto schema).certificate
    (okOfIsOk _ (by native_decide))
theorem incidentCertificate :
    Certificate (incidentRevision.afterSnapshot schema incidentRequest entities).proofObject :=
  incidentRevision.authorizationCertificate schema incidentRequest entities
    (by simpa [incidentBefore] using incidentBaseline) incidentFreshCertificates
example : Cedar.Thm.AllEvaluateToBool incidentRevision.afterPolicies
    incidentRequest entities :=
  certifiedAuthorizationSound
    (incidentRevision.afterSnapshot schema incidentRequest entities)
    incidentCertificate

def recoveryBefore : AuthorizationSnapshot :=
  recoveryRevision.beforeSnapshot schema incidentRequest entities
theorem recoveryBaseline : Certificate recoveryBefore.proofObject :=
  recoveryBefore.certificateOfChecks (by native_decide)
theorem recoveryCertificate :
    Certificate (recoveryRevision.afterSnapshot schema incidentRequest entities).proofObject :=
  recoveryRevision.authorizationCertificate schema incidentRequest entities
    (by simpa [recoveryBefore] using recoveryBaseline)
    (by intro policy member; simp [recoveryDelta.2] at member)
example : Cedar.Thm.AllEvaluateToBool recoveryRevision.afterPolicies
    incidentRequest entities :=
  certifiedAuthorizationSound
    (recoveryRevision.afterSnapshot schema incidentRequest entities)
    recoveryCertificate

end CedarPooSpec.FleetIncidentExample
