import Examples.Health.Interoperability.UnitedStatesPayer
import CedarPooSpec.Admission.BoundOperation
import CedarPooSpec.Vertical.Health.ClinicalEvidence

/-!
Synthetic Host projection for one Provider Access operation. The Host must
authenticate the validator result and actual patient, consent, treatment
relationship, and resource bytes before constructing these values.
-/

namespace CedarPooSpec.UnitedStatesPayerExample.Admission

open Cedar.Spec CedarPooSpec.Admission CedarPooSpec.UnitedStatesPayerExample
open CedarPooSpec.Vertical.Health.ClinicalEvidence
open CedarPooSpec.Vertical.Health.Region.PackageMetadata

structure Effect where
  actor : EntityUID
  action : EntityUID
  resource : EntityUID
  patient : String
  resourceDigest : String
  deriving DecidableEq

structure Snapshot where
  selectedPublication : Pin
  resourceAttestation : Attestation
  identityVerified : Bool
  treatmentRelationship : Bool
  patientOptOut : Bool
  patientOptIn : Bool
  deriving DecidableEq

def clinicalRecord : Effect :=
  { actor := provider, action := shareWithProvider, resource := clinicalA,
    patient := "patient-a", resourceDigest := "synthetic-clinical-digest" }

def validatedRecord : Attestation :=
  { publication := unitedStates, patient := clinicalRecord.patient,
    resourceDigest := clinicalRecord.resourceDigest,
    validationId := "synthetic-us-validation-receipt", validated := true }

def snapshot : Snapshot :=
  { selectedPublication := unitedStates,
    resourceAttestation := validatedRecord,
    identityVerified := true, treatmentRelationship := true,
    patientOptOut := false, patientOptIn := false }

def operationRequest (effect : Effect) (state : Snapshot) : Request :=
  UnitedStatesPayerExample.request effect.actor effect.action effect.resource {
    subjectPatient := effect.patient,
    identityVerified := state.identityVerified,
    treatmentRelationship := state.treatmentRelationship,
    patientOptOut := state.patientOptOut,
    patientOptIn := state.patientOptIn,
    contentAttested := state.resourceAttestation.ready state.selectedPublication &&
      decide (state.selectedPublication = unitedStates),
    sourceDigestMatches := state.resourceAttestation.covers
      effect.patient effect.resourceDigest }

def proposed : BoundOperation Effect Snapshot operationRequest :=
  ⟨clinicalRecord, snapshot⟩

def payerTransfer : Effect :=
  { clinicalRecord with actor := receivingPayer, action := transferToPayer }
def payerSnapshot : Snapshot := { snapshot with patientOptIn := true }
def proposedPayerTransfer : BoundOperation Effect Snapshot operationRequest :=
  ⟨payerTransfer, payerSnapshot⟩

def admitted (operation : BoundOperation Effect Snapshot operationRequest)
    (effect : Effect) (state : Snapshot) : Bool :=
  match operation.authorize effect state model "Governed" entities with
  | .ok receipt => receipt.allowed
  | .error _ => false

theorem selectedRecordAdmitted :
    admitted proposed clinicalRecord snapshot = true := by native_decide

theorem selectedPayerTransferAdmitted :
    admitted proposedPayerTransfer payerTransfer payerSnapshot = true := by
  native_decide

theorem otherPublicationDenied :
    admitted ⟨clinicalRecord, { snapshot with
      resourceAttestation := { validatedRecord with publication := australia } }⟩
      clinicalRecord { snapshot with
        resourceAttestation := { validatedRecord with publication := australia } } = false := by
  native_decide

theorem wrongPatientDenied :
    admitted ⟨clinicalRecord, { snapshot with
      resourceAttestation := { validatedRecord with patient := "patient-b" } }⟩
      clinicalRecord { snapshot with
        resourceAttestation := { validatedRecord with patient := "patient-b" } } = false := by
  native_decide

theorem changedResourceDenied :
    admitted ⟨clinicalRecord, { snapshot with
      resourceAttestation := { validatedRecord with resourceDigest := "other-resource" } }⟩
      clinicalRecord { snapshot with
        resourceAttestation := { validatedRecord with resourceDigest := "other-resource" } } = false := by
  native_decide

theorem revokedChoiceDenied :
    admitted ⟨clinicalRecord, { snapshot with patientOptOut := true }⟩
      clinicalRecord { snapshot with patientOptOut := true } = false := by
  native_decide

theorem missingPayerOptInDenied :
    admitted ⟨payerTransfer, snapshot⟩ payerTransfer snapshot = false := by
  native_decide

theorem changedEvidenceRejectedBeforeCedar :
    (match proposed.authorize clinicalRecord
        { snapshot with resourceAttestation :=
          { validatedRecord with resourceDigest := "other-resource" } }
        model "Governed" entities with
    | .error .stateMismatch => true
    | _ => false) = true := by native_decide

/-- Concrete Host projections replayed by official Cedar Rust. -/
def projectedCases : List (String × Request × Decision) := [
  ("admission-us-provider", operationRequest clinicalRecord snapshot, .allow),
  ("admission-us-payer", operationRequest payerTransfer payerSnapshot, .allow),
  ("admission-us-other-publication", operationRequest clinicalRecord
    { snapshot with resourceAttestation := { validatedRecord with
      publication := australia } }, .deny),
  ("admission-us-other-patient", operationRequest clinicalRecord
    { snapshot with resourceAttestation := { validatedRecord with
      patient := "patient-b" } }, .deny),
  ("admission-us-other-resource", operationRequest clinicalRecord
    { snapshot with resourceAttestation := { validatedRecord with
      resourceDigest := "other-resource" } }, .deny),
  ("admission-us-payer-no-opt-in", operationRequest payerTransfer snapshot,
    .deny)]

def projectedCasesConform : Bool := projectedCases.all fun (_, req, expected) =>
  match model.compile "Governed" with
  | .error _ => false
  | .ok policies =>
      let answer := isAuthorized req entities policies
      answer.decision == expected && answer.erroringPolicies.isEmpty

theorem projectedCasesConformFully : projectedCasesConform = true := by
  native_decide

end CedarPooSpec.UnitedStatesPayerExample.Admission
