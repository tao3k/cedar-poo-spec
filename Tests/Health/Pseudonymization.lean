import Examples.Health.Pseudonymization

/-! Executable regression checks for the hospital composition scenario. -/

namespace CedarPooSpec.PseudonymizationTest

open Cedar.Spec CedarPooSpec.PseudonymizationExample

theorem scenarioConformsFully : scenarioConforms = true := by native_decide

theorem caseNamesUnique : (cases.map (fun (name, _, _, _) => name)).Nodup := by
  native_decide

theorem composedViewsShareRemovalFully : composedViewsShareRemoval = true := by
  native_decide

theorem compositionIsLocalFully : compositionIsLocal = true := by native_decide

theorem incidentOnlyAddsAgentVetoFully : incidentOnlyAddsAgentVeto = true := by
  native_decide

/-- Recovery removes the inherited incident veto while retaining the other
    owner and privacy policies. -/
theorem recoveryWithdrawsIncidentVeto :
    (match model.compile recovered.name, model.compile hospitalView.name with
    | .ok policies, .ok baseline =>
      decide (policies = baseline) &&
      !policies.any (fun p => p.id == incidentControl.policyId) &&
      (isAuthorized (request agent join hospital {}) entities policies).decision == .allow
    | _, _ => false) = true := by
  native_decide

end CedarPooSpec.PseudonymizationTest
