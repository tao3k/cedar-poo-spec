import CedarPooSpec.AuthorizationDeltaRelease
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
  let .ok reviewed ← analyzeAndCapture model "DualHold" "RiskReleased"
      "ComplianceReleased" "JointRelease" paymentSchema 7
    | throw (IO.userError "joint-release interaction analysis failed")
  let report := reviewed.analysis
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
  if !(reviewed.snapshot.currentPolicies model paymentSchema 7).isOk then
    throw (IO.userError "unchanged reviewed snapshot was rejected")
  match reviewed.noGainCurrentPolicies model paymentSchema 7 with
  | .error .requiresReview => pure ()
  | _ => throw (IO.userError "joint authorization gain bypassed review")
  match reviewed.snapshot.currentPolicies model paymentSchema 8 with
  | .error .epochChanged => pure ()
  | _ => throw (IO.userError "stale Host policy epoch was admitted")
  let changedSchema := { paymentSchema with acts := Cedar.Data.Map.empty }
  match reviewed.snapshot.currentPolicies model changedSchema 7 with
  | .error .schemaChanged => pure ()
  | _ => throw (IO.userError "changed Cedar schema was admitted")
  let changedOwner : Model := { modules := model.modules.map fun module =>
    if module.name == "DualHold" then
      { module with edits := module.edits ++ [.overlay paymentBase] }
    else module }
  if !(reviewed.snapshot.combined.currentPolicies changedOwner).isOk then
    throw (IO.userError "owner-only mutation changed Cedar policy bodies")
  match reviewed.snapshot.currentPolicies changedOwner paymentSchema 7 with
  | .error .modelChanged => pure ()
  | _ => throw (IO.userError "changed POO edit provenance was admitted")
  let .ok unrelated := model.extend "UnrelatedOwner" "PaymentBase" []
    | throw (IO.userError "could not add an unrelated POO owner")
  if !(reviewed.snapshot.currentPolicies unrelated paymentSchema 7).isOk then
    throw (IO.userError "unrelated owner unnecessarily invalidated review")
  let .ok retained := model.extend "ComplianceRetained" "DualHold" []
    | throw (IO.userError "could not stage retained compliance hold")
  let .ok safeModel := retained.mix "RiskOnlyReview"
      ["RiskReleased", "ComplianceRetained"]
    | throw (IO.userError "could not compose the no-gain review root")
  let .ok safeReview ← analyzeAndCapture safeModel "DualHold" "RiskReleased"
      "ComplianceRetained" "RiskOnlyReview" paymentSchema 11
    | throw (IO.userError "no-gain release analysis failed")
  let .noCombinedGain := safeReview.analysis.outcome
    | throw (IO.userError "retaining one hold unexpectedly grants access")
  if !(safeReview.noGainCurrentPolicies safeModel paymentSchema 11).isOk then
    throw (IO.userError "current no-gain review was rejected")
  match safeReview.noGainCurrentPolicies safeModel paymentSchema 12 with
  | .error .epochChanged => pure ()
  | _ => throw (IO.userError "stale no-gain review was admitted")
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
    ("release_requires_review", Lean.toJson true),
    ("stale_epoch_rejected", Lean.toJson true),
    ("changed_schema_rejected", Lean.toJson true),
    ("owner_only_change_rejected", Lean.toJson true),
    ("unrelated_owner_reused", Lean.toJson true),
    ("safe_release_current", Lean.toJson true),
    ("safe_release_stale_rejected", Lean.toJson true),
    ("manifest", Lean.Json.mkObj [("cases", Lean.toJson cases)])]

end CedarPooSpec.AgentPaymentJointRelease

def main : IO Unit := do
  IO.println (← CedarPooSpec.AgentPaymentJointRelease.run).compress
