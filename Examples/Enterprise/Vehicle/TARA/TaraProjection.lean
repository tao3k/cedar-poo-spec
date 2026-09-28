import Examples.Enterprise.Vehicle.Mission.SuccessorBoundary

/-!
An illustrative TARA work-product index over the existing mission case.
The descriptions identify assets, damage scenarios, and treatment owners;
they do not assign ISO/SAE 21434 impact, feasibility, or risk ratings.
-/

namespace CedarPooSpec.TaraProjectionExample

open CedarPooSpec.SuccessorBoundaryExample

structure RiskAxis where
  id : String
  asset : String
  damageScenario : String
  treatmentOwner : String

def riskAxes : List RiskAxis := [
  ⟨"collision", "vehicle motion", "future collision", "Platform"⟩,
  ⟨"checkpoint", "mission route", "required checkpoint becomes unreachable", "Mission"⟩,
  ⟨"restricted", "allowed operating area", "future route enters a restricted region", "Mission"⟩,
  ⟨"budget", "mission reserve", "future route exhausts remaining budget", "Mission"⟩,
  ⟨"clear", "control case", "no modeled damage", "Base"⟩,
  ⟨"unbound", "decision evidence", "witness belongs to another proposal", "Evidence"⟩,
  ⟨"stale", "decision evidence", "once-valid witness is replayed too late", "Current"⟩]

def rootNames : List String := matrixExpectations.map Prod.fst
def projectedCells : List (String × String) :=
  rootNames.flatMap fun root => riskAxes.map fun risk => (root, risk.id)
def ownerEditCount : Nat :=
  model.modules.foldl (fun total module => total + module.edits.length) 0
def emittedPolicyOccurrences : Nat :=
  rootNames.foldl (fun total root =>
    total + ((model.compile root).toOption.map List.length).getD 0) 0

theorem projectionMatchesExecutableMatrix :
    riskAxes.map RiskAxis.id = matrixColumns.map Prod.fst ∧
    projectedCells.length = matrixCases.length ∧
    projectedCells.length = 42 ∧
    ownerEditCount = 6 ∧
    emittedPolicyOccurrences = 18 := by
  native_decide

theorem everyProjectedDecisionChecked :
    matrixCases.all (fun (_, root, action, candidate, expected) =>
      authorized root action candidate == expected) = true := matrixExact

end CedarPooSpec.TaraProjectionExample
