import Examples.Enterprise.Vehicle.TARA.TaraProjection

/-!
TARA owns the complete assessment and approval. This adapter consumes only
an externally verified reference to a selected TARA work product and its
treatment goal. It checks whether a linked executable treatment needs review;
it neither parses the assessment nor assigns a risk rating.
-/

namespace CedarPooSpec.TaraHandoffExample

structure TaraReference where
  source : String
  workProductId : String
  revision : String
  approvalRef : String
  treatmentGoal : String
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
    (prior : Handoff) (currentTara : TaraReference)
    (currentTreatment : TreatmentPublication) : List ReviewObligation :=
  (if verifyTara currentTara then [] else [.taraOwnerReview]) ++
  (if prior.tara == currentTara && prior.treatment == currentTreatment
    then [] else [.treatmentOwnerReview])

def prior : Handoff := {
  tara := ⟨"example-tara", "case-7", "tara-r1", "approval-a", "command-integrity"⟩
  treatment := ⟨"Current", "policy-a"⟩ }

/- Only a test assumption. A host must verify approval and source identity. -/
def assumedTaraVerified (reference : TaraReference) : Bool :=
  reference.source == "example-tara" &&
    reference.workProductId == "case-7" &&
    ((reference.revision == "tara-r1" &&
        reference.approvalRef == "approval-a" &&
        reference.treatmentGoal == "command-integrity") ||
      (reference.revision == "tara-r2" &&
        reference.approvalRef == "approval-b" &&
        reference.treatmentGoal == "command-integrity") ||
      (reference.revision == "tara-r3" &&
        reference.approvalRef == "approval-c" &&
        reference.treatmentGoal == "voice-command-integrity"))

def revisedTara : TaraReference :=
  { prior.tara with revision := "tara-r2", approvalRef := "approval-b" }

def changedGoal : TaraReference :=
  { prior.tara with
      revision := "tara-r3", approvalRef := "approval-c",
      treatmentGoal := "voice-command-integrity" }

def revokedTara : TaraReference :=
  { prior.tara with approvalRef := "revoked" }

def revisedTreatment : TreatmentPublication :=
  { prior.treatment with revision := "policy-b" }

theorem unchangedVerifiedLinkNeedsNoReview :
    reviewObligations assumedTaraVerified prior prior.tara prior.treatment = [] := by
  native_decide

theorem changedTaraReferenceRechecksTreatmentLink :
    reviewObligations assumedTaraVerified prior revisedTara prior.treatment =
      [.treatmentOwnerReview] ∧
    reviewObligations assumedTaraVerified prior changedGoal prior.treatment =
      [.treatmentOwnerReview] := by
  native_decide

theorem changedPolicyRechecksTreatment :
    reviewObligations assumedTaraVerified prior prior.tara revisedTreatment =
      [.treatmentOwnerReview] := by
  native_decide

theorem changedBothSidesEmitOneTreatmentObligation :
    reviewObligations assumedTaraVerified prior revisedTara revisedTreatment =
      [.treatmentOwnerReview] := by
  native_decide

theorem unverifiedTaraReferenceRequiresSourceReview :
    reviewObligations assumedTaraVerified prior revokedTara prior.treatment =
      [.taraOwnerReview, .treatmentOwnerReview] := by
  native_decide

theorem approvalCannotBeCarriedAcrossRevision :
    reviewObligations assumedTaraVerified prior
      { prior.tara with revision := "tara-r2" } prior.treatment =
        [.taraOwnerReview, .treatmentOwnerReview] := by
  native_decide

end CedarPooSpec.TaraHandoffExample
