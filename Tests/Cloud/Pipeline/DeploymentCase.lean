import Examples.Cloud.Pipeline.DeploymentCase

namespace CedarPooSpec.Cloud.Pipeline.DeploymentCaseTest

open CedarPooSpec.Cloud.Pipeline.DeploymentCase
open CedarPooSpec.PolicyModules

theorem schemaValid : schema.validateWellFormed.isOk = true := by native_decide

theorem decisionsExact :
    choices.all (fun choice =>
      promotionAllowed choice == choice.expectedPromotion &&
      deploymentAllowed choice == choice.expectedDeployment &&
      admitted choice == (choice.expectedPromotion && choice.expectedDeployment)) = true := by
  native_decide

theorem selectedRootsPublish :
    [Root.ready, .incident, .recovered].all
      (fun root => (publish root).isOk) = true := by native_decide

theorem incidentChangesOnlyTwoOwnedQuarantines :
    ((model.compileRevision "DeploymentReady" "DeploymentIncident").toOption.get
      (by native_decide)).changedPolicyIds =
        [CedarPooSpec.Cloud.Pipeline.GoogleThreatCase.incident.policyId,
          deploymentIncident.policyId] := by
  native_decide

end CedarPooSpec.Cloud.Pipeline.DeploymentCaseTest
