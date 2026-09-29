import Examples.Health.ModelStewardship

/-! Reuse the exact requests checked in Lean for official Cedar replay. -/

namespace CedarPooSpec.ModelStewardshipExample.ReplayExport

open Cedar.Spec CedarPooSpec.ModelStewardshipExample

private def checked (result : Except CedarPooSpec.Data.Lineage.Error Request) :
    Except String Request :=
  result.mapError (fun _ => "model lineage catalog rejected the request")

def manifest : Except String Lean.Json := do
  let baselineTrain ← checked <| trainRequest [] jointDataset jointRun
  let swappedSource ← checked <| trainRequest [] independentModel jointRun
  let revokedTrain ← checked <| trainRequest [] jointDataset jointRun 2
  let withdrawnTrain ← checked <|
    trainRequest ["hospital-b-record"] jointDataset jointRun
  let baselinePublish ← checked <| publishRequest [] jointModel jointEndpoint
  let otherSink ← checked <| publishRequest [] jointModel independentEndpoint
  let unreviewed ← checked <| publishRequest [] jointModel jointEndpoint 1 false
  let withdrawnPublish ← checked <|
    publishRequest ["hospital-b-record"] jointModel jointEndpoint
  let baselineInfer ← checked <| inferRequest []
  let wrongPatient ← checked <| inferRequest [] false
  let withdrawnInfer ← checked <| inferRequest ["hospital-b-record"]
  let cases : List (String × String × Request) := [
    ("train-approved", "MedicalModel", baselineTrain),
    ("train-swapped-source", "MedicalModel", swappedSource),
    ("train-revoked-grant", "MedicalModel", revokedTrain),
    ("train-withdrawn-source", "MedicalModel", withdrawnTrain),
    ("publish-approved", "MedicalModel", baselinePublish),
    ("publish-other-sink", "MedicalModel", otherSink),
    ("publish-unreviewed", "MedicalModel", unreviewed),
    ("publish-withdrawn-source", "MedicalModel", withdrawnPublish),
    ("infer-approved", "MedicalModel", baselineInfer),
    ("infer-wrong-patient", "MedicalModel", wrongPatient),
    ("infer-withdrawn-source", "MedicalModel", withdrawnInfer),
    ("incident-training", "ModelIncident", baselineTrain),
    ("incident-publish", "ModelIncident", baselinePublish),
    ("incident-infer", "ModelIncident", baselineInfer),
    ("recovered-publish", "Recovered", baselinePublish),
    ("recovered-infer", "Recovered", baselineInfer)]
  let rows ← cases.mapM fun (name, root, req) =>
    CedarPooSpec.PolicyJson.authorizationCase name root model root req (entities "r1")
  return Lean.Json.mkObj [("cases", Lean.toJson rows)]

end CedarPooSpec.ModelStewardshipExample.ReplayExport
