import Examples.Health.ModelStewardship
import CedarPooSpec.Admission.BoundOperation
import CedarPooSpec.Data.ArtifactAssessment

/-!
One proposed training, model-publication, or inference effect is projected to
Cedar from its exact selected bytes and a Host-supplied snapshot. The Host must
authenticate the snapshot and atomically bind the eventual effect to it.
-/

namespace CedarPooSpec.ModelStewardshipExample.Admission

open Cedar.Spec CedarPooSpec.Admission CedarPooSpec.Data
open CedarPooSpec.ModelStewardshipExample

structure Effect where
  actor : EntityUID
  action : EntityUID
  resource : EntityUID
  artifact : String
  source : EntityUID
  target : EntityUID
  sourceDigest : String
  purpose : String
  patient : Option String := none
  deriving DecidableEq

structure Snapshot where
  withdrawn : List String := []
  lineageRevision : String := "r1"
  catalogRevision : String := "r1"
  governanceRevision : Nat := 1
  now : Nat := 50
  grant : Option CedarPooSpec.Governance.ScopedApproval := none
  assessment : Option ArtifactAssessment := none
  patientBinding : Option String := none
  clinicalValidationCurrent : Bool := false
  auditReady : Bool := false
  deriving DecidableEq

/-- Project only selected, exact-byte evidence into Cedar facts. An invalid
    catalog is treated as unavailable, never as an empty withdrawal set. -/
def operationRequest (effect : Effect) (state : Snapshot) : Request :=
  let available := (catalog.available state.withdrawn effect.artifact).toOption.getD false
  let approval := state.grant.any fun grant =>
    grant.applies effect.actor effect.action effect.purpose
      effect.source effect.target state.governanceRevision state.now &&
      (if effect.action == train then grant.approver == studyReviewer
       else grant.approver == releaseReviewer)
  let selected :=
    if effect.action == train then effect.target == effect.resource
    else if effect.action == publish then effect.source == effect.resource
    else true
  let assessed (kind : AssessmentKind) (assessor : EntityUID) :=
    state.assessment.any fun claim =>
    claim.covers kind effect.source effect.sourceDigest assessor
      state.governanceRevision state.now
  let patientBound := effect.patient.any (fun patient =>
    !patient.isEmpty && state.patientBinding == some patient)
  request effect.actor effect.action effect.resource {
    artifact := effect.artifact,
    lineageRevision := state.catalogRevision,
    lineageAvailable := available,
    purpose := effect.purpose,
    approvalValid := approval && selected,
    deidentificationAttested := assessed .deidentification studyReviewer,
    modelReviewed := assessed .modelReview releaseReviewer,
    sinkBound := effect.target == jointEndpoint && selected,
    patientBound := patientBound,
    clinicalValidationCurrent := state.clinicalValidationCurrent,
    auditReady := state.auditReady }

def deidentificationAssessment : ArtifactAssessment :=
  { subject := jointDataset, digest := "joint-dataset-digest-v1",
    kind := .deidentification, assessor := studyReviewer,
    revision := 1, expiresAt := 100, passed := true }

def modelReviewAssessment : ArtifactAssessment :=
  { subject := jointModel, digest := "joint-model-digest-v1",
    kind := .modelReview, assessor := releaseReviewer,
    revision := 1, expiresAt := 100, passed := true }

def trainingEffect : Effect :=
  { actor := trainer, action := train, resource := jointRun,
    artifact := "joint-training-run", source := jointDataset,
    target := jointRun, sourceDigest := "joint-dataset-digest-v1",
    purpose := "research" }

def publicationEffect : Effect :=
  { actor := publisher, action := publish, resource := jointModel,
    artifact := "joint-model-v1", source := jointModel,
    target := jointEndpoint, sourceDigest := "joint-model-digest-v1",
    purpose := "publication" }

def inferenceEffect : Effect :=
  { actor := clinician, action := infer, resource := jointEndpoint,
    artifact := "joint-endpoint", source := jointEndpoint,
    target := jointEndpoint, sourceDigest := "joint-model-digest-v1",
    purpose := "treatment", patient := some "patient-42" }

def trainingSnapshot : Snapshot :=
  { grant := some trainingGrant,
    assessment := some deidentificationAssessment }

def publicationSnapshot : Snapshot :=
  { grant := some publicationGrant,
    assessment := some modelReviewAssessment }

def inferenceSnapshot : Snapshot :=
  { patientBinding := some "patient-42",
    clinicalValidationCurrent := true, auditReady := true }

def proposedTraining : BoundOperation Effect Snapshot operationRequest :=
  ⟨trainingEffect, trainingSnapshot⟩

def proposedPublication : BoundOperation Effect Snapshot operationRequest :=
  ⟨publicationEffect, publicationSnapshot⟩

def proposedInference : BoundOperation Effect Snapshot operationRequest :=
  ⟨inferenceEffect, inferenceSnapshot⟩

/-- Pure admission over exact values; no data-plane effect is performed. -/
def admitted (root : String)
    (operation : BoundOperation Effect Snapshot operationRequest)
    (effect : Effect) (state : Snapshot) : Bool :=
  match operation.authorize effect state model root (entities state.lineageRevision) with
  | .ok receipt => receipt.allowed
  | .error _ => false

end CedarPooSpec.ModelStewardshipExample.Admission
