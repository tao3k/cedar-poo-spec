import Examples.Health.ModelStewardship

namespace CedarPooSpec.ModelStewardshipTest

open Cedar.Spec CedarPooSpec.ModelStewardshipExample

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
    trainDecision [] jointDataset jointRun = .ok (some .allow) := by native_decide

theorem baselinePublication :
    publishDecision "MedicalModel" [] jointModel jointEndpoint =
      .ok (some .allow) := by native_decide

theorem baselineClinicalUse :
    inferDecision "MedicalModel" [] = .ok (some .allow) := by native_decide

theorem swappedTrainingSourceDenied :
    trainDecision [] independentModel jointRun =
      .ok (some .deny) := by native_decide

theorem expiredTrainingGrantDenied :
    trainDecision [] jointDataset jointRun 1 100 =
      .ok (some .deny) := by native_decide

theorem revokedTrainingGrantDenied :
    trainDecision [] jointDataset jointRun 2 =
      .ok (some .deny) := by native_decide

theorem missingDeidentificationReceiptDenied :
    trainDecision [] jointDataset jointRun 1 50 false =
      .ok (some .deny) := by native_decide

theorem withdrawnSourceBlocksNewTraining :
    trainDecision ["hospital-b-record"] jointDataset jointRun =
      .ok (some .deny) := by native_decide

theorem withdrawnSourceBlocksModelPublication :
    publishDecision "MedicalModel" ["hospital-b-record"]
      jointModel jointEndpoint = .ok (some .deny) := by native_decide

theorem withdrawnSourceBlocksEndpointUse :
    inferDecision "MedicalModel" ["hospital-b-record"] =
      .ok (some .deny) := by native_decide

theorem otherDeploymentTargetDenied :
    publishDecision "MedicalModel" [] jointModel independentEndpoint =
      .ok (some .deny) := by native_decide

theorem withdrawnPublicationGrantDenied :
    publishDecision "MedicalModel" [] jointModel jointEndpoint 2 =
      .ok (some .deny) := by native_decide

theorem unreviewedModelDenied :
    publishDecision "MedicalModel" [] jointModel jointEndpoint 1 false =
      .ok (some .deny) := by native_decide

theorem clinicalUseRequiresPatientBinding :
    inferDecision "MedicalModel" [] false =
      .ok (some .deny) := by native_decide

theorem incidentBlocksPublication :
    publishDecision "ModelIncident" [] jointModel jointEndpoint =
      .ok (some .deny) := by native_decide

theorem incidentBlocksInference :
    inferDecision "ModelIncident" [] = .ok (some .deny) := by native_decide

theorem incidentLeavesTrainingOwner :
    trainDecisionAt "ModelIncident" [] jointDataset jointRun =
      .ok (some .allow) := by native_decide

theorem recoveryRestoresPublication :
    publishDecision "Recovered" [] jointModel jointEndpoint =
      .ok (some .allow) := by native_decide

theorem selectedModelCannotBorrowOtherAvailability :
    (do
      let facts ← factsFor "hospital-a-model-v1" [] "r1" "publication"
      return decision "MedicalModel" "r1" <|
        request publisher publish jointModel
          { facts with approvalValid := true, modelReviewed := true, sinkBound := true }) =
      (.ok (some .deny) : Except CedarPooSpec.Data.Lineage.Error (Option Decision)) := by
  native_decide

theorem staleLineageRevisionDenied :
    (do
      let facts ← factsFor "joint-model-v1" [] "r1" "publication"
      return decision "MedicalModel" "r2" <|
        request publisher publish jointModel
          { facts with approvalValid := true, modelReviewed := true, sinkBound := true }) =
      (.ok (some .deny) : Except CedarPooSpec.Data.Lineage.Error (Option Decision)) := by
  native_decide

end CedarPooSpec.ModelStewardshipTest
