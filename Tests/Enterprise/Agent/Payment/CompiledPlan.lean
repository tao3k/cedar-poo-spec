import Examples.Enterprise.Agent.Payment.AgentPayment

/-! Regression checks for C4 slot composition across a three-owner payment
hierarchy. The scenario itself belongs to `Examples`. -/

namespace CedarPooSpec.AgentPaymentCompiledPlanTest

open CedarPooSpec.AgentPaymentExample

theorem inheritedPermit :
    policySlot "PaymentGoverned" paymentBase.id = some (some paymentBase) := by
  native_decide

theorem siblingAccountVeto :
    policySlot "PaymentGoverned" accountVeto.id = some (some accountVeto) := by
  native_decide

theorem siblingAmountVeto :
    policySlot "PaymentGoverned" amountVeto.id = some (some amountVeto) := by
  native_decide

theorem siblingOriginVeto :
    policySlot "PaymentGoverned" originVeto.id = some (some originVeto) := by
  native_decide

theorem freezeAndRemove :
    freezeSlotEvolution = [none, some (some frozenAccountVeto), some none] := by
  native_decide

theorem restoredPublication :
    (paymentModel.compile "PaymentRestored" ==
      paymentModel.compile "PaymentGoverned") = true := by
  exact restoredPoliciesEqualGoverned

end CedarPooSpec.AgentPaymentCompiledPlanTest
