import CedarPooSpec.Data.Lineage
import CedarPooSpec.Data.LineageUse
import CedarPooSpec.Governance.ScopedApproval
import CedarPooSpec.PolicyJson

/-!
Synthetic medical model lifecycle inspired by publicly announced healthcare AI
collaborations. It is not a description of any provider's deployed system.
The Host authenticates approvals, de-identification, lineage, review, and the
actual training, publication, and inference effects.
-/

namespace CedarPooSpec.ModelStewardshipExample

open Cedar.Spec Cedar.Data CedarPooSpec.PolicyModules
open CedarPooSpec.Data CedarPooSpec.Data.Lineage
open CedarPooSpec.Governance

def actorType : EntityType := ⟨"Actor", []⟩
def artifactType : EntityType := ⟨"Artifact", []⟩
def actionType : EntityType := ⟨"Action", []⟩

def trainer : EntityUID := ⟨actorType, "model-trainer"⟩
def publisher : EntityUID := ⟨actorType, "model-publisher"⟩
def clinician : EntityUID := ⟨actorType, "clinician"⟩
def studyReviewer : EntityUID := ⟨actorType, "study-reviewer"⟩
def releaseReviewer : EntityUID := ⟨actorType, "release-reviewer"⟩
def train : EntityUID := ⟨actionType, "train"⟩
def publish : EntityUID := ⟨actionType, "publish"⟩
def infer : EntityUID := ⟨actionType, "infer"⟩

def jointDataset : EntityUID := ⟨artifactType, "joint-dataset"⟩
def jointRun : EntityUID := ⟨artifactType, "joint-training-run"⟩
def jointModel : EntityUID := ⟨artifactType, "joint-model-v1"⟩
def jointEndpoint : EntityUID := ⟨artifactType, "joint-endpoint"⟩
def independentModel : EntityUID := ⟨artifactType, "hospital-a-model-v1"⟩
def independentEndpoint : EntityUID := ⟨artifactType, "hospital-a-endpoint"⟩

def catalog : Catalog := ⟨[
  ⟨"hospital-a-record", .source, []⟩,
  ⟨"hospital-b-record", .source, []⟩,
  ⟨"hospital-a-dataset", .fragment, ["hospital-a-record"]⟩,
  ⟨"hospital-b-dataset", .fragment, ["hospital-b-record"]⟩,
  ⟨"joint-dataset", .other "training-dataset",
    ["hospital-a-dataset", "hospital-b-dataset"]⟩,
  ⟨"joint-training-run", .other "training-run", ["joint-dataset"]⟩,
  ⟨"joint-model-v1", .other "model-checkpoint", ["joint-training-run"]⟩,
  ⟨"joint-endpoint", .other "deployment", ["joint-model-v1"]⟩,
  ⟨"joint-inference", .result, ["joint-endpoint"]⟩,
  ⟨"hospital-a-training-run", .other "training-run", ["hospital-a-dataset"]⟩,
  ⟨"hospital-a-model-v1", .other "model-checkpoint", ["hospital-a-training-run"]⟩,
  ⟨"hospital-a-endpoint", .other "deployment", ["hospital-a-model-v1"]⟩]⟩

def entity (attrs : List (String × Value)) : EntityData :=
  { attrs := Map.make attrs, ancestors := Set.empty, tags := Map.empty }

def artifactData (id kind revision : String) : EntityData :=
  entity [("artifactId", .prim (.string id)),
    ("kind", .prim (.string kind)),
    ("lineageRevision", .prim (.string revision))]

def entities (revision : String) : Entities := Map.make [
  (trainer, entity [("kind", .prim (.string "trainer"))]),
  (publisher, entity [("kind", .prim (.string "publisher"))]),
  (clinician, entity [("kind", .prim (.string "clinician"))]),
  (jointDataset, artifactData "joint-dataset" "dataset" revision),
  (jointRun, artifactData "joint-training-run" "run" revision),
  (jointModel, artifactData "joint-model-v1" "model" revision),
  (jointEndpoint, artifactData "joint-endpoint" "endpoint" revision),
  (independentModel, artifactData "hospital-a-model-v1" "model" revision),
  (independentEndpoint, artifactData "hospital-a-endpoint" "endpoint" revision)]

private def attr (source : Var) (name : String) : Expr :=
  .getAttr (.var source) name
private def eq (left right : Expr) : Expr := .binaryApp .eq left right
private def string (value : String) : Expr := .lit (.string value)
private def all (conditions : List Expr) : Expr :=
  conditions.foldr Expr.and (.lit (.bool true))

def permit (id : String) (action : EntityUID) (conditions : List Expr) : Policy :=
  { id, effect := .permit,
    principalScope := .principalScope .any,
    actionScope := .actionScope (.eq action),
    resourceScope := .resourceScope .any,
    condition := [{ kind := .when, body := all conditions }] }

def trainingPermit : Policy := permit "model-training" train [
  eq (attr .principal "kind") (string "trainer"),
  eq (attr .resource "kind") (string "run"),
  eq (attr .context "purpose") (string "research"),
  attr .context "approvalValid",
  attr .context "deidentificationAttested"]

def publicationPermit : Policy := permit "model-publication" publish [
  eq (attr .principal "kind") (string "publisher"),
  eq (attr .resource "kind") (string "model"),
  eq (attr .context "purpose") (string "publication"),
  attr .context "approvalValid",
  attr .context "modelReviewed",
  attr .context "sinkBound"]

def inferencePermit : Policy := permit "clinical-inference" infer [
  eq (attr .principal "kind") (string "clinician"),
  eq (attr .resource "kind") (string "endpoint"),
  eq (attr .context "purpose") (string "treatment"),
  attr .context "patientBound",
  attr .context "clinicalValidationCurrent",
  attr .context "auditReady"]

def lineageControl : LineageUse :=
  { policyId := "model-lineage-current",
    actionScope := .actionInAny [train, publish, infer] }

def incidentControl : Veto :=
  { policyId := "model-release-incident",
    actionScope := .actionInAny [publish, infer],
    denyWhen := .lit (.bool true) }

def modelResult : Except LeanPoo.C4.Error Model := do
  let base : Model := { modules := [{ name := "Base" }] }
  let training ← base.extend "Training" "Base" [.extend trainingPermit]
  let publication ← training.extend "Publication" "Base" [.extend publicationPermit]
  let clinical ← publication.extend "Clinical" "Base" [.extend inferencePermit]
  let lineage ← clinical.extend "Lineage" "Base"
    [lineageControl.edit .introduce]
  let integrated ← lineage.mix "MedicalModel"
    ["Training", "Publication", "Clinical", "Lineage"]
  let incident ← integrated.extend "ModelIncident" "MedicalModel"
    [incidentControl.edit .introduce]
  incident.extend "Recovered" "ModelIncident"
    [incidentControl.edit .withdraw]

def model : Model := modelResult.toOption.get (by native_decide)

/-- The grant source, target, action, purpose, and governance revision must
    all match. The Host supplies authenticated grant and clock values. -/
def trainingGrant : ScopedApproval :=
  { id := "study-approval-42", approver := studyReviewer, actor := trainer,
    operation := train, purpose := "research", source := jointDataset,
    target := jointRun, revision := 1, expiresAt := 100 }

def publicationGrant : ScopedApproval :=
  { id := "model-release-42", approver := releaseReviewer, actor := publisher,
    operation := publish, purpose := "publication", source := jointModel,
    target := jointEndpoint, revision := 1, expiresAt := 100 }

structure Facts where
  artifact : String
  lineageRevision : String
  lineageAvailable : Bool
  purpose : String
  approvalValid : Bool := false
  deidentificationAttested : Bool := false
  modelReviewed : Bool := false
  sinkBound : Bool := false
  patientBound : Bool := false
  clinicalValidationCurrent : Bool := false
  auditReady : Bool := false

def factsFor (artifact : String) (withdrawn : List String)
    (revision purpose : String) : Except Lineage.Error Facts := do
  let available ← catalog.available withdrawn artifact
  return { artifact := artifact, lineageRevision := revision, lineageAvailable := available, purpose := purpose }

def request (actor action resource : EntityUID) (facts : Facts) : Request :=
  ⟨actor, action, resource, Map.make [
    ("targetArtifact", .prim (.string facts.artifact)),
    ("lineageRevision", .prim (.string facts.lineageRevision)),
    ("lineageAvailable", .prim (.bool facts.lineageAvailable)),
    ("purpose", .prim (.string facts.purpose)),
    ("approvalValid", .prim (.bool facts.approvalValid)),
    ("deidentificationAttested", .prim (.bool facts.deidentificationAttested)),
    ("modelReviewed", .prim (.bool facts.modelReviewed)),
    ("sinkBound", .prim (.bool facts.sinkBound)),
    ("patientBound", .prim (.bool facts.patientBound)),
    ("clinicalValidationCurrent", .prim (.bool facts.clinicalValidationCurrent)),
    ("auditReady", .prim (.bool facts.auditReady))]⟩

def decision (root revision : String) (req : Request) : Option Decision := do
  let policies ← (model.compile root).toOption
  let response := isAuthorized req (entities revision) policies
  if response.erroringPolicies.isEmpty then some response.decision else none

def trainRequest (withdrawn : List String) (source target : EntityUID)
    (grantRevision : Nat := 1) (now : Nat := 50)
    (deidentified : Bool := true) : Except Lineage.Error Request := do
  let facts ← factsFor "joint-training-run" withdrawn "r1" "research"
  let valid := trainingGrant.applies trainer train "research" source target
    grantRevision now
  return request trainer train jointRun
    { facts with approvalValid := valid, deidentificationAttested := deidentified }

def trainDecisionAt (root : String) (withdrawn : List String)
    (source target : EntityUID)
    (grantRevision : Nat := 1) (now : Nat := 50)
    (deidentified : Bool := true) : Except Lineage.Error (Option Decision) := do
  return decision root "r1" (← trainRequest withdrawn source target grantRevision now deidentified)

def trainDecision (withdrawn : List String) (source target : EntityUID)
    (grantRevision : Nat := 1) (now : Nat := 50)
    (deidentified : Bool := true) : Except Lineage.Error (Option Decision) :=
  trainDecisionAt "MedicalModel" withdrawn source target grantRevision now deidentified

def publishRequest (withdrawn : List String)
    (source target : EntityUID) (grantRevision : Nat := 1)
    (reviewed : Bool := true) : Except Lineage.Error Request := do
  let facts ← factsFor "joint-model-v1" withdrawn "r1" "publication"
  let valid := publicationGrant.applies publisher publish "publication"
    source target grantRevision 50
  return request publisher publish jointModel
    { facts with approvalValid := valid, modelReviewed := reviewed, sinkBound := target == jointEndpoint }

def publishDecision (root : String) (withdrawn : List String)
    (source target : EntityUID) (grantRevision : Nat := 1)
    (reviewed : Bool := true) : Except Lineage.Error (Option Decision) := do
  return decision root "r1" (← publishRequest withdrawn source target grantRevision reviewed)

def inferRequest (withdrawn : List String)
    (patientBound : Bool := true) : Except Lineage.Error Request := do
  let facts ← factsFor "joint-endpoint" withdrawn "r1" "treatment"
  return request clinician infer jointEndpoint
    { facts with patientBound := patientBound, clinicalValidationCurrent := true, auditReady := true }

def inferDecision (root : String) (withdrawn : List String)
    (patientBound : Bool := true) : Except Lineage.Error (Option Decision) := do
  return decision root "r1" (← inferRequest withdrawn patientBound)

end CedarPooSpec.ModelStewardshipExample
