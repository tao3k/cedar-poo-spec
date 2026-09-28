import CedarPooSpec.Revision
import CedarPooSpec.PolicyValidation
import CedarPooSpec.Governance.Veto

/-!
An authorization model for hospital pseudonymization. The cryptographic
operations, IV allocation, key release, and durable audit are Host effects;
the finite Cedar model authorizes requests using facts established by them.
-/

namespace CedarPooSpec.PseudonymizationExample

open Cedar.Spec Cedar.Validation Cedar.Data
open CedarPooSpec.PolicyModules
open CedarPooSpec.Governance
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
    ("scope", .required .string), ("keyDomain", .required .string),
    ("tokenKeyVersion", .required .string),
    ("transformVersion", .required .string),
    ("wrappingVersion", .required .string)], none⟩
def contextType : RecordType := Map.make [
  ("targetDataset", .required (.entity datasetType)),
  ("ownerApproved", .required (.bool .anyBool)),
  ("keyAuthorized", .required (.bool .anyBool)),
  ("requestedKeyVersion", .required .string),
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
def ingest : EntityUID := ⟨actorType, "trusted-ingestion"⟩
def hospital : EntityUID := ⟨datasetType, "hospital-patients"⟩
def research : EntityUID := ⟨datasetType, "research-patients"⟩
def randomized : EntityUID := ⟨datasetType, "randomized-records"⟩
def oneWay : EntityUID := ⟨datasetType, "one-way-records"⟩
def otherKey : EntityUID := ⟨datasetType, "other-key-records"⟩
def otherTenant : EntityUID := ⟨datasetType, "other-tenant-records"⟩
def rewrapped : EntityUID := ⟨datasetType, "rewrapped-records"⟩
def rotatedTokenKey : EntityUID := ⟨datasetType, "rotated-token-key-records"⟩
def revisedTransform : EntityUID := ⟨datasetType, "revised-transform-records"⟩
def actorData (kind : String) : EntityData :=
  { attrs := Map.make [("tenant", .prim (.string "hospital-a")),
      ("kind", .prim (.string kind))], ancestors := Set.empty, tags := Map.empty }

/-- Public metadata needed to compare token compatibility. A wrapping-key
    version is recorded for recovery, but does not identify token key bytes. -/
structure TokenLineage where
  tenant : String := "hospital-a"
  keyDomain : String := "key-a"
  tokenKeyVersion : String := "dek-v1"
  transformVersion : String := "patient-id-v1"
  wrappingVersion : String := "kek-v1"

def datasetData (mode scope : String) (lineage : TokenLineage := {}) : EntityData :=
  { attrs := Map.make [("tenant", .prim (.string lineage.tenant)),
      ("mode", .prim (.string mode)), ("scope", .prim (.string scope)),
      ("keyDomain", .prim (.string lineage.keyDomain)),
      ("tokenKeyVersion", .prim (.string lineage.tokenKeyVersion)),
      ("transformVersion", .prim (.string lineage.transformVersion)),
      ("wrappingVersion", .prim (.string lineage.wrappingVersion))],
    ancestors := Set.empty, tags := Map.empty }

/-- One declared dataset is the source of both Cedar entity data and catalog
    admission checks. The Host must verify that these declarations match the
    actual transformation and key inventory before publication. -/
structure DatasetObject where
  uid : EntityUID
  mode : String
  scope : String
  lineage : TokenLineage := {}

def DatasetObject.entity (object : DatasetObject) : EntityUID × EntityData :=
  (object.uid, datasetData object.mode object.scope object.lineage)

def datasets : List DatasetObject := [
  ⟨hospital, "aes-siv", "hospital-a", {}⟩,
  ⟨research, "aes-siv", "study-1", {}⟩,
  ⟨randomized, "aes-gcm", "hospital-a", {}⟩,
  ⟨oneWay, "hmac-sha256", "hospital-a", {}⟩,
  ⟨otherKey, "aes-siv", "hospital-a", { keyDomain := "key-b" }⟩,
  ⟨otherTenant, "aes-siv", "hospital-a", { tenant := "hospital-b" }⟩,
  ⟨rewrapped, "aes-siv", "hospital-a", { wrappingVersion := "kek-v2" }⟩,
  ⟨rotatedTokenKey, "aes-siv", "hospital-a", { tokenKeyVersion := "dek-v2" }⟩,
  ⟨revisedTransform, "aes-siv", "hospital-a",
    { transformVersion := "patient-id-v2" }⟩]

/-- The Google HMAC transformation has no context tweak. Separate scopes
    therefore need separate HMAC key material to prevent passive linkage. -/
def hmacKeyReuseAcrossScopes (left right : DatasetObject) : Bool :=
  left.mode == "hmac-sha256" && right.mode == "hmac-sha256" &&
  left.scope != right.scope &&
  left.lineage.keyDomain == right.lineage.keyDomain &&
  left.lineage.tokenKeyVersion == right.lineage.tokenKeyVersion &&
  left.lineage.transformVersion == right.lineage.transformVersion

def hmacCatalogSeparated (catalog : List DatasetObject) : Bool :=
  catalog.all fun left =>
    catalog.all fun right => !hmacKeyReuseAcrossScopes left right

def unsafeHmacStudy : DatasetObject :=
  ⟨⟨datasetType, "unsafe-hmac-study"⟩, "hmac-sha256", "study-1", {}⟩
def isolatedHmacStudy : DatasetObject :=
  ⟨⟨datasetType, "isolated-hmac-study"⟩, "hmac-sha256", "study-1",
    { keyDomain := "study-1-hmac-key" }⟩

theorem publishedHmacCatalogSeparated : hmacCatalogSeparated datasets = true := by
  native_decide
theorem unsafeHmacStudyRejected :
    hmacCatalogSeparated (unsafeHmacStudy :: datasets) = false := by
  native_decide
theorem isolatedHmacStudyAccepted :
    hmacCatalogSeparated (isolatedHmacStudy :: datasets) = true := by
  native_decide

def entities : Entities := Map.make ([
  (agent, actorData "agent"), (steward, actorData "steward"),
  (operator, actorData "operator"),
  (ingest, actorData "ingest")] ++
  datasets.map DatasetObject.entity ++ [
  (tokenize, actionSchemaEntryToEntityData actionEntry),
  (join, actionSchemaEntryToEntityData actionEntry),
  (reidentify, actionSchemaEntryToEntityData actionEntry)])

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
def tokenKeyBound : Expr :=
  equal (target "tokenKeyVersion") (resource "tokenKeyVersion")
def transformBound : Expr :=
  equal (target "transformVersion") (resource "transformVersion")
def modeBound : Expr := equal (target "mode") (resource "mode")
def tenantBound : Expr := equal (attr .principal "tenant") (resource "tenant")
def targetTenantBound : Expr := equal (attr .principal "tenant") (target "tenant")
def selfBound : Expr := equal (fact "targetDataset") (.var .resource)
def modeIs (mode : String) : Expr := eqString (resource "mode") mode
def compatible (mode : String) : Expr :=
  .and (modeIs mode) (.and modeBound
    (.and scopeBound (.and keyBound
      (.and tokenKeyBound transformBound))))
def keyed (mode : String) : Expr :=
  .and (compatible mode) (.and (fact "keyAuthorized")
    (equal (fact "requestedKeyVersion") (resource "tokenKeyVersion")))

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
  let basis := compatible mode
  let withKey := keyed mode
  let tokenizeBody :=
    if profile.mode == .aesGcm then
      .and withKey (.and selfBound
        (.and (eqString (attr .principal "kind") "ingest") (fact "ivUnique")))
    else .and withKey (.and selfBound
      (eqString (attr .principal "kind") "ingest"))
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
      (.and withKey (.and selfBound
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
def veto (id : String) (action : EntityUID) (denyWhen : Expr) : Veto :=
  { policyId := id, actionScope := .actionScope (.eq action), denyWhen }

def owner : Module :=
  Veto.moduleMany "DataOwner" "Base" .introduce [
    veto "owner-approval" tokenize (not (fact "ownerApproved")),
    veto "owner-join-approval" join (not (fact "ownerApproved")),
    veto "owner-reidentify-approval" reidentify (not (fact "ownerApproved"))]
def privacy : Module :=
  Veto.moduleMany "Privacy" "Base" .introduce [
    veto "tenant-token-boundary" tokenize (not tenantBound),
    veto "tenant-join-boundary" join (not tenantBound),
    veto "tenant-reidentify-boundary" reidentify (not tenantBound)]
def agentBoundary : Module :=
  (veto "agent-cannot-reidentify" reidentify
    (eqString (attr .principal "kind") "agent")).module
      "AgentBoundary" "Base" .introduce

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
  requestedKeyVersion : String := "dek-v1"
  joinApproved : Bool := true
  reidentifyApproved : Bool := false
  auditReady : Bool := false
  ivUnique : Bool := true

def request (who action dataset : EntityUID) (facts : Facts) : Request :=
  ⟨who, action, dataset, Map.make [
    ("targetDataset", .prim (.entityUID facts.targetDataset)),
    ("ownerApproved", .prim (.bool facts.ownerApproved)),
    ("keyAuthorized", .prim (.bool facts.keyAuthorized)),
    ("requestedKeyVersion", .prim (.string facts.requestedKeyVersion)),
    ("joinApproved", .prim (.bool facts.joinApproved)),
    ("reidentifyApproved", .prim (.bool facts.reidentifyApproved)),
    ("auditReady", .prim (.bool facts.auditReady)),
    ("ivUnique", .prim (.bool facts.ivUnique))]⟩

def reveal : Facts := { reidentifyApproved := true, auditReady := true }
def cases : List (String × String × Request × Decision) := [
  ("pre-governance-broad-reidentify", "AesSiv",
    request steward reidentify hospital {}, .allow),
  ("hospital-tokenize", "HospitalSiv", request ingest tokenize hospital {}, .allow),
  ("tokenize-without-key", "HospitalSiv", request ingest tokenize hospital
    { keyAuthorized := false }, .deny),
  ("agent-tokenization-oracle", "HospitalSiv",
    request agent tokenize hospital {}, .deny),
  ("hospital-join", "HospitalSiv", request agent join hospital {}, .allow),
  ("join-without-key-release", "HospitalSiv", request agent join hospital
    { keyAuthorized := false }, .allow),
  ("research-local-join", "HospitalSiv", request agent join research
    { targetDataset := research }, .allow),
  ("cross-study-join", "HospitalSiv", request agent join research {}, .deny),
  ("wrong-key-domain", "HospitalSiv", request agent join hospital
    { targetDataset := otherKey }, .deny),
  ("rewrapped-same-token-key", "HospitalSiv", request agent join hospital
    { targetDataset := rewrapped }, .allow),
  ("rotated-token-key", "HospitalSiv", request agent join hospital
    { targetDataset := rotatedTokenKey }, .deny),
  ("revised-transform", "HospitalSiv", request agent join hospital
    { targetDataset := revisedTransform }, .deny),
  ("incompatible-token-mode", "HospitalSiv", request agent join hospital
    { targetDataset := randomized }, .deny),
  ("other-tenant-join", "HospitalSiv", request agent join hospital
    { targetDataset := otherTenant }, .deny),
  ("tokenize-other-dataset", "HospitalSiv", request ingest tokenize hospital
    { targetDataset := otherKey }, .deny),
  ("owner-rejected", "HospitalSiv", request agent join hospital
    { ownerApproved := false }, .deny),
  ("agent-reidentify", "HospitalSiv", request agent reidentify hospital reveal, .deny),
  ("operator-reidentify", "HospitalSiv", request operator reidentify hospital reveal, .deny),
  ("reidentify-other-dataset", "HospitalSiv", request steward reidentify hospital
    { reveal with targetDataset := otherKey }, .deny),
  ("steward-reidentify", "HospitalSiv", request steward reidentify hospital reveal, .allow),
  ("reidentify-without-key", "HospitalSiv", request steward reidentify hospital
    { reveal with keyAuthorized := false }, .deny),
  ("wrong-reidentification-key-version", "HospitalSiv",
    request steward reidentify hospital
      { reveal with requestedKeyVersion := "dek-v2" }, .deny),
  ("rotated-key-reidentify", "HospitalSiv",
    request steward reidentify rotatedTokenKey
      { reveal with targetDataset := rotatedTokenKey, requestedKeyVersion := "dek-v2" }, .allow),
  ("no-reidentify-approval", "HospitalSiv", request steward reidentify hospital
    { reveal with reidentifyApproved := false }, .deny),
  ("audit-unavailable", "HospitalSiv", request steward reidentify hospital
    { reveal with auditReady := false }, .deny),
  ("gcm-unique-iv", "RandomizedGcm", request ingest tokenize randomized
    { targetDataset := randomized }, .allow),
  ("gcm-reused-iv", "RandomizedGcm", request ingest tokenize randomized
    { targetDataset := randomized, ivUnique := false }, .deny),
  ("gcm-no-deterministic-join", "RandomizedGcm", request agent join randomized
    { targetDataset := randomized }, .deny),
  ("gcm-steward-reidentify", "RandomizedGcm", request steward reidentify randomized
    { reveal with targetDataset := randomized }, .allow),
  ("hmac-local-join", "OneWayHmac", request agent join oneWay
    { targetDataset := oneWay }, .allow),
  ("hmac-tokenize", "OneWayHmac", request ingest tokenize oneWay
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
