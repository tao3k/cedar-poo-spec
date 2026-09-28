import CedarPooSpec.Revision
import CedarPooSpec.PolicyValidation
import CedarPooSpec.Soundness

/-!
An enterprise data-access model combining a project subscription, an
independent data-owner approval, enclave attestation, and a region boundary.
These facts are projected by external authorities; Cedar does not verify a
Nitro attestation document or grant Lake Formation/KMS permissions.
-/

namespace CedarPooSpec.AttestedDataAccessExample

open Cedar.Spec Cedar.Validation Cedar.Data
open CedarPooSpec.PolicyModules CedarPooSpec.Soundness
open LeanPoo.Proof

def workerType : EntityType := ⟨"DataWorker", []⟩
def datasetType : EntityType := ⟨"Dataset", []⟩
def actionType : EntityType := ⟨"Action", []⟩
def queryAction : EntityUID := ⟨actionType, "query"⟩

def workerEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.make [
    ("project", .required .string),
    ("operator", .required .string)], none⟩
def datasetEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.make [
    ("project", .required .string),
    ("region", .required .string),
    ("measurement", .required .string)], none⟩
def contextType : RecordType := Map.make [
  ("subscriptionActive", .required (.bool .anyBool)),
  ("ownerApproved", .required (.bool .anyBool)),
  ("approver", .required .string),
  ("attestationVerified", .required (.bool .anyBool)),
  ("attestationFresh", .required (.bool .anyBool)),
  ("measurement", .required .string),
  ("region", .required .string),
  ("purpose", .required .string)]
def actionEntry : ActionSchemaEntry :=
  ⟨Set.make [workerType], Set.make [datasetType], Set.empty, contextType⟩
def schema : Schema :=
  ⟨Map.make [(workerType, workerEntry), (datasetType, datasetEntry)],
   Map.make [(queryAction, actionEntry)]⟩
def datasetEntryV2 : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.make [
    ("project", .required .string),
    ("region", .required .string),
    ("measurement", .required .string),
    ("classification", .optional .string)], none⟩
def schemaV2 : Schema :=
  ⟨Map.make [(workerType, workerEntry), (datasetType, datasetEntryV2)],
   Map.make [(queryAction, actionEntry)]⟩
def hasClassification (candidate : Schema) : Bool :=
  match candidate.ets.find? datasetType with
  | some (.standard entry) => entry.attrs.contains "classification"
  | _ => false
theorem schemaChanged : schema ≠ schemaV2 := by
  intro same
  have projected := congrArg hasClassification same
  have old : hasClassification schema = false := by native_decide
  have new : hasClassification schemaV2 = true := by native_decide
  rw [old, new] at projected
  cases projected

def analyst : EntityUID := ⟨workerType, "analyst-a"⟩
def customerDataset : EntityUID := ⟨datasetType, "customer-a"⟩
def financeDataset : EntityUID := ⟨datasetType, "finance-b"⟩
def datasetData (project : String) : EntityData :=
  { attrs := Map.make [
      ("project", .prim (.string project)),
      ("region", .prim (.string "eu-west-1")),
      ("measurement", .prim (.string "approved-image"))],
    ancestors := Set.empty, tags := Map.empty }
def workerData : EntityData :=
  { attrs := Map.make [
      ("project", .prim (.string "analytics")),
      ("operator", .prim (.string "alice"))],
    ancestors := Set.empty, tags := Map.empty }
def entities : Entities := Map.make [
  (analyst, workerData),
  (customerDataset, datasetData "analytics"),
  (financeDataset, datasetData "finance"),
  (queryAction, actionSchemaEntryToEntityData actionEntry)]

def contextFact (name : String) : Expr := .getAttr (.var .context) name
def principalFact (name : String) : Expr := .getAttr (.var .principal) name
def resourceFact (name : String) : Expr := .getAttr (.var .resource) name
def projectMatches : Expr :=
  .binaryApp .eq (principalFact "project") (resourceFact "project")
def subscriptionActive : Expr := contextFact "subscriptionActive"
def ownerApproved : Expr := contextFact "ownerApproved"
def independentApprover : Expr :=
  .unaryApp .not
    (.binaryApp .eq (principalFact "operator") (contextFact "approver"))
def attestationValid : Expr :=
  .and (contextFact "attestationVerified")
    (.and (contextFact "attestationFresh")
      (.binaryApp .eq (contextFact "measurement") (resourceFact "measurement")))
def attestationV1 : Expr :=
  .and (contextFact "attestationVerified")
    (.binaryApp .eq (contextFact "measurement") (resourceFact "measurement"))
def regionMatches : Expr :=
  .binaryApp .eq (contextFact "region") (resourceFact "region")
def analyticsPurpose : Expr :=
  .binaryApp .eq (contextFact "purpose") (.lit (.string "analytics"))

def queryPolicy (id : String) (effect : Effect) (body : Expr) : Policy :=
  { id := id, effect := effect,
    principalScope := .principalScope .any,
    actionScope := .actionScope (.eq queryAction),
    resourceScope := .resourceScope .any,
    condition := [{ kind := .when, body := body }] }

def projectPermit : Policy :=
  queryPolicy "project-subscription" .permit
    (.and projectMatches subscriptionActive)
def purposePermit : Policy :=
  queryPolicy "project-subscription" .permit
    (.and projectMatches (.and subscriptionActive analyticsPurpose))
def legacyPermit : Policy :=
  queryPolicy "legacy-subscription" .permit subscriptionActive

/-- An independently owned governance control has a stable policy identity
    and one denial condition. A revision changes the condition, not its ID. -/
structure ControlObject where
  moduleName : String
  policyId : String
  denyWhen : Expr

def ControlObject.policy (object : ControlObject) : Policy :=
  queryPolicy object.policyId .forbid object.denyWhen

def ControlObject.module (object : ControlObject) (parent : String)
    (change : Policy → Edit) : Module :=
  { name := object.moduleName, parentOrders := [[parent]],
    edits := [change object.policy] }

def ownerControl : ControlObject :=
  ⟨"DataOwner", "owner-approval",
    .unaryApp .not (.and ownerApproved independentApprover)⟩
def platformControl : ControlObject :=
  ⟨"Platform", "attested-platform", .unaryApp .not attestationV1⟩
def platformControlV2 : ControlObject :=
  ⟨"PlatformV2", platformControl.policyId, .unaryApp .not attestationValid⟩
def complianceControl : ControlObject :=
  ⟨"Compliance", "region-boundary", .unaryApp .not regionMatches⟩

def ownerVeto : Policy := ownerControl.policy
def platformVetoV1 : Policy := platformControl.policy
def platformVetoV2 : Policy := platformControlV2.policy
def regionVeto : Policy := complianceControl.policy

def base : Module :=
  { name := "Base", suffix := true,
    edits := [.extend projectPermit, .extend legacyPermit] }
def dataOwner : Module := ownerControl.module "Base" .extend
def platform : Module := platformControl.module "Base" .extend
def platformV2 : Module := platformControlV2.module "Platform" .overlay
def compliance : Module := complianceControl.module "Base" .extend

/-- A governed view owns its C4 precedence. Every view performs the same
    purpose overlay and legacy-grant removal after its owners are resolved. -/
structure GovernanceView where
  name : String
  owners : List String

def GovernanceView.module (view : GovernanceView) : Module :=
  { name := view.name, parentOrders := [view.owners],
    edits := [.overlay purposePermit, .remove legacyPermit.id] }

def GovernanceView.reviseOwner (view : GovernanceView) (name oldOwner newOwner : String)
    (_present : oldOwner ∈ view.owners) : GovernanceView :=
  ⟨name, view.owners.map (fun owner => if owner == oldOwner then newOwner else owner)⟩

def GovernanceView.prioritize (view : GovernanceView) (name owner : String)
    (_present : owner ∈ view.owners) : GovernanceView :=
  ⟨name, owner :: view.owners.filter (· != owner)⟩

def baselineView : GovernanceView :=
  ⟨"Governed", [ownerControl.moduleName, platformControl.moduleName,
    complianceControl.moduleName]⟩
def strengthenedView : GovernanceView :=
  baselineView.reviseOwner "GovernedV2"
    platformControl.moduleName platformControlV2.moduleName (by native_decide)
def reorderedView : GovernanceView :=
  strengthenedView.prioritize "GovernedV2Reordered"
    complianceControl.moduleName (by native_decide)
def governanceViews : List GovernanceView :=
  [baselineView, strengthenedView, reorderedView]

def governed : Module := baselineView.module
def governedV2 : Module := strengthenedView.module
def governedV2Reordered : Module := reorderedView.module

theorem governanceViewsShareEdits :
    governed.edits = governedV2.edits ∧
    governedV2.edits = governedV2Reordered.edits := by native_decide

def sandbox : Module :=
  { name := "Sandbox", parentOrders := [["Base"]] }
def auditView : Module :=
  { name := "AuditView", parentOrders := [[strengthenedView.name]] }
def model : Model :=
  { modules := [base, dataOwner, platform, platformV2, compliance] ++
      governanceViews.map GovernanceView.module ++ [sandbox, auditView] }
/-- An owner chain can opt into C4's indivisible inherited suffix. -/
def strictOwner : Module := { dataOwner with suffix := true }
def independentCompliance : Module :=
  { name := "IndependentCompliance", edits := [.extend regionVeto] }
def ownerSuffixModel (strict : Bool) : Model :=
  { modules := [base, { strictOwner with suffix := strict }, independentCompliance,
      { name := "OwnerSplit",
        parentOrders := [["DataOwner", "IndependentCompliance", "Base"]] }] }
def ownerSuffixRejectsInterleaving : Bool :=
  match (ownerSuffixModel true).compile "OwnerSplit" with
  | .error (.c4 .suffixOrderViolation) => true
  | _ => false
theorem ownerSuffixRejectsInterleavingExact :
    ownerSuffixRejectsInterleaving = true := by
  native_decide
theorem ordinaryOrderAcceptsInterleaving :
    ((ownerSuffixModel false).compile "OwnerSplit").isOk = true := by
  native_decide
def revision : Revision :=
  (model.compileRevision "Governed" "GovernedV2").toOption.get (by native_decide)
def compilation : Compilation :=
  revision.after
def updatedPolicies : Policies := revision.afterPolicies
def baselinePolicies : Policies := revision.beforePolicies
theorem policyDeltaExact : revision.changedPolicyIds = ["attested-platform"] := by
  native_decide
theorem policyListsDiffer :
    revision.beforePolicies ≠ revision.afterPolicies := by
  native_decide
def auditRevision : Revision :=
  (model.compileRevision "GovernedV2" "AuditView").toOption.get (by native_decide)
theorem auditRevisionHasNoPolicyDelta : auditRevision.changedPolicyIds = [] := by
  native_decide
def reorderRevision : Revision :=
  (model.compileRevision "GovernedV2" "GovernedV2Reordered").toOption.get
    (by native_decide)
theorem reorderHasNoFreshPolicies : reorderRevision.freshPolicies = [] := by
  native_decide
theorem reorderChangesOrderedList :
    reorderRevision.beforePolicies ≠ reorderRevision.afterPolicies := by
  native_decide
theorem reorderStartsFromUpdatedPolicies :
    reorderRevision.beforePolicies = updatedPolicies := by
  native_decide
theorem reorderStillTouchesPolicyKey :
    changedDependencies policiesObligation reorderRevision.authorizationPatch =
      [.policies] := by
  native_decide

structure Facts where
  subscriptionActive : Bool := true
  ownerApproved : Bool := true
  approver : String := "steward-bob"
  attestationVerified : Bool := true
  attestationFresh : Bool := true
  measurement : String := "approved-image"
  region : String := "eu-west-1"
  purpose : String := "analytics"

def request (dataset : EntityUID) (facts : Facts) : Request :=
  ⟨analyst, queryAction, dataset, Map.make [
    ("subscriptionActive", .prim (.bool facts.subscriptionActive)),
    ("ownerApproved", .prim (.bool facts.ownerApproved)),
    ("approver", .prim (.string facts.approver)),
    ("attestationVerified", .prim (.bool facts.attestationVerified)),
    ("attestationFresh", .prim (.bool facts.attestationFresh)),
    ("measurement", .prim (.string facts.measurement)),
    ("region", .prim (.string facts.region)),
    ("purpose", .prim (.string facts.purpose))]⟩

def unchangedCases : List (String × Request × Decision) := [
  ("approved-attested-query", request customerDataset {}, .allow),
  ("other-project", request financeDataset {}, .deny),
  ("owner-rejected", request customerDataset { ownerApproved := false }, .deny),
  ("wrong-measurement", request customerDataset
    { measurement := "unapproved-image" }, .deny),
  ("wrong-region", request customerDataset { region := "us-east-1" }, .deny)]

def stableDecisions : Bool :=
  (validate baselinePolicies schema).isOk &&
  (validate updatedPolicies schema).isOk &&
  unchangedCases.all fun (_, req, expected) =>
    let before := isAuthorized req entities baselinePolicies
    let after := isAuthorized req entities updatedPolicies
    before.decision == expected && after.decision == expected &&
      before.erroringPolicies.isEmpty && after.erroringPolicies.isEmpty
theorem stableDecisionsFully : stableDecisions = true := by native_decide
theorem caseNamesUnique : (unchangedCases.map (fun (name, _, _) => name)).Nodup := by
  native_decide

def staleAttestationDelta : Bool :=
  let req := request customerDataset { attestationFresh := false }
  (isAuthorized req entities baselinePolicies).decision == .allow &&
  (isAuthorized req entities updatedPolicies).decision == .deny
theorem staleAttestationDeltaExact : staleAttestationDelta = true := by native_decide

def broadPermitRisk : Bool :=
  match model.compile "DataOwner" with
  | .error _ => false
  | .ok inherited =>
    (validate inherited schema).isOk &&
    (isAuthorized (request financeDataset {}) entities inherited).decision == .allow &&
    (isAuthorized (request financeDataset {}) entities updatedPolicies).decision == .deny
theorem broadPermitRiskDetected : broadPermitRisk = true := by native_decide

def compositionTraceConforms : Bool :=
  (LeanPoo.C4.linearize model.graph "GovernedV2").toOption ==
    some ["GovernedV2", "DataOwner", "PlatformV2", "Platform", "Compliance", "Base"] &&
  compilation.applied.length == 8 &&
  (match compilation.applied.getLast? with
   | some { moduleName := "GovernedV2", edit := .remove "legacy-subscription" } => true
   | _ => false) &&
  (match compilation.policies.find? (fun item => item.policy.id == "attested-platform") with
   | some item => item.introducedBy == "Platform" && item.lastEditedBy == "PlatformV2"
   | none => false)
theorem compositionTraceConformsFully : compositionTraceConforms = true := by
  native_decide

def impactIsLocal : Bool :=
  let affected := invalidatedNodes model.graph ["PlatformV2"]
  affected.length == 4 &&
  affected.contains "PlatformV2" && affected.contains "GovernedV2" &&
  affected.contains "GovernedV2Reordered" &&
  affected.contains "AuditView" &&
  !affected.contains "Governed" && !affected.contains "DataOwner" &&
  !affected.contains "Compliance" && !affected.contains "Sandbox"
theorem impactIsLocalFully : impactIsLocal = true := by native_decide

def policyRevision : Patch AuthorizationKey AuthorizationValue :=
  revision.authorizationPatch
def proofReuseFootprint : Bool :=
  (match changedDependencies policiesObligation policyRevision with
   | [.policies] => true
   | _ => false) &&
  (changedDependencies schemaObligation policyRevision).isEmpty &&
  (changedDependencies requestObligation policyRevision).isEmpty &&
  (changedDependencies entitiesObligation policyRevision).isEmpty
theorem proofReuseFootprintExact : proofReuseFootprint = true := by native_decide

def authorizedRequest : Request := request customerDataset {}
def baselineSnapshot : AuthorizationSnapshot :=
  revision.beforeSnapshot schema authorizedRequest entities
def snapshot : AuthorizationSnapshot :=
  revision.afterSnapshot schema authorizedRequest entities
theorem auditRevisionHasNoPendingProofs :
    (pending snapshot.proofObject auditRevision.authorizationPatch).isEmpty = true := by
  native_decide
private theorem okOfIsOk {ε : Type} (result : Except ε Unit)
    (h : result.isOk = true) : result = .ok () := by
  cases result with
  | ok value => cases value; rfl
  | error _ => cases h
theorem baselineCertificate : Certificate baselineSnapshot.proofObject :=
  baselineSnapshot.certificateOfChecks (by native_decide)
theorem freshPoliciesExact :
    revision.freshPolicies = [platformVetoV2] := by
  native_decide
theorem freshPoliciesValidate :
    ∀ policy ∈ revision.freshPolicies,
      PolicyValidation.check policy schema = .ok () := by
  intro policy membership
  have same : policy = platformVetoV2 := by
    simpa [freshPoliciesExact] using membership
  subst policy
  exact okOfIsOk _ (by native_decide)
theorem freshPoliciesCertified :
    ∀ policy ∈ revision.freshPolicies,
      Certificate (PolicyValidation.Snapshot.mk policy schema).proofObject := by
  intro policy membership
  exact (PolicyValidation.Snapshot.mk policy schema).certificate
    (freshPoliciesValidate policy membership)
theorem updatedPoliciesValidate : validate updatedPolicies schema = .ok () :=
  revision.validateAfter schema (okOfIsOk _ (by native_decide))
    freshPoliciesCertified
theorem baselinePoliciesValidate : validate baselinePolicies schema = .ok () :=
  okOfIsOk _ (by native_decide)
def validatedBase : PolicyValidation.ValidatedSet schema :=
  ⟨baselinePolicies, baselinePoliciesValidate⟩
def invalidSameId : Policy :=
  { projectPermit with
    condition := [{ kind := .when, body := .lit (.string "not-a-boolean") }] }
theorem invalidSameIdRejected :
    (PolicyValidation.incrementalValidate validatedBase [invalidSameId]).isOk = false := by
  native_decide
theorem incrementalMatchesCedar :
    PolicyValidation.incrementalValidate validatedBase updatedPolicies =
      validate updatedPolicies schema :=
  PolicyValidation.incrementalValidate_eq_validate validatedBase updatedPolicies
theorem incrementalAccepted :
    PolicyValidation.incrementalValidate validatedBase updatedPolicies = .ok () :=
  okOfIsOk _ (by native_decide)
def refreshed : Except ValidationError (PolicyValidation.ValidatedSet schema) :=
  revision.tryRefresh validatedBase rfl
theorem refreshedAccepted : refreshed.isOk = true := by
  unfold refreshed Revision.tryRefresh PolicyValidation.ValidatedSet.tryRefresh
  split
  · rfl
  · rename_i error equation
    have accepted :
        PolicyValidation.incrementalValidate validatedBase
          revision.afterPolicies = .ok () := by
      simpa [updatedPolicies] using incrementalAccepted
    rw [equation] at accepted
    cases accepted
theorem reorderedPoliciesValidate :
    validate reorderRevision.afterPolicies schema = .ok () := by
  apply reorderRevision.validateAfter schema
    (by simpa [reorderStartsFromUpdatedPolicies] using updatedPoliciesValidate)
  intro policy membership
  simp [reorderHasNoFreshPolicies] at membership
theorem patchedCertificate :
    Certificate (append baselineSnapshot.proofObject policyRevision) :=
  revision.patchedAuthorizationCertificate schema authorizedRequest entities
    baselineCertificate freshPoliciesCertified
theorem certificate : Certificate snapshot.proofObject := by
  change Certificate (revision.afterSnapshot schema authorizedRequest entities).proofObject
  rw [← revision.authorizationPatch_object]
  exact patchedCertificate
def schemaRevision : Patch AuthorizationKey AuthorizationValue :=
  Patch.set .schema schemaV2
def schemaChangeFootprint : Bool :=
  (changedDependencies schemaObligation schemaRevision == [.schema]) &&
  (changedDependencies policiesObligation schemaRevision == [.schema]) &&
  (changedDependencies requestObligation schemaRevision == [.schema]) &&
  (changedDependencies entitiesObligation schemaRevision == [.schema]) &&
  (changedDependencies PolicyValidation.policyObligation
    (PolicyValidation.replaceSchema schemaV2) == [.schema])
theorem schemaChangeFootprintExact : schemaChangeFootprint = true := by
  native_decide
def combinedSchemaRevision : Patch AuthorizationKey AuthorizationValue :=
  revision.authorizationPatchWithSchema schemaV2
def combinedSchemaFootprint : Bool :=
  (changedDependencies schemaObligation combinedSchemaRevision == [.schema]) &&
  (changedDependencies policiesObligation combinedSchemaRevision ==
    [.policies, .schema]) &&
  (changedDependencies requestObligation combinedSchemaRevision == [.schema]) &&
  (changedDependencies entitiesObligation combinedSchemaRevision == [.schema])
theorem combinedSchemaFootprintExact : combinedSchemaFootprint = true := by
  native_decide
theorem schemaV2Bundle : PolicyValidation.Bundle updatedPolicies schemaV2 :=
  PolicyValidation.Bundle.ofValidate updatedPolicies schemaV2
    (okOfIsOk _ (by native_decide))
theorem schemaV2PatchedCertificate :
    Certificate (append baselineSnapshot.proofObject combinedSchemaRevision) :=
  revision.patchedAuthorizationCertificateWithSchema schema schemaV2
    authorizedRequest entities
    (okOfIsOk _ (by native_decide)) schemaV2Bundle
    (okOfIsOk _ (by native_decide)) (okOfIsOk _ (by native_decide))
theorem schemaV2Certificate :
    Certificate (revision.afterSnapshot schemaV2 authorizedRequest entities).proofObject := by
  rw [← revision.authorizationPatchWithSchema_object]
  exact schemaV2PatchedCertificate
theorem auditCertificate :
    Certificate (append snapshot.proofObject auditRevision.authorizationPatch) := by
  apply closePending snapshot.proofObject auditRevision.authorizationPatch certificate
  intro obligation membership
  have noPending :
      pending snapshot.proofObject auditRevision.authorizationPatch = [] := by
    simpa only [List.isEmpty_iff] using auditRevisionHasNoPendingProofs
  simp [noPending] at membership
example : Cedar.Thm.AllEvaluateToBool snapshot.policies
    snapshot.request snapshot.entities :=
  certifiedAuthorizationSound snapshot certificate

end CedarPooSpec.AttestedDataAccessExample
