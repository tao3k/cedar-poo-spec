import Examples.Cloud.DataProtection.GoogleSdpRelease

namespace CedarPooSpec.Cloud.DataProtection.GoogleSdpReleaseTest

open CedarPooSpec.Cloud.DataProtection.GoogleSdpRelease
open CedarPooSpec.PolicyModules

theorem selectedRowUsesNamedContext :
    recipe.select row = .ok selectedInput := by native_decide

theorem choiceDecisionsExact :
    choices.all (fun choice =>
      pipelineAllowed choice == choice.expectedPipeline &&
      transformAllowed choice == choice.expectedTransform &&
      admitted choice == (choice.expectedPipeline && choice.expectedTransform)) = true := by
  native_decide

theorem combinedRootsPublish :
    ["CustomerDataRelease", "CustomerIncident", "CustomerRecovered"].all
      (fun root => (CedarPooSpec.PolicyJson.publish model root schema).isOk) = true := by
  native_decide

theorem incidentKeepsRecipeOwner :
    ((model.compileRevision "CustomerDataRelease" "CustomerIncident").toOption.get
      (by native_decide)).changedPolicyIds = ["affected-artifact-quarantine"] := by
  native_decide

end CedarPooSpec.Cloud.DataProtection.GoogleSdpReleaseTest
