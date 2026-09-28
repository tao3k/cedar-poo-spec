import CedarPooSpec.Revision
import CedarPooSpec.PolicyValidation

/-!
An authorization model for hospital pseudonymization. The cryptographic
operations, IV allocation, key release, and durable audit are Host effects;
the finite Cedar model authorizes requests using facts established by them.
-/

namespace CedarPooSpec.PseudonymizationExample

open Cedar.Spec Cedar.Validation Cedar.Data
open CedarPooSpec.PolicyModules
open LeanPoo.Proof

def actorType : EntityType := ⟨"Actor", []⟩
def datasetType : EntityType := ⟨"Dataset", []⟩
def actionType : EntityType := ⟨"Action", []⟩
def tokenize : EntityUID := ⟨actionType, "tokenize"⟩
def join : EntityUID := ⟨actionType, "join"⟩
def reidentify : EntityUID := ⟨actionType, "reidentify"⟩

def actorEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.make [
    ("tenant", .required .string), ("kind", .required .string)], none⟩
def datasetEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.make [
    ("tenant", .required .string), ("mode", .required .string),
    ("scope", .required .string), ("keyDomain", .required .string)], none⟩
def contextType : RecordType := Map.make [
  ("targetDataset", .required (.entity datasetType)),
  ("ownerApproved", .required (.bool .anyBool)),
  ("keyAuthorized", .required (.bool .anyBool)),
  ("joinApproved", .required (.bool .anyBool)),
  ("reidentifyApproved", .required (.bool .anyBool)),
  ("auditReady", .required (.bool .anyBool)),
  ("ivUnique", .required (.bool .anyBool))]
def actionEntry : ActionSchemaEntry :=
  ⟨Set.make [actorType], Set.make [datasetType], Set.empty, contextType⟩
def schema : Schema :=
  ⟨Map.make [(actorType, actorEntry), (datasetType, datasetEntry)],
   Map.make [(tokenize, actionEntry), (join, actionEntry),
     (reidentify, actionEntry)]⟩

def agent : EntityUID := ⟨actorType, "analytics-agent"⟩
def steward : EntityUID := ⟨actorType, "clinical-steward"⟩
def operator : EntityUID := ⟨actorType, "data-operator"⟩
def hospital : EntityUID := ⟨datasetType, "hospital-patients"⟩
def research : EntityUID := ⟨datasetType, "research-patients"⟩
def randomized : EntityUID := ⟨datasetType, "randomized-records"⟩
def oneWay : EntityUID := ⟨datasetType, "one-way-records"⟩
def otherKey : EntityUID := ⟨datasetType, "other-key-records"⟩
def otherTenant : EntityUID := ⟨datasetType, "other-tenant-records"⟩
def actorData (kind : String) : EntityData :=
  { attrs := Map.make [("tenant", .prim (.string "hospital-a")),
      ("kind", .prim (.string kind))], ancestors := Set.empty, tags := Map.empty }
def datasetData (mode scope : String) (keyDomain : String := "key-a")
    (tenant : String := "hospital-a") : EntityData :=
  { attrs := Map.make [("tenant", .prim (.string tenant)),
      ("mode", .prim (.string mode)), ("scope", .prim (.string scope)),
      ("keyDomain", .prim (.string keyDomain))],
    ancestors := Set.empty, tags := Map.empty }
def entities : Entities := Map.make [
  (agent, actorData "agent"), (steward, actorData "steward"),
  (operator, actorData "operator"),
  (hospital, datasetData "aes-siv" "hospital-a"),
  (research, datasetData "aes-siv" "study-1"),
  (randomized, datasetData "aes-gcm" "hospital-a"),
  (oneWay, datasetData "hmac-sha256" "hospital-a"),
  (otherKey, datasetData "aes-siv" "hospital-a" "key-b"),
  (otherTenant, datasetData "aes-siv" "hospital-a" "key-a" "hospital-b"),
  (tokenize, actionSchemaEntryToEntityData actionEntry),
  (join, actionSchemaEntryToEntityData actionEntry),
  (reidentify, actionSchemaEntryToEntityData actionEntry)]

def attr (source : Var) (name : String) : Expr := .getAttr (.var source) name
def fact (name : String) : Expr := attr .context name
def resource (name : String) : Expr := attr .resource name
def eqString (left : Expr) (right : String) : Expr :=
  .binaryApp .eq left (.lit (.string right))
def equal (left right : Expr) : Expr := .binaryApp .eq left right
def not (body : Expr) : Expr := .unaryApp .not body
def target (name : String) : Expr := .getAttr (fact "targetDataset") name
def scopeBound : Expr := equal (target "scope") (resource "scope")
def keyBound : Expr := equal (target "keyDomain") (resource "keyDomain")
def modeBound : Expr := equal (target "mode") (resource "mode")
def tenantBound : Expr := equal (attr .principal "tenant") (resource "tenant")
def targetTenantBound : Expr := equal (attr .principal "tenant") (target "tenant")
def selfBound : Expr := equal (fact "targetDataset") (.var .resource)
def modeIs (mode : String) : Expr := eqString (resource "mode") mode
def common (mode : String) : Expr :=
  .and (modeIs mode) (.and modeBound
    (.and scopeBound (.and keyBound (fact "keyAuthorized"))))

def policy (id : String) (effect : Effect) (action : EntityUID)
    (body : Expr) : Policy :=
  { id := id, effect := effect,
    principalScope := .principalScope .any,
    actionScope := .actionScope (.eq action),
    resourceScope := .resourceScope .any,
    condition := [{ kind := .when, body := body }] }

/-- This object states which operation a cryptographic profile can support.
    It never claims that Cedar performs the cryptographic operation. -/
inductive CryptoMode where
  | aesSiv | aesGcm | hmacSha256
  deriving DecidableEq

def CryptoMode.label : CryptoMode → String
  | .aesSiv => "aes-siv"
  | .aesGcm => "aes-gcm"
  | .hmacSha256 => "hmac-sha256"

def CryptoMode.reversible : CryptoMode → Bool
  | .aesSiv | .aesGcm => true
  | .hmacSha256 => false

def CryptoMode.linkable : CryptoMode → Bool
  | .aesSiv | .hmacSha256 => true
  | .aesGcm => false

structure CryptoProfile where
  name : String
  mode : CryptoMode

def CryptoProfile.module (profile : CryptoProfile) : Module := Id.run do
  let mode := profile.mode.label
  let basis := common mode
  let tokenizeBody :=
    if profile.mode == .aesGcm then
      .and basis (.and selfBound (fact "ivUnique"))
    else .and basis selfBound
  let mut edits : List Edit :=
    [.extend (policy "tokenize" .permit tokenize tokenizeBody)]
  if profile.mode.linkable then
    edits := edits ++ [.extend (policy "join" .permit join
      (.and basis (.and targetTenantBound (fact "joinApproved"))))]
  else
    edits := edits ++ [.extend (policy "no-deterministic-join" .forbid join
      (modeIs mode))]
  if profile.mode.reversible then
    edits := edits ++ [.extend (policy "reidentify" .permit reidentify
      (.and basis (.and selfBound
        (.and (eqString (attr .principal "kind") "steward")
          (.and (fact "reidentifyApproved") (fact "auditReady"))))))]
  else
    edits := edits ++ [.extend (policy "irreversible-token" .forbid
      reidentify (modeIs mode))]
  return { name := profile.name, parentOrders := [["Base"]], edits }

def siv : CryptoProfile := ⟨"AesSiv", .aesSiv⟩
def gcm : CryptoProfile := ⟨"AesGcm", .aesGcm⟩
def hmac : CryptoProfile := ⟨"Hmac", .hmacSha256⟩

def legacyReveal : Policy :=
  policy "legacy-reidentify" .permit reidentify (.lit (.bool true))
def base : Module := { name := "Base", edits := [.extend legacyReveal] }
def owner : Module :=
  { name := "DataOwner", parentOrders := [["Base"]],
    edits := [.extend (policy "owner-approval" .forbid tokenize
      (not (fact "ownerApproved"))),
      .extend (policy "owner-join-approval" .forbid join
        (not (fact "ownerApproved"))),
      .extend (policy "owner-reidentify-approval" .forbid reidentify
        (not (fact "ownerApproved")))] }
def privacy : Module :=
  { name := "Privacy", parentOrders := [["Base"]],
    edits := [.extend (policy "tenant-token-boundary" .forbid tokenize
      (not tenantBound)),
      .extend (policy "tenant-join-boundary" .forbid join
        (not tenantBound)),
      .extend (policy "tenant-reidentify-boundary" .forbid reidentify
        (not tenantBound))] }
def agentBoundary : Module :=
  { name := "AgentBoundary", parentOrders := [["Base"]],
    edits := [.extend (policy "agent-cannot-reidentify" .forbid reidentify
      (eqString (attr .principal "kind") "agent"))] }

/-- Each view inherits the same owner, privacy, and agent boundaries. Changing
    the profile changes only the cryptographic capability branch. -/
structure GovernanceView where
  name : String
  profile : CryptoProfile

def GovernanceView.module (view : GovernanceView) : Module :=
  { name := view.name,
    parentOrders := [[view.profile.name, "DataOwner", "Privacy", "AgentBoundary"]],
    edits := [.remove legacyReveal.id] }
def hospitalView : GovernanceView := ⟨"HospitalSiv", siv⟩
def randomizedView : GovernanceView := ⟨"RandomizedGcm", gcm⟩
def oneWayView : GovernanceView := ⟨"OneWayHmac", hmac⟩
def views : List GovernanceView := [hospitalView, randomizedView, oneWayView]

def incident : Module :=
  { name := "AgentIncident", parentOrders := [[hospitalView.name]],
    edits := [.extend (policy "agent-join-suspended" .forbid join
      (eqString (attr .principal "kind") "agent"))] }
def model : Model :=
  { modules := [base, siv.module, gcm.module, hmac.module,
      owner, privacy, agentBoundary] ++ views.map GovernanceView.module ++ [incident] }

structure Facts where
  targetDataset : EntityUID := hospital
  ownerApproved : Bool := true
  keyAuthorized : Bool := true
  joinApproved : Bool := true
  reidentifyApproved : Bool := false
  auditReady : Bool := false
  ivUnique : Bool := true

def request (who action dataset : EntityUID) (facts : Facts) : Request :=
  ⟨who, action, dataset, Map.make [
    ("targetDataset", .prim (.entityUID facts.targetDataset)),
    ("ownerApproved", .prim (.bool facts.ownerApproved)),
    ("keyAuthorized", .prim (.bool facts.keyAuthorized)),
    ("joinApproved", .prim (.bool facts.joinApproved)),
    ("reidentifyApproved", .prim (.bool facts.reidentifyApproved)),
    ("auditReady", .prim (.bool facts.auditReady)),
    ("ivUnique", .prim (.bool facts.ivUnique))]⟩

def reveal : Facts := { reidentifyApproved := true, auditReady := true }
def cases : List (String × String × Request × Decision) := [
  ("pre-governance-broad-reidentify", "AesSiv",
    request steward reidentify hospital {}, .allow),
  ("hospital-tokenize", "HospitalSiv", request agent tokenize hospital {}, .allow),
  ("hospital-join", "HospitalSiv", request agent join hospital {}, .allow),
  ("research-local-join", "HospitalSiv", request agent join research
    { targetDataset := research }, .allow),
  ("cross-study-join", "HospitalSiv", request agent join research {}, .deny),
  ("wrong-key-domain", "HospitalSiv", request agent join hospital
    { targetDataset := otherKey }, .deny),
  ("incompatible-token-mode", "HospitalSiv", request agent join hospital
    { targetDataset := randomized }, .deny),
  ("other-tenant-join", "HospitalSiv", request agent join hospital
    { targetDataset := otherTenant }, .deny),
  ("tokenize-other-dataset", "HospitalSiv", request agent tokenize hospital
    { targetDataset := otherKey }, .deny),
  ("owner-rejected", "HospitalSiv", request agent join hospital
    { ownerApproved := false }, .deny),
  ("agent-reidentify", "HospitalSiv", request agent reidentify hospital reveal, .deny),
  ("operator-reidentify", "HospitalSiv", request operator reidentify hospital reveal, .deny),
  ("reidentify-other-dataset", "HospitalSiv", request steward reidentify hospital
    { reveal with targetDataset := otherKey }, .deny),
  ("steward-reidentify", "HospitalSiv", request steward reidentify hospital reveal, .allow),
  ("no-reidentify-approval", "HospitalSiv", request steward reidentify hospital
    { reveal with reidentifyApproved := false }, .deny),
  ("audit-unavailable", "HospitalSiv", request steward reidentify hospital
    { reveal with auditReady := false }, .deny),
  ("gcm-unique-iv", "RandomizedGcm", request agent tokenize randomized
    { targetDataset := randomized }, .allow),
  ("gcm-reused-iv", "RandomizedGcm", request agent tokenize randomized
    { targetDataset := randomized, ivUnique := false }, .deny),
  ("gcm-no-deterministic-join", "RandomizedGcm", request agent join randomized
    { targetDataset := randomized }, .deny),
  ("gcm-steward-reidentify", "RandomizedGcm", request steward reidentify randomized
    { reveal with targetDataset := randomized }, .allow),
  ("hmac-local-join", "OneWayHmac", request agent join oneWay
    { targetDataset := oneWay }, .allow),
  ("hmac-no-reidentification", "OneWayHmac", request steward reidentify oneWay
    { reveal with targetDataset := oneWay }, .deny),
  ("incident-agent-join", "AgentIncident", request agent join hospital {}, .deny),
  ("incident-steward-join", "AgentIncident", request steward join hospital {}, .allow)]

def scenarioConforms : Bool := cases.all fun (_, root, req, expected) =>
  match model.compile root with
  | .error _ => false
  | .ok policies =>
    (validate policies schema).isOk &&
    let response := isAuthorized req entities policies
    response.decision == expected && response.erroringPolicies.isEmpty
theorem scenarioConformsFully : scenarioConforms = true := by native_decide

theorem caseNamesUnique : (cases.map (fun (name, _, _, _) => name)).Nodup := by
  native_decide

def composedViewsShareRemoval : Bool :=
  views.all (fun view => view.module.edits == [.remove legacyReveal.id])
theorem composedViewsShareRemovalFully : composedViewsShareRemoval = true := by
  native_decide

def compositionIsLocal : Bool :=
  let sivAffected := invalidatedNodes model.graph [siv.name]
  let incidentAffected := invalidatedNodes model.graph [incident.name]
  sivAffected.contains hospitalView.name &&
  sivAffected.contains incident.name &&
  !sivAffected.contains randomizedView.name &&
  !sivAffected.contains oneWayView.name &&
  incidentAffected == [incident.name]
theorem compositionIsLocalFully : compositionIsLocal = true := by native_decide

def incidentOnlyAddsAgentVeto : Bool :=
  match model.compile hospitalView.name, model.compile incident.name with
  | .ok baseline, .ok suspended =>
    suspended.length == baseline.length + 1 &&
    suspended.filter (fun p => p.id != "agent-join-suspended") == baseline
  | _, _ => false
theorem incidentOnlyAddsAgentVetoFully : incidentOnlyAddsAgentVeto = true := by
  native_decide

end CedarPooSpec.PseudonymizationExample
