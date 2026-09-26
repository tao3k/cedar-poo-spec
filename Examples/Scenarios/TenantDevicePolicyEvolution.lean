import CedarPooSpec.Slicing
import CedarPooSpec.PolicyModules

/-!
A stock-Cedar authorization scenario. A principal may read a document only
inside its tenant, and an authority-projected device fact must be true.
The fact is request context; this example adds no Cedar evaluator extension.
-/

namespace CedarPooSpec.TenantDeviceAuthorizationExample

open Cedar.Spec Cedar.Validation Cedar.Data
open CedarPooSpec.Soundness
open LeanPoo.Proof

def userType : EntityType := ⟨"User", []⟩
def documentType : EntityType := ⟨"Document", []⟩
def actionType : EntityType := ⟨"Action", []⟩
def readAction : EntityUID := ⟨actionType, "read"⟩

def tenantAttrs : RecordType :=
  Map.make [("tenant", .required .string)]
def entityEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, tenantAttrs, none⟩
def contextType : RecordType :=
  Map.make [("deviceTrusted", .required (.bool .anyBool))]
def actionEntry : ActionSchemaEntry :=
  ⟨Set.make [userType], Set.make [documentType], Set.empty, contextType⟩
def schema : Schema :=
  ⟨Map.make [(userType, entityEntry), (documentType, entityEntry)],
   Map.make [(readAction, actionEntry)]⟩

def alice : EntityUID := ⟨userType, "alice"⟩
def documentA : EntityUID := ⟨documentType, "a"⟩
def documentB : EntityUID := ⟨documentType, "b"⟩

def tenantEntity (tenant : String) : EntityData :=
  { attrs := Map.make [("tenant", .prim (.string tenant))],
    ancestors := Set.empty, tags := Map.empty }
def entities : Entities :=
  Map.make [(alice, tenantEntity "a"),
    (documentA, tenantEntity "a"),
    (documentB, tenantEntity "b"),
    (readAction, actionSchemaEntryToEntityData actionEntry)]

def tenantMatches : Expr :=
  .binaryApp .eq
    (.getAttr (.var .principal) "tenant")
    (.getAttr (.var .resource) "tenant")
def trustedDevice : Expr := .getAttr (.var .context) "deviceTrusted"

def policy : Policy :=
  { id := "trusted-tenant-read",
    effect := .permit,
    principalScope := .principalScope .any,
    actionScope := .actionScope (.eq readAction),
    resourceScope := .resourceScope .any,
    condition := [{ kind := .when, body := .and tenantMatches trustedDevice }] }
def policies : Policies := [policy]

def readRequest (document : EntityUID) (trusted : Bool) : Request :=
  ⟨alice, readAction, document,
    Map.make [("deviceTrusted", .prim (.bool trusted))]⟩

def allowedRequest : Request := readRequest documentA true
def crossTenantRequest : Request := readRequest documentB true
def untrustedRequest : Request := readRequest documentA false

def singlePolicyConforms : Bool :=
  (isAuthorized allowedRequest entities policies).decision == .allow &&
  (isAuthorized crossTenantRequest entities policies).decision == .deny &&
  (isAuthorized untrustedRequest entities policies).decision == .deny &&
  entities.size == 4 &&
  (entities.sliceAtLevel allowedRequest 1).size == 3
theorem singlePolicyConformsFully : singlePolicyConforms = true := by native_decide

private theorem okOfIsOk {ε : Type} (result : Except ε Unit)
    (h : result.isOk = true) : result = .ok () := by
  cases result with
  | ok value => cases value; rfl
  | error _ => cases h

def snapshot : AuthorizationSnapshot :=
  ⟨policies, schema, allowedRequest, entities⟩
theorem authorizationCertificate : Certificate snapshot.proofObject :=
  snapshot.certificateOfChecks (by native_decide)

def sliced : CedarPooSpec.Slicing.Snapshot := ⟨snapshot, 1⟩
theorem sliceCertificate : Certificate sliced.proofObject :=
  sliced.certificate authorizationCertificate
    (okOfIsOk _ (by native_decide))
theorem closedCertificate : Certificate sliced.closedProofObject :=
  sliced.closedCertificate sliceCertificate (by native_decide)

example : isAuthorized allowedRequest entities policies =
    isAuthorized allowedRequest
      (entities.sliceAtLevel allowedRequest 1) policies :=
  CedarPooSpec.Slicing.certifiedSlice sliced sliceCertificate

example : ∀ p ∈ policies,
    evaluate p.toExpr allowedRequest entities ≠ .error .entityDoesNotExist :=
  CedarPooSpec.Slicing.certifiedNoMissingEntity sliced closedCertificate

/-!
Policy evolution is the POO use case. A legacy broad permit coexists with a
tenant permit. Tightening the tenant permit alone cannot revoke the legacy
permit: Cedar combines all applicable permits. A descendant adds a forbid for
untrusted devices, then removes the legacy permit. C4 determines which module
edits are inherited; Cedar alone computes authorization decisions.
-/

open CedarPooSpec.PolicyModules

def tenantPermit : Policy :=
  { id := "tenant-read", effect := .permit,
    principalScope := .principalScope .any,
    actionScope := .actionScope (.eq readAction),
    resourceScope := .resourceScope .any,
    condition := [{ kind := .when, body := tenantMatches }] }
def strictTenantPermit : Policy :=
  { policy with id := "tenant-read" }
def legacyPermit : Policy :=
  { id := "legacy-read", effect := .permit,
    principalScope := .principalScope .any,
    actionScope := .actionScope (.eq readAction),
    resourceScope := .resourceScope .any, condition := [] }
def untrustedForbid : Policy :=
  { id := "untrusted-device", effect := .forbid,
    principalScope := .principalScope .any,
    actionScope := .actionScope (.eq readAction),
    resourceScope := .resourceScope .any,
    condition := [{ kind := .when, body := .unaryApp .not trustedDevice }] }

def baseModule : Module :=
  { name := "Base", edits := [.extend tenantPermit, .extend legacyPermit] }
def overlayModule : Module :=
  { name := "Overlay", parentOrders := [["Base"]],
    edits := [.overlay strictTenantPermit] }
def extendModule : Module :=
  { name := "Extend", parentOrders := [["Overlay"]],
    edits := [.extend untrustedForbid] }
def removeModule : Module :=
  { name := "Remove", parentOrders := [["Extend"]],
    edits := [.remove legacyPermit.id] }

def model : Model :=
  { modules := [baseModule, overlayModule, extendModule, removeModule] }

def finalPolicies : Policies :=
  (model.compile "Remove").toOption.get (by native_decide)

def expectedDecisions : List (String × Request × Decision) :=
  [("Base", allowedRequest, .allow),
   ("Base", crossTenantRequest, .allow),
   ("Base", untrustedRequest, .allow),
   ("Overlay", allowedRequest, .allow),
   ("Overlay", crossTenantRequest, .allow),
   ("Overlay", untrustedRequest, .allow),
   ("Extend", allowedRequest, .allow),
   ("Extend", crossTenantRequest, .allow),
   ("Extend", untrustedRequest, .deny),
   ("Remove", allowedRequest, .allow),
   ("Remove", crossTenantRequest, .deny),
   ("Remove", untrustedRequest, .deny)]

def scenarioConforms : Bool :=
  (LeanPoo.C4.linearize model.graph "Remove").toOption ==
      some ["Remove", "Extend", "Overlay", "Base"] &&
  expectedDecisions.all fun (root, request, expected) =>
    match model.compile root with
    | .error _ => false
    | .ok policies =>
      (validate policies schema).isOk &&
      (isAuthorized request entities policies).decision == expected &&
      (isAuthorized request entities policies).erroringPolicies.isEmpty

theorem scenarioConformsFully : scenarioConforms = true := by native_decide

-- Issue-inspired skip-on-error case: a missing context attribute makes a
-- forbid error. Cedar excludes that forbid, so the broad permit can allow.
-- The validated module path above avoids accepting this policy set.
def missingDeviceFact : Expr :=
  .getAttr (.var .context) "missingDeviceFact"
def brokenForbid : Policy :=
  { id := "broken-forbid", effect := .forbid,
    principalScope := .principalScope .any,
    actionScope := .actionScope (.eq readAction),
    resourceScope := .resourceScope .any,
    condition := [{ kind := .when, body := missingDeviceFact }] }
def brokenPolicies : Policies := [legacyPermit, brokenForbid]
def brokenPolicyDetected : Bool :=
  !(validate brokenPolicies schema).isOk &&
  (isAuthorized untrustedRequest entities brokenPolicies).decision == .allow &&
  (isAuthorized untrustedRequest entities brokenPolicies).erroringPolicies.contains
    brokenForbid.id
theorem brokenPolicyDetectedFully : brokenPolicyDetected = true := by native_decide

-- Authoring mistakes and ambiguous sibling edits fail before Cedar evaluation.
def duplicateModule : Module :=
  { name := "Duplicate", parentOrders := [["Base"]],
    edits := [.extend legacyPermit] }
def duplicateModel : Model :=
  { modules := [baseModule, duplicateModule] }

def absentPolicy : Policy := { policy with id := "absent" }
def missingModule : Module :=
  { name := "Missing", parentOrders := [["Base"]],
    edits := [.overlay absentPolicy] }
def missingModel : Model :=
  { modules := [baseModule, missingModule] }

def absentRemoval : Module :=
  { name := "AbsentRemoval", parentOrders := [["Base"]],
    edits := [.remove "absent"] }

def siblingModel : Model :=
  { modules := [baseModule,
    { name := "Left", parentOrders := [["Base"]],
      edits := [.overlay strictTenantPermit] },
    { name := "Right", parentOrders := [["Base"]],
      edits := [.overlay strictTenantPermit] },
    { name := "Diamond", parentOrders := [["Left", "Right"]] }] }

def cyclicModel : Model :=
  { modules := [
    { name := "CycleA", parentOrders := [["CycleB"]] },
    { name := "CycleB", parentOrders := [["CycleA"]] }] }

def authoringErrorsDetected : Bool :=
  (match duplicateModel.compile "Duplicate" with
   | .error (.policyAlreadyExists "legacy-read") => true
   | _ => false) &&
  (match missingModel.compile "Missing" with
   | .error (.missingPolicy "absent") => true
   | _ => false) &&
  (match ({ modules := [baseModule, absentRemoval] } : Model).compile "AbsentRemoval" with
   | .error (.missingPolicy "absent") => true
   | _ => false) &&
  (match siblingModel.compile "Diamond" with
   | .error (.competingEdits "tenant-read" _ _) => true
   | _ => false) &&
  (match cyclicModel.compile "CycleA" with
   | .error (.c4 _) => true
   | _ => false)
theorem authoringErrorsDetectedFully : authoringErrorsDetected = true := by native_decide

def evolvedSnapshot : AuthorizationSnapshot :=
  ⟨finalPolicies, schema, allowedRequest, entities⟩
theorem evolvedCertificate : Certificate evolvedSnapshot.proofObject :=
  evolvedSnapshot.certificateOfChecks (by native_decide)

def policyRevision : Patch AuthorizationKey AuthorizationValue :=
  Patch.set .policies finalPolicies
def policyRevisionFootprint : Bool :=
  (match changedDependencies policiesObligation policyRevision with
   | [.policies] => true
   | _ => false) &&
  (changedDependencies schemaObligation policyRevision).isEmpty &&
  (changedDependencies requestObligation policyRevision).isEmpty &&
  (changedDependencies entitiesObligation policyRevision).isEmpty
theorem policyRevisionFootprintExact : policyRevisionFootprint = true := by
  native_decide

-- The final composed policy set is checked by Cedar's validator and theorem.
example : Cedar.Thm.AllEvaluateToBool evolvedSnapshot.policies
    evolvedSnapshot.request evolvedSnapshot.entities :=
  certifiedAuthorizationSound evolvedSnapshot evolvedCertificate

end CedarPooSpec.TenantDeviceAuthorizationExample
