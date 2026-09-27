import Examples.Enterprise.Vehicle.TARA.TaraProjection

/-!
TARA owns the risk assessment and its approval. This boundary links an
externally verified TARA reference to an executable treatment publication,
and emits review obligations when either side changes. It does not infer a
risk rating or approve a TARA work product.
-/

namespace CedarPooSpec.TaraHandoffExample

structure AssessmentInputs where
  vehicleItem : String
  operatingDomain : String
  inputSurface : String
  hardwareBoundary : String
  asset : String
  damageScenario : String
  attackPath : String
  modelRevision : String
  referenceAuthority : String
  deriving DecidableEq, Repr

structure TaraReference where
  assessmentId : String
  approvalId : String
  inputs : AssessmentInputs
  deriving DecidableEq, Repr

structure TreatmentPublication where
  root : String
  revision : String
  deriving DecidableEq, Repr

structure Handoff where
  tara : TaraReference
  treatment : TreatmentPublication

inductive ReviewObligation where
  | taraOwnerReview
  | treatmentOwnerReview
  deriving DecidableEq, Repr

def reviewObligations (verifyTara : TaraReference → Bool)
    (prior : Handoff) (currentInputs : AssessmentInputs)
    (currentTreatment : TreatmentPublication) : List ReviewObligation :=
  (if verifyTara prior.tara && decide (prior.tara.inputs = currentInputs)
    then [] else [.taraOwnerReview]) ++
  (if prior.treatment == currentTreatment
    then [] else [.treatmentOwnerReview])

def assessedInputs : AssessmentInputs := {
  vehicleItem := "illustrative-vehicle"
  operatingDomain := "bounded-route"
  inputSurface := "planner-output"
  hardwareBoundary := "vehicle-host"
  asset := "vehicle-motion"
  damageScenario := "future-collision"
  attackPath := "untrusted-planner-command"
  modelRevision := "model-a"
  referenceAuthority := "independent-reference-a" }

def currentTreatment : TreatmentPublication :=
  ⟨"Current", "policy-a"⟩

def prior : Handoff := {
  tara := ⟨"assessment-7", "approval-4", assessedInputs⟩
  treatment := currentTreatment }

/- Only an example verifier. A real host must validate the external approval. -/
def assumedTaraVerified (reference : TaraReference) : Bool :=
  reference.assessmentId == "assessment-7" &&
    reference.approvalId == "approval-4"

def cabinVoice : AssessmentInputs :=
  { assessedInputs with
      inputSurface := "cabin-speech"
      attackPath := "unverified-voice-command" }

def wearableBridge : AssessmentInputs :=
  { assessedInputs with
      inputSurface := "wearable-automation"
      hardwareBoundary := "paired-device-to-vehicle" }

def embeddedDetector : AssessmentInputs :=
  { assessedInputs with
      inputSurface := "CAN-traffic"
      hardwareBoundary := "embedded-detector-to-controller" }

theorem unchangedVerifiedHandoffNeedsNoReview :
    reviewObligations assumedTaraVerified prior assessedInputs
      currentTreatment = [] := by
  native_decide

theorem newInputOrHardwareBoundaryGoesBackToTaraOwner :
    reviewObligations assumedTaraVerified prior cabinVoice currentTreatment =
      [.taraOwnerReview] ∧
    reviewObligations assumedTaraVerified prior wearableBridge currentTreatment =
      [.taraOwnerReview] ∧
    reviewObligations assumedTaraVerified prior embeddedDetector currentTreatment =
      [.taraOwnerReview] := by
  native_decide

theorem newPolicyRevisionGoesToTreatmentOwner :
    reviewObligations assumedTaraVerified prior assessedInputs
      ⟨"Current", "policy-b"⟩ = [.treatmentOwnerReview] := by
  native_decide

theorem simultaneousChangesKeepBothObligations :
    reviewObligations assumedTaraVerified prior cabinVoice
      ⟨"Current", "policy-b"⟩ =
        [.taraOwnerReview, .treatmentOwnerReview] := by
  native_decide

theorem invalidApprovalGoesBackToTaraOwner :
    reviewObligations assumedTaraVerified
      { prior with tara := { prior.tara with approvalId := "unknown" } }
      assessedInputs currentTreatment = [.taraOwnerReview] := by
  native_decide

end CedarPooSpec.TaraHandoffExample
