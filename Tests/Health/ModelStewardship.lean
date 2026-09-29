import Examples.Health.ModelStewardship.Admission

namespace CedarPooSpec.ModelStewardshipTest

open CedarPooSpec.ModelStewardshipExample
open CedarPooSpec.ModelStewardshipExample.Admission

private def integrated : CedarPooSpec.PolicyModules.Model :=
  integratedResult.toOption.get (by native_decide)

private def trainingOwner : CedarPooSpec.PolicyModules.Model :=
  (CedarPooSpec.PolicyModules.Model.define "Training" [.extend trainingPermit]).toOption.get
    (by native_decide)

theorem independentOwnerCompiles :
    (trainingOwner.compile "Training").toOption = some [trainingPermit] := by
  native_decide

theorem independentFamiliesBecomeParents :
    ((integrated.objectAt "MedicalModel").toOption.get (by native_decide)).plan.precedence =
      ["MedicalModel", "Training", "Publication", "Clinical", "Lineage"] := by
  native_decide

theorem duplicateOwnerNameIsRejected :
    (trainingOwner.combine "Training" [(trainingOwner, "Training")]
      "InvalidMedicalModel").isOk = false := by
  native_decide

theorem missingOwnerRootIsRejected :
    (trainingOwner.combine "Missing" [] "InvalidMedicalModel").isOk = false := by
  native_decide

private def conflictingPolicyOwner : CedarPooSpec.PolicyModules.Model :=
  (CedarPooSpec.PolicyModules.Model.define "OtherTraining"
    [.extend trainingPermit]).toOption.get (by native_decide)

theorem disjointObjectsDoNotBypassCedarEditChecks :
    (match trainingOwner.combine "Training"
        [(conflictingPolicyOwner, "OtherTraining")] "ConflictingMedicalModel" with
      | .ok combined =>
          match combined.compile "ConflictingMedicalModel" with
          | .error (.policyAlreadyExists id) => id == trainingPermit.id
          | _ => false
      | .error _ => false) = true := by native_decide

theorem mixedRootIsFirstClassObject : integrated.builtObject.isSome = true := by
  native_decide

theorem extendedRootRemainsFirstClassObject : model.builtObject.isSome = true := by
  native_decide

theorem objectBackedCompilationAgreesWithUncached :
    (integrated.compile "MedicalModel").toOption =
      (({ modules := integrated.modules } : CedarPooSpec.PolicyModules.Model).compile
        "MedicalModel").toOption := by native_decide

theorem changedModulesInvalidateObjectCache :
    (({ integrated with modules := [] } : CedarPooSpec.PolicyModules.Model).compile
      "MedicalModel").isOk = false := by native_decide

theorem extendedObjectCompilationAgreesWithUncached :
    (model.compile "Recovered").toOption =
      (({ modules := model.modules } : CedarPooSpec.PolicyModules.Model).compile
        "Recovered").toOption := by native_decide

private def permits (root : String) (effect : Effect) (state : Snapshot) : Bool :=
  admitted root ⟨effect, state⟩ effect state

theorem catalogIsAcyclic : catalog.validate = .ok () := by native_decide

theorem hospitalBWithdrawalReachesPublishedModel :
    catalog.affected ["hospital-b-record"] = .ok
      ["hospital-b-record", "hospital-b-dataset", "joint-dataset",
        "joint-training-run", "joint-model-v1", "joint-endpoint",
        "joint-inference"] := by native_decide

theorem independentModelRemainsAvailable :
    catalog.available ["hospital-b-record"] "hospital-a-model-v1" =
      .ok true := by native_decide

theorem baselineTraining :
    permits "MedicalModel" trainingEffect trainingSnapshot = true := by native_decide

theorem baselinePublication :
    permits "MedicalModel" publicationEffect publicationSnapshot = true := by native_decide

theorem baselineClinicalUse :
    permits "MedicalModel" inferenceEffect inferenceSnapshot = true := by native_decide

theorem swappedTrainingSourceDenied :
    permits "MedicalModel" { trainingEffect with source := independentModel }
      trainingSnapshot = false := by native_decide

theorem expiredTrainingGrantDenied :
    permits "MedicalModel" trainingEffect { trainingSnapshot with now := 100 } =
      false := by native_decide

theorem revokedTrainingGrantDenied :
    permits "MedicalModel" trainingEffect
      { trainingSnapshot with governanceRevision := 2 } = false := by native_decide

theorem missingDeidentificationAssessmentDenied :
    permits "MedicalModel" trainingEffect
      { trainingSnapshot with assessment := none } = false := by native_decide

theorem otherDatasetDigestDenied :
    permits "MedicalModel"
      { trainingEffect with sourceDigest := "other-dataset-bytes" }
      trainingSnapshot = false := by native_decide

theorem otherAssessmentKindDenied :
    permits "MedicalModel" trainingEffect
      { trainingSnapshot with assessment := some modelReviewAssessment } =
      false := by native_decide

theorem failedAssessmentDenied :
    permits "MedicalModel" trainingEffect
      { trainingSnapshot with assessment := some { deidentificationAssessment with passed := false } } =
      false := by native_decide

theorem otherAssessmentIssuerDenied :
    permits "MedicalModel" trainingEffect
      { trainingSnapshot with assessment := some { deidentificationAssessment with assessor := releaseReviewer } } =
      false := by native_decide

theorem otherGrantApproverDenied :
    permits "MedicalModel" trainingEffect
      { trainingSnapshot with grant := some { trainingGrant with approver := releaseReviewer } } =
      false := by native_decide

theorem expiredAssessmentDenied :
    permits "MedicalModel" trainingEffect
      { trainingSnapshot with assessment := some { deidentificationAssessment with expiresAt := 50 } } =
      false := by native_decide

theorem withdrawnSourceBlocksNewTraining :
    permits "MedicalModel" trainingEffect
      { trainingSnapshot with withdrawn := ["hospital-b-record"] } =
      false := by native_decide

theorem withdrawnSourceBlocksModelPublication :
    permits "MedicalModel" publicationEffect
      { publicationSnapshot with withdrawn := ["hospital-b-record"] } =
      false := by native_decide

theorem withdrawnSourceBlocksEndpointUse :
    permits "MedicalModel" inferenceEffect
      { inferenceSnapshot with withdrawn := ["hospital-b-record"] } =
      false := by native_decide

theorem unknownWithdrawalFailsClosed :
    permits "MedicalModel" trainingEffect
      { trainingSnapshot with withdrawn := ["unknown-source"] } =
      false := by native_decide

theorem otherDeploymentTargetDenied :
    permits "MedicalModel"
      { publicationEffect with target := independentEndpoint }
      publicationSnapshot = false := by native_decide

theorem withdrawnPublicationGrantDenied :
    permits "MedicalModel" publicationEffect
      { publicationSnapshot with governanceRevision := 2 } =
      false := by native_decide

theorem unreviewedModelDenied :
    permits "MedicalModel" publicationEffect
      { publicationSnapshot with assessment := none } = false := by native_decide

theorem changedModelBytesDenied :
    permits "MedicalModel"
      { publicationEffect with sourceDigest := "modified-model-bytes" }
      publicationSnapshot = false := by native_decide

theorem publicationCannotSubstituteResource :
    permits "MedicalModel"
      { publicationEffect with resource := independentModel }
      publicationSnapshot = false := by native_decide

theorem clinicalUseRequiresPatientBinding :
    permits "MedicalModel"
      { inferenceEffect with patient := some "patient-43" }
      inferenceSnapshot = false := by native_decide

theorem incidentBlocksPublication :
    permits "ModelIncident" publicationEffect publicationSnapshot = false := by
  native_decide

theorem incidentBlocksInference :
    permits "ModelIncident" inferenceEffect inferenceSnapshot = false := by
  native_decide

theorem incidentLeavesTrainingOwner :
    permits "ModelIncident" trainingEffect trainingSnapshot = true := by
  native_decide

theorem recoveryRestoresPublication :
    permits "Recovered" publicationEffect publicationSnapshot = true := by
  native_decide

theorem selectedModelCannotBorrowOtherAvailability :
    permits "MedicalModel" { publicationEffect with artifact := "hospital-a-model-v1" }
      publicationSnapshot = false := by native_decide

theorem staleLineageRevisionDenied :
    permits "MedicalModel" publicationEffect
      { publicationSnapshot with lineageRevision := "r2" } =
      false := by native_decide

theorem substitutedEffectRejectedBeforeCedar :
    (match proposedPublication.authorize
        { publicationEffect with sourceDigest := "modified-model-bytes" }
        publicationSnapshot model "MedicalModel" (entities "r1") with
    | .error .effectMismatch => true
    | _ => false) = true := by native_decide

theorem changedEvidenceRejectedBeforeCedar :
    (match proposedPublication.authorize publicationEffect
        { publicationSnapshot with assessment := none }
        model "MedicalModel" (entities "r1") with
    | .error .stateMismatch => true
    | _ => false) = true := by native_decide

theorem changedConsentStateRejectedBeforeCedar :
    (match proposedTraining.authorize trainingEffect
        { trainingSnapshot with withdrawn := ["hospital-b-record"] }
        model "MedicalModel" (entities "r1") with
    | .error .stateMismatch => true
    | _ => false) = true := by native_decide

end CedarPooSpec.ModelStewardshipTest
