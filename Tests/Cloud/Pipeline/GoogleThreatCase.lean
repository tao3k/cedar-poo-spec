import Examples.Cloud.Pipeline.GoogleThreatCase
import Examples.Cloud.Pipeline.Deployment

namespace CedarPooSpec.Cloud.Pipeline.GoogleThreatCaseTest

open CedarPooSpec.Cloud.Pipeline.GoogleThreatCase
open CedarPooSpec.PolicyModules

theorem schemaValid : schema.validateWellFormed.isOk = true := by native_decide

theorem stageDecisionsExact :
    cases.all (fun (_, root, resource, facts, expected) =>
      allowed root resource facts == expected) = true := by native_decide

theorem allDiagnosticRootsValidate :
    ["Base", "SourcePrecheck", "SourceBound", "DependencyBound", "RunnerBound", "ArtifactBound",
      "ReleaseReady", "Quarantined", "Recovered", "CanaryRelease"].all (fun root =>
        (CedarPooSpec.PolicyJson.publish model root schema).isOk) = true := by
  native_decide

theorem selectedDeploymentRootsValidate :
    [Deployment.Root.releaseReady, .quarantined, .recovered].all
      (fun root => (Deployment.publish root).isOk) = true := by native_decide

theorem independentStageOwnersPresent :
    ((model.objectAt "ReleaseReady").toOption.get
      (by native_decide)).plan.precedence =
        ["ReleaseReady", "ArtifactBound", "RunnerBound", "DependencyBound",
          "SourceBound", "SourcePrecheck", "Base", "Source", "SourceControl",
          "Dependencies", "Runner", "Artifact", "Provenance"] := by
  native_decide

theorem sourceControlAddsOnlyItsOwnedPolicy :
    ((model.compileRevision "SourcePrecheck" "SourceBound").toOption.get
      (by native_decide)).changedPolicyIds = [sourceControl.policyId] := by
  native_decide

theorem prototypeBranchOverrideKeepsParent :
    productionProfile.read .branch = some "main" ∧
    canaryProfile.read .branch = some "release-candidate" ∧
    canaryProfile.plan.precedence = ["CanarySource", "ProductionSource"] ∧
    productionControl.protectedBranch = "main" ∧
    canaryControl.protectedBranch = "release-candidate" := by
  native_decide

theorem canaryRevisionTouchesOnlySourceControl :
    ((model.compileRevision "ReleaseReady" "CanaryRelease").toOption.get
      (by native_decide)).changedPolicyIds = [sourceControl.policyId] := by
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
