import Examples.Enterprise.Agent.DataFlow.AgentDataFlow

/-! The Data Flow scenario constructs policy modules by dispatching on two
independent C4 profiles. Cedar remains the request-time authorizer. -/

namespace CedarPooSpec.AgentDataFlowDispatchTest

open CedarPooSpec.AgentDataFlowExample
open CedarPooSpec.PolicyModules

def classifiedBranchExact : Bool :=
  match controlEdits "Internal" "Destination" with
  | .ok [.extend policy] => decide (policy = classificationVeto)
  | _ => false

def reviewBranchExact : Bool :=
  match controlEdits "Source" "Public" with
  | .ok [.extend policy] => decide (policy = reviewVeto)
  | _ => false

def inheritedPairExact : Bool :=
  match controlEdits "Restricted" "PartnerPublic" with
  | .ok [.extend reviewed, .extend classified] =>
      decide (reviewed = reviewVeto) &&
      decide (classified = classificationVeto)
  | _ => false

def inheritedPrecedenceExact : Bool :=
  match LeanPoo.C4.linearize sourceClasses "Restricted",
      LeanPoo.C4.linearize destinationClasses "PartnerPublic" with
  | .ok sourceOrder, .ok destinationOrder =>
      sourceOrder == ["Restricted", "Internal", "Regulated", "Source"] &&
      destinationOrder == ["PartnerPublic", "Public", "Destination"]
  | _, _ => false

def invalidProfileTyped : Bool :=
  match controlEdits "Unknown" "Public" with
  | .error (.sourceProfile _) => true
  | _ => false

theorem exactDispatch :
    classifiedBranchExact = true ∧ reviewBranchExact = true ∧
    inheritedPairExact = true ∧ inheritedPrecedenceExact = true ∧
    invalidProfileTyped = true := by
  native_decide

theorem generatedBranchesRemainCedarPolicies :
    governedPolicyIds = true ∧ casesExact = true ∧ casesErrorFree = true := by
  exact ⟨governedPolicyIdsFully, casesExactFully, casesErrorFreeFully⟩

/-- Equality below is not vacuous: both roots compile successfully. -/
theorem bothConstructionRootsCompile :
    (dataModel.compile "PublishDispatched").isOk = true ∧
      (dataModel.compile "PublishGoverned").isOk = true := by
  native_decide

/-- Two POO construction routes produce the same ordered Cedar policy list,
    which is stronger than equal decisions on the current request corpus. -/
theorem orderedPoliciesEqual :
    (dataModel.compile "PublishDispatched").toOption =
      (dataModel.compile "PublishGoverned").toOption := by
  native_decide

def sameDecisions : Bool := cases.all fun (_, readRoot, _, source, repo,
    origin, approver, approved, _) =>
  authorizeFlow readRoot "PublishDispatched" source repo origin approver approved ==
    authorizeFlow readRoot "PublishGoverned" source repo origin approver approved

theorem dispatchedDecisionsExact : sameDecisions = true := by native_decide

theorem dispatchedRootValidated : allRootsValidated = true :=
  allRootsValidatedFully

end CedarPooSpec.AgentDataFlowDispatchTest
