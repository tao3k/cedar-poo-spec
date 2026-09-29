import CedarPooSpec.AuthorizationDeltaInteraction
import CedarPooSpec.PolicyJson
import Examples.Enterprise.Agent.Payment.AgentPayment

/-!
Two independent owners release overlapping holds on an AI-agent payment.
Each branch remains denied; their C4 mix creates an authorization gain.
-/

namespace CedarPooSpec.AgentPaymentJointRelease

open Cedar.Spec CedarPooSpec.PolicyModules CedarPooSpec.AuthorizationDelta
open CedarPooSpec.AgentPaymentExample

def riskHold : Policy := { frozenAccountVeto with id := "risk-payment-hold" }
def complianceHold : Policy := { frozenAccountVeto with id := "compliance-payment-hold" }

def modelResult : Except LeanPoo.C4.Error Model := do
  let base ← paymentModel.extend "DualHold" "PaymentGoverned"
    [.extend riskHold, .extend complianceHold]
  let left ← base.extend "RiskReleased" "DualHold" [.remove riskHold.id]
  let right ← left.extend "ComplianceReleased" "DualHold"
    [.remove complianceHold.id]
  right.mix "JointRelease" ["RiskReleased", "ComplianceReleased"]

def model : Model := modelResult.toOption.get (by native_decide)

private def hasPolicy (root : String) (id : PolicyID) : Bool :=
  match model.compile root with
  | .ok policies => (policies.map Policy.id).contains id
  | .error _ => false

/-- The two native POO removals remain local, while C4 combines both in the
    final root. This is a topology receipt, not an authorization proof. -/
theorem compiledRoots :
    hasPolicy "DualHold" riskHold.id = true ∧
    hasPolicy "DualHold" complianceHold.id = true ∧
    hasPolicy "RiskReleased" complianceHold.id = true ∧
    hasPolicy "ComplianceReleased" riskHold.id = true ∧
    hasPolicy "JointRelease" riskHold.id = false ∧
    hasPolicy "JointRelease" complianceHold.id = false := by
  native_decide

def run : IO Lean.Json := do
  match ← analyzeModelInteraction model "DualHold" "RiskReleased"
      "ComplianceReleased" "PaymentFrozen" paymentSchema with
  | .error (.topology _) => pure ()
  | _ => throw (IO.userError "unrelated root was admitted as a C4 branch mix")
  let .ok report ← analyzeModelInteraction model "DualHold" "RiskReleased"
      "ComplianceReleased" "JointRelease" paymentSchema
    | throw (IO.userError "joint-release interaction analysis failed")
  let .jointOnlyGain gains := report.outcome
    | throw (IO.userError "two individually safe releases did not expose a joint gain")
  let some gain := gains.head?
    | throw (IO.userError "joint gain has no Cedar witness")
  if !report.left.symbolic.noExpansion || !report.right.symbolic.noExpansion ||
      report.combined.symbolic.noExpansion ||
      gain.combined.beforeResponse.decision != .deny ||
      gain.combined.afterResponse.decision != .allow ||
      gain.leftResponse.decision != .deny || gain.rightResponse.decision != .deny ||
      !gain.combined.beforeResponse.erroringPolicies.isEmpty ||
      !gain.combined.afterResponse.erroringPolicies.isEmpty ||
      !gain.leftResponse.erroringPolicies.isEmpty ||
      !gain.rightResponse.erroringPolicies.isEmpty then
    throw (IO.userError "joint-only decision receipt is inconsistent")
  let some riskChange := report.left.changes.find? (·.id == riskHold.id)
    | throw (IO.userError "risk release lost POO provenance")
  let some complianceChange := report.right.changes.find? (·.id == complianceHold.id)
    | throw (IO.userError "compliance release lost POO provenance")
  let some riskEdit := riskChange.afterEdits.getLast?
    | throw (IO.userError "risk removal missing from edit trail")
  let some complianceEdit := complianceChange.afterEdits.getLast?
    | throw (IO.userError "compliance removal missing from edit trail")
  if riskEdit.moduleName != "RiskReleased" || complianceEdit.moduleName != "ComplianceReleased" then
    throw (IO.userError "joint release edit owner is wrong")
  let request := gain.combined.witness.request
  let entities := gain.combined.witness.entities
  let mut cases := []
  for root in ["DualHold", "RiskReleased", "ComplianceReleased", "JointRelease"] do
    let .ok receipt := CedarPooSpec.PolicyJson.authorizationCase root root model root
        request entities
      | throw (IO.userError s!"cannot export {root} Cedar replay")
    cases := cases ++ [receipt]
  return Lean.Json.mkObj [
    ("left_no_gain", Lean.toJson report.left.symbolic.noExpansion),
    ("right_no_gain", Lean.toJson report.right.symbolic.noExpansion),
    ("joint_gain", Lean.toJson (!report.combined.symbolic.noExpansion)),
    ("left_changes", Lean.toJson report.left.symbolic.changedPolicyIds),
    ("right_changes", Lean.toJson report.right.symbolic.changedPolicyIds),
    ("joint_changes", Lean.toJson report.combined.symbolic.changedPolicyIds),
    ("risk_owner", Lean.toJson riskEdit.moduleName),
    ("compliance_owner", Lean.toJson complianceEdit.moduleName),
    ("manifest", Lean.Json.mkObj [("cases", Lean.toJson cases)])]

end CedarPooSpec.AgentPaymentJointRelease

def main : IO Unit := do
  IO.println (← CedarPooSpec.AgentPaymentJointRelease.run).compress
