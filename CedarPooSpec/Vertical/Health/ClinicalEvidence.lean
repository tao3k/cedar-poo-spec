import CedarPooSpec.Vertical.Health.Region.PackageMetadata

/-!
The Host projects an authenticated resource-validation result into this value.
Constructing the value in Lean does not authenticate a validator or a payload.
-/

namespace CedarPooSpec.Vertical.Health.ClinicalEvidence

open CedarPooSpec.Vertical.Health.Region.PackageMetadata

/-- A Host-supplied claim about one exact resource and IG publication. -/
structure Attestation where
  publication : Pin
  patient : String
  resourceDigest : String
  validationId : String
  validated : Bool
  deriving DecidableEq

/-- Check publication and result identity before projecting an attestation
    into a Cedar authorization fact. -/
def Attestation.ready (claim : Attestation) (selected : Pin) : Bool :=
  claim.validated && !claim.validationId.isEmpty &&
    decide (claim.publication = selected)

/-- Bind the claimed validation to the patient and exact resource bytes of
    the proposed operation. -/
def Attestation.covers (claim : Attestation)
    (patient resourceDigest : String) : Bool :=
  !patient.isEmpty && !resourceDigest.isEmpty && claim.patient == patient &&
    claim.resourceDigest == resourceDigest

end CedarPooSpec.Vertical.Health.ClinicalEvidence
