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
  | .ok [.extend classified, .extend reviewed] =>
      decide (classified = classificationVeto) &&
      decide (reviewed = reviewVeto)
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

end CedarPooSpec.AgentDataFlowDispatchTest
