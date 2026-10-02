import CedarPooSpec.Vertical.FinancialServices.AgentCommercePayment
import Examples.Enterprise.Agent.Payment.AgentPayment

namespace CedarPooSpec.AgentCommerceTest

open CedarPooSpec.Vertical.FinancialServices
open CedarPooSpec.AgentDelegationExample
open CedarPooSpec.AgentPaymentExample

def mandate : AgentCommerceMandate :=
  { mandateId := "trip-2026", principal := approvedAccount,
    agentId := "travel-agent-7", agentPublicKey := "agent-key-7",
    allowedMerchants := ["ride-provider"],
    allowedProducts := ["airport-ride"], asset := "HKD",
    perPurchaseCap := 50000, totalCap := 80000,
    policyEpoch := 4, expiresAt := 30, verified := true }

def terms : AgentPurchaseTerms :=
  { merchantId := "ride-provider", productId := "airport-ride",
    offerId := "quote-42", checkoutCommitment := "checkout-42",
    amountMinor := 30000, asset := "HKD" }

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
theorem changedAgentKeyMandateDenied :
    budget.reserve { mandate with agentPublicKey := "other-key" } offer purchase = none := by decide
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
theorem changedCheckoutCommitmentDenied :
    budget.reserve mandate offer
      { purchase with terms := { terms with checkoutCommitment := "checkout-43" } } =
      none := by decide
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

def child : AgentCommerceMandate :=
  { mandate with mandateId := "trip-child", agentId := "booking-agent-8", agentPublicKey := "agent-key-8", perPurchaseCap := 40000, totalCap := 60000, expiresAt := 25 }
def grant : AgentCommerceDelegation :=
  { issuerAgentId := mandate.agentId, parent := mandate,
    child, verified := true }
def grandchild : AgentCommerceMandate :=
  { child with mandateId := "trip-grandchild", agentId := "quote-agent-9", agentPublicKey := "agent-key-9", perPurchaseCap := 35000, totalCap := 50000, expiresAt := 22 }
def secondGrant : AgentCommerceDelegation :=
  { issuerAgentId := child.agentId, parent := child,
    child := grandchild, verified := true }

theorem narrowerChildAccepted :
    AgentCommerceDelegation.resolveChain mandate [grant] = some child := by decide
theorem twoHopAttenuationAccepted :
    AgentCommerceDelegation.resolveChain mandate [grant, secondGrant] =
      some grandchild := by decide
theorem reusedAncestorMandateIdDenied :
    AgentCommerceDelegation.resolveChain mandate
      [grant, { secondGrant with child :=
        { grandchild with mandateId := mandate.mandateId } }] = none := by decide
theorem reusedAncestorAgentIdDenied :
    AgentCommerceDelegation.resolveChain mandate
      [grant, { secondGrant with child :=
        { grandchild with agentId := mandate.agentId } }] = none := by decide
theorem reusedAncestorAgentKeyDenied :
    AgentCommerceDelegation.resolveChain mandate
      [grant, { secondGrant with child :=
        { grandchild with agentPublicKey := mandate.agentPublicKey } }] = none := by decide
theorem widenedMerchantDenied :
    AgentCommerceDelegation.resolveChain mandate
      [{ grant with child := { child with allowedMerchants := ["ride-provider", "other"] } }] =
      none := by decide
theorem increasedChildBudgetDenied :
    AgentCommerceDelegation.resolveChain mandate
      [{ grant with child := { child with totalCap := 80001 } }] = none := by decide
theorem changedChildPrincipalDenied :
    AgentCommerceDelegation.resolveChain mandate
      [{ grant with child := { child with principal := reserveAccount } }] = none := by decide
theorem wrongIssuerDenied :
    AgentCommerceDelegation.resolveChain mandate
      [{ grant with issuerAgentId := "other-agent" }] = none := by decide
theorem reusedParentAgentKeyDenied :
    AgentCommerceDelegation.resolveChain mandate
      [{ grant with child := { child with agentPublicKey := mandate.agentPublicKey } }] =
      none := by decide
theorem parentSubstitutionDenied :
    AgentCommerceDelegation.resolveChain mandate
      [{ grant with parent := { mandate with perPurchaseCap := 60000 } }] = none := by decide
theorem missingHopDenied :
    AgentCommerceDelegation.resolveChain mandate [secondGrant] = none := by decide
theorem unverifiedGrantDenied :
    AgentCommerceDelegation.resolveChain mandate
      [{ grant with verified := false }] = none := by decide

def credential : AgentCommerceCredential :=
  { credentialId := "agent-token-1", issuerId := "credential-provider",
    mandate, purchaseId := purchase.purchaseId, terms,
    expiresAt := 18, verified := true }

theorem exactCredentialAccepted :
    reserved.acceptsCredential offer purchase credential = true := by decide
theorem credentialCannotPrecedeReservation :
    budget.acceptsCredential offer purchase credential = false := by decide
theorem otherAgentCredentialDenied :
    reserved.acceptsCredential offer purchase
      { credential with mandate := child } = false := by decide
theorem otherCheckoutCredentialDenied :
    reserved.acceptsCredential offer purchase
      { credential with terms := { terms with checkoutCommitment := "other-checkout" } } =
      false := by decide
theorem expiredCredentialDenied :
    ({ reserved with now := 18 }).acceptsCredential offer purchase credential = false := by decide
theorem revokedCredentialDenied :
    ({ reserved with revoked := true }).acceptsCredential offer purchase credential = false := by decide
theorem unverifiedCredentialDenied :
    reserved.acceptsCredential offer purchase
      { credential with verified := false } = false := by decide

def cardProfile : AgentCommercePaymentProfile :=
  { origin := admin, instrument := "agent-card-token", network := "card",
    feeCap := "1.0000", verified := true }
def payment : PaymentOperation :=
  { authorityMode := .delegated, payerAccount := approvedAccount, origin := admin,
    instrument := "agent-card-token", beneficiary := terms.merchantId,
    amount := "300.0000", asset := "HKD", network := "card",
    feeCap := "1.0000", mandateRef := mandate.mandateId,
    checkoutCommitment := terms.checkoutCommitment,
    nonce := purchase.purchaseId, proposer := mandate.agentId,
    policyEpoch := mandate.policyEpoch, expiresAt := 18 }
def envelope : AgentCommercePaymentEnvelope :=
  { offer, purchase, credential, payment }

theorem exactPurchaseBindsPayment :
    cardProfile.binds reserved envelope = true := by native_decide
theorem changedPaymentMerchantDenied :
    cardProfile.binds reserved
      { envelope with payment := { payment with beneficiary := "other" } } = false := by native_decide
theorem changedPaymentAmountDenied :
    cardProfile.binds reserved
      { envelope with payment := { payment with amount := "301.0000" } } = false := by native_decide
theorem nonCanonicalPaymentAmountDenied :
    cardProfile.binds reserved
      { envelope with payment := { payment with amount := "300.00" } } = false := by native_decide
theorem changedCheckoutInPaymentDenied :
    cardProfile.binds reserved
      { envelope with payment := { payment with checkoutCommitment := "other" } } = false := by native_decide
theorem changedPaymentNonceDenied :
    cardProfile.binds reserved
      { envelope with payment := { payment with nonce := "buy-2" } } = false := by native_decide
theorem wrongPaymentAgentDenied :
    cardProfile.binds reserved
      { envelope with payment := { payment with proposer := "other-agent" } } = false := by native_decide
theorem expiredPaymentDenied :
    cardProfile.binds reserved
      { envelope with payment := { payment with expiresAt := 21 } } = false := by native_decide

end CedarPooSpec.AgentCommerceTest
