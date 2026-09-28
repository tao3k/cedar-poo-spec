import Examples.Health.Interoperability.AustralianEMR
import CedarPooSpec.Admission.BoundOperation
import CedarPooSpec.Vertical.Health.Region.PackageMetadata
import CedarPooSpec.Vertical.Health.ClinicalEvidence

/-!
Synthetic Host projection. A real parser, terminology service, identifier
service, and profile validator must authenticate these values before the Host
constructs this snapshot. Equality below binds evidence; it does not validate
FHIR, AUCDI, AU Core, or SNOMED CT-AU content.
-/

namespace CedarPooSpec.AustralianEMRExample.Admission

open Cedar.Spec CedarPooSpec.AustralianEMRExample CedarPooSpec.Admission
open CedarPooSpec.Vertical.Health.ClinicalEvidence

structure ProfilePins where
  contentReference : String
  fhirProfile : String
  terminologyRelease : String
  deriving DecidableEq

structure Effect where
  document : EntityUID
  patient : String
  documentDigest : String
  deriving DecidableEq

structure Snapshot where
  selectedProfile : ProfilePins
  attestedProfile : ProfilePins
  resourceAttestation : Attestation
  ihiVerified : Bool
  patientDeclinedUpload : Bool
  policyRevision : Nat
  deriving DecidableEq

def selectedProfile : ProfilePins :=
  { contentReference := "AUCDI Release 2",
    fhirProfile := CedarPooSpec.Vertical.Health.Region.PackageMetadata.australia.reference,
    terminologyRelease := "NCTS synthetic release" }
def document : Effect :=
  { document := dischargeA, patient := "patient-a",
    documentDigest := "synthetic-discharge-digest" }
def validatedDocument : Attestation :=
  { publication := CedarPooSpec.Vertical.Health.Region.PackageMetadata.australia,
    patient := document.patient, resourceDigest := document.documentDigest,
    validationId := "synthetic-validation-receipt", validated := true }
def snapshot : Snapshot :=
  { selectedProfile, attestedProfile := selectedProfile,
    resourceAttestation := validatedDocument, ihiVerified := true,
    patientDeclinedUpload := false, policyRevision := 1 }

def operationRequest (effect : Effect) (state : Snapshot) : Request :=
  AustralianEMRExample.request hospital effect.document {
    subjectPatient := effect.patient,
    ihiVerified := state.ihiVerified,
    patientDeclinedUpload := state.patientDeclinedUpload,
    contentAttested := state.resourceAttestation.ready
      CedarPooSpec.Vertical.Health.Region.PackageMetadata.australia &&
      state.selectedProfile.fhirProfile ==
        CedarPooSpec.Vertical.Health.Region.PackageMetadata.australia.reference &&
      decide (state.selectedProfile = state.attestedProfile),
    sourceDigestMatches := state.resourceAttestation.covers
      effect.patient effect.documentDigest }

def proposed : BoundOperation Effect Snapshot operationRequest :=
  ⟨document, snapshot⟩

def admitted (operation : BoundOperation Effect Snapshot operationRequest)
    (effect : Effect) (state : Snapshot) : Bool :=
  !effect.documentDigest.isEmpty &&
    match operation.authorize effect state model "Governed" entities with
    | .ok receipt => receipt.allowed
    | .error _ => false

theorem selectedDocumentAdmitted : admitted proposed document snapshot = true := by
  native_decide

theorem changedContentReferenceDenied :
    admitted ⟨document, { snapshot with
      attestedProfile := { selectedProfile with
        contentReference := "other-content-reference" } }⟩
      document { snapshot with
        attestedProfile := { selectedProfile with
          contentReference := "other-content-reference" } } = false := by
  native_decide

theorem changedFhirProfileDenied :
    admitted ⟨document, { snapshot with
      attestedProfile := { selectedProfile with
        fhirProfile := "other-profile" } }⟩
      document { snapshot with
        attestedProfile := { selectedProfile with
          fhirProfile := "other-profile" } } = false := by
  native_decide

theorem wrongPublicationDenied :
    admitted ⟨document, { snapshot with
      resourceAttestation := { validatedDocument with
        publication := CedarPooSpec.Vertical.Health.Region.PackageMetadata.unitedStates } }⟩
      document { snapshot with
        resourceAttestation := { validatedDocument with
          publication := CedarPooSpec.Vertical.Health.Region.PackageMetadata.unitedStates } } = false := by
  native_decide

theorem substitutedSelectionDenied :
    admitted ⟨document, { snapshot with
      selectedProfile := { selectedProfile with fhirProfile := "other-profile" },
      attestedProfile := { selectedProfile with fhirProfile := "other-profile" } }⟩
      document { snapshot with
        selectedProfile := { selectedProfile with fhirProfile := "other-profile" },
        attestedProfile := { selectedProfile with fhirProfile := "other-profile" } } = false := by
  native_decide

theorem staleTerminologyReleaseDenied :
    admitted ⟨document, { snapshot with
      attestedProfile := { selectedProfile with
        terminologyRelease := "older-release" } }⟩
      document { snapshot with
        attestedProfile := { selectedProfile with
          terminologyRelease := "older-release" } } = false := by
  native_decide

theorem patientInstructionDenied :
    admitted ⟨document, { snapshot with patientDeclinedUpload := true }⟩
      document { snapshot with patientDeclinedUpload := true } = false := by
  native_decide

theorem changedEvidenceRejectedBeforeCedar :
    (match proposed.authorize document
        { snapshot with resourceAttestation :=
          { validatedDocument with resourceDigest := "swapped-payload" } }
        model "Governed" entities with
    | .error .stateMismatch => true
    | _ => false) = true := by native_decide

theorem changedEffectRejectedBeforeCedar :
    (match proposed.authorize
        { document with documentDigest := "swapped-payload" } snapshot
        model "Governed" entities with
    | .error .effectMismatch => true
    | _ => false) = true := by native_decide

/-- Concrete Host projections replayed by official Cedar Rust. -/
def substitutedSnapshot : Snapshot :=
  { snapshot with
    selectedProfile := { selectedProfile with fhirProfile := "other-profile" },
    attestedProfile := { selectedProfile with fhirProfile := "other-profile" } }

def projectedCases : List (String × Request × Decision) := [
  ("admission-au-selected", operationRequest document snapshot, .allow),
  ("admission-au-other-publication", operationRequest document
    { snapshot with resourceAttestation := { validatedDocument with
      publication := CedarPooSpec.Vertical.Health.Region.PackageMetadata.unitedStates } },
    .deny),
  ("admission-au-other-resource", operationRequest document
    { snapshot with resourceAttestation := { validatedDocument with
      resourceDigest := "other-resource" } }, .deny),
  ("admission-au-substituted-selection",
    operationRequest document substitutedSnapshot, .deny)]

def projectedCasesConform : Bool := projectedCases.all fun (_, req, expected) =>
  match model.compile "Governed" with
  | .error _ => false
  | .ok policies =>
      let answer := isAuthorized req entities policies
      answer.decision == expected && answer.erroringPolicies.isEmpty

theorem projectedCasesConformFully : projectedCasesConform = true := by
  native_decide

end CedarPooSpec.AustralianEMRExample.Admission
