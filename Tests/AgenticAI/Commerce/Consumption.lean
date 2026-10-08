import Tests.AgenticAI.Commerce.Projection

namespace CedarPooSpec.AgenticAI.CommerceConsumptionTest
open CedarPooSpec.AgenticAI.Commerce
open CedarPooSpec.AgenticAI.CommerceProjectionTest

theorem credentialReissueCannotConsumeAgain :
    consumptionAfter.claim 2 sharedAfter { offer with verified := true } sharedPurchase
      { dispatch with credential := { committedCredential with credentialId := "reissued" } } =
      none := by decide
theorem changedProviderCannotConsumeAgain :
    consumptionAfter.claim 2 sharedAfter { offer with verified := true } sharedPurchase
      { dispatch with providerId := "another-provider", idempotencyKey := "another-key" } =
      none := by decide
theorem staleConsumptionRevisionDenied :
    consumptionBefore.claim 0 sharedAfter { offer with verified := true } sharedPurchase dispatch =
      none := by decide
theorem revokedAncestorCannotConsume :
    consumptionBefore.claim 1 (sharedAfter.revoke mandate.mandateId)
      { offer with verified := true } sharedPurchase dispatch = none := by decide

def receipt : ProviderReceipt :=
  { providerId := "processor", request := dispatch, outcome := .succeeded,
    reference := "payment-42", verified := true }
theorem exactSignedProviderReceiptAccepted : dispatch.acceptsReceipt receipt = true := by decide
theorem differentCheckoutReceiptDenied :
    dispatch.acceptsReceipt { receipt with
      request := { dispatch with credential := { committedCredential with
        receipt := { committedCredential.receipt with committedContentId := "other-cid" } } } } =
      false := by decide
theorem differentProviderReceiptDenied :
    dispatch.acceptsReceipt { receipt with providerId := "other" } = false := by decide
theorem unsignedProviderReceiptDenied :
    dispatch.acceptsReceipt { receipt with verified := false } = false := by decide
end CedarPooSpec.AgenticAI.CommerceConsumptionTest
