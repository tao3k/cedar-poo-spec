import CedarPooSpec.PolicyModules

/-!
An exact-artifact assessment claim. The Host authenticates its issuer and the
bytes named by `digest`; this value alone is not a signature or a validation
receipt from an external provider.
-/

namespace CedarPooSpec.Data

open Cedar.Spec

inductive AssessmentKind where
  | deidentification
  | modelReview
  | other (name : String)
  deriving Repr, BEq, DecidableEq

structure ArtifactAssessment where
  subject : EntityUID
  digest : String
  kind : AssessmentKind
  assessor : EntityUID
  revision : Nat
  expiresAt : Nat
  passed : Bool
  deriving DecidableEq

/-- Project a claim only for the selected artifact bytes, assessment kind,
    governance revision, and current time. An empty digest never qualifies. -/
def ArtifactAssessment.covers (claim : ArtifactAssessment)
    (kind : AssessmentKind) (subject : EntityUID) (digest : String)
    (assessor : EntityUID) (revision now : Nat) : Bool :=
  claim.passed && !digest.isEmpty &&
    decide (claim.kind = kind ∧ claim.subject = subject ∧
      claim.digest = digest ∧ claim.assessor = assessor ∧
      claim.revision = revision ∧ now < claim.expiresAt)

end CedarPooSpec.Data
