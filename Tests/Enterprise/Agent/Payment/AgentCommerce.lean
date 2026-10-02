import CedarPooSpec.Vertical.FinancialServices.AgentCommerce
import Examples.Enterprise.Agent.Payment.AgentPayment

namespace CedarPooSpec.AgentCommerceTest

open CedarPooSpec.Vertical.FinancialServices
open CedarPooSpec.AgentDelegationExample
open CedarPooSpec.AgentPaymentExample

def mandate : AgentCommerceMandate :=
  { mandateId := "trip-2026", principal := approvedAccount,
    agentId := "travel-agent-7", allowedMerchants := ["ride-provider"],
    allowedProducts := ["airport-ride"], asset := "HKD",
    perPurchaseCap := 50000, totalCap := 80000,
    policyEpoch := 4, expiresAt := 30, verified := true }

def terms : AgentPurchaseTerms :=
  { merchantId := "ride-provider", productId := "airport-ride",
    offerId := "quote-42", amountMinor := 30000, asset := "HKD" }

def offer : AgentMerchantOffer :=
  { terms, expiresAt := 20, verified := true }

def purchase : AgentPurchase :=
  { purchaseId := "buy-1", mandateId := mandate.mandateId,
    agentId := mandate.agentId, terms }

def budget : AgentCommerceBudget :=
  { mandate, now := 10, spentMinor := 0, reservations := [],
    revoked := false, revision := 0 }

def reserved : AgentCommerceBudget :=
  { budget with spentMinor := 30000, reservations := [purchase], revision := 1 }

theorem matchingOfferReserves :
    budget.reserve mandate offer purchase = some reserved := by decide
theorem samePurchaseCannotReplay :
    reserved.reserve mandate offer purchase = none := by decide
theorem sameOfferCannotUseNewPurchaseId :
    reserved.reserve mandate offer { purchase with purchaseId := "buy-2" } = none := by decide
theorem wrongAgentDenied :
    budget.reserve mandate offer { purchase with agentId := "other-agent" } = none := by decide
theorem wrongMandateDenied :
    budget.reserve mandate offer { purchase with mandateId := "other-mandate" } = none := by decide
theorem unverifiedMandateDenied :
    budget.reserve { mandate with verified := false } offer purchase = none := by decide
theorem changedPrincipalMandateDenied :
    budget.reserve { mandate with principal := reserveAccount } offer purchase = none := by decide
theorem widenedMerchantMandateDenied :
    budget.reserve { mandate with allowedMerchants := ["ride-provider", "other"] }
      offer purchase = none := by decide
theorem unverifiedOfferDenied :
    budget.reserve mandate { offer with verified := false } purchase = none := by decide
theorem changedMerchantDenied :
    budget.reserve mandate offer
      { purchase with terms := { terms with merchantId := "attacker" } } = none := by decide
theorem changedPriceDenied :
    budget.reserve mandate offer
      { purchase with terms := { terms with amountMinor := 31000 } } = none := by decide
theorem changedProductDenied :
    budget.reserve mandate offer
      { purchase with terms := { terms with productId := "hotel" } } = none := by decide
theorem changedQuoteDenied :
    budget.reserve mandate offer
      { purchase with terms := { terms with offerId := "quote-43" } } = none := by decide
theorem changedAssetDenied :
    budget.reserve mandate offer
      { purchase with terms := { terms with asset := "USD" } } = none := by decide
theorem outOfScopeMerchantDenied :
    budget.reserve mandate { offer with terms := { terms with merchantId := "other" } }
      { purchase with terms := { terms with merchantId := "other" } } = none := by decide
theorem outOfScopeProductDenied :
    budget.reserve mandate { offer with terms := { terms with productId := "hotel" } }
      { purchase with terms := { terms with productId := "hotel" } } = none := by decide
theorem perPurchaseCapEnforced :
    budget.reserve mandate { offer with terms := { terms with amountMinor := 50001 } }
      { purchase with terms := { terms with amountMinor := 50001 } } = none := by decide
theorem cumulativeCapEnforced :
    ({ budget with spentMinor := 60000 }).reserve mandate offer purchase = none := by decide
def secondTerms : AgentPurchaseTerms :=
  { terms with offerId := "quote-43", amountMinor := 50000 }
def secondOffer : AgentMerchantOffer :=
  { offer with terms := secondTerms }
def secondPurchase : AgentPurchase :=
  { purchase with purchaseId := "buy-2", terms := secondTerms }
theorem twoPurchasesCanUseExactTotalCap :
    (reserved.reserve mandate secondOffer secondPurchase).isSome = true := by decide
theorem zeroPriceDenied :
    budget.reserve mandate { offer with terms := { terms with amountMinor := 0 } }
      { purchase with terms := { terms with amountMinor := 0 } } = none := by decide
theorem revokedMandateDenied :
    ({ budget with revoked := true }).reserve mandate offer purchase = none := by decide
theorem stalePolicyEpochDenied :
    ({ budget with mandate := { mandate with policyEpoch := 5 } }).reserve
      mandate offer purchase = none := by decide
theorem expiredOfferDenied :
    ({ budget with now := 20 }).reserve mandate offer purchase = none := by decide
theorem expiredMandateDenied :
    ({ budget with now := 30 }).reserve mandate
      { offer with expiresAt := 40 } purchase = none := by decide

end CedarPooSpec.AgentCommerceTest
