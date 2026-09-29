import CedarPooSpec.Governance.Veto

/-!
Bind a Cedar data-use decision to the selected artifact and the Host's
lineage snapshot. The Host projects availability from a validated catalog,
authenticates the revision, and rechecks both before the actual effect.
-/

namespace CedarPooSpec.Data

open Cedar.Spec CedarPooSpec.PolicyModules CedarPooSpec.Governance

structure LineageUse where
  policyId : PolicyID
  actionScope : ActionScope
  resourceArtifactAttribute : String := "artifactId"
  resourceRevisionAttribute : String := "lineageRevision"
  targetFact : String := "targetArtifact"
  revisionFact : String := "lineageRevision"
  availableFact : String := "lineageAvailable"

private def attr (source : Var) (name : String) : Expr :=
  .getAttr (.var source) name

def LineageUse.control (use : LineageUse) : Veto :=
  { policyId := use.policyId, actionScope := use.actionScope,
    denyWhen := .or
      (.unaryApp .not <| .binaryApp .eq
        (attr .resource use.resourceArtifactAttribute)
        (attr .context use.targetFact))
      (.or (.unaryApp .not <| .binaryApp .eq
          (attr .resource use.resourceRevisionAttribute)
          (attr .context use.revisionFact))
        (.unaryApp .not <| attr .context use.availableFact)) }

def LineageUse.edit (use : LineageUse) (change : Veto.Change) : Edit :=
  use.control.edit change

end CedarPooSpec.Data
