import Examples.Cloud.Pipeline.GoogleThreatCase

namespace CedarPooSpec.Cloud.Pipeline.GoogleThreatCaseTest

open CedarPooSpec.Cloud.Pipeline.GoogleThreatCase
open CedarPooSpec.PolicyModules

theorem schemaValid : schema.validateWellFormed.isOk = true := by native_decide

theorem stageDecisionsExact :
    cases.all (fun (_, root, resource, facts, expected) =>
      allowed root resource facts == expected) = true := by native_decide

theorem allPublishedRootsValidate :
    ["Base", "SourceBound", "DependencyBound", "RunnerBound",
      "ReleaseReady", "Quarantined", "Recovered"].all (fun root =>
        (CedarPooSpec.PolicyJson.publish model root schema).isOk) = true := by
  native_decide

theorem independentStageOwnersPresent :
    ((model.objectAt "ReleaseReady").toOption.get
      (by native_decide)).plan.precedence =
        ["ReleaseReady", "RunnerBound", "DependencyBound", "SourceBound",
          "Base", "Source", "Dependencies", "Runner", "Artifact"] := by
  native_decide

theorem quarantineTouchesOnlyIncidentPolicy :
    ((model.compileRevision "ReleaseReady" "Quarantined").toOption.get
      (by native_decide)).changedPolicyIds = [incident.policyId] := by
  native_decide

theorem recoveryTouchesOnlyIncidentPolicy :
    ((model.compileRevision "Quarantined" "Recovered").toOption.get
      (by native_decide)).changedPolicyIds = [incident.policyId] := by
  native_decide

end CedarPooSpec.Cloud.Pipeline.GoogleThreatCaseTest
