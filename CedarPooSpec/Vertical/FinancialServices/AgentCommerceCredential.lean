import CedarPooSpec.Vertical.FinancialServices.AgentCommerceDelegation

/-!
An exact, agent-specific credential admission boundary. `verified` remains a
Host assertion about the credential issuer and signature, not a cryptographic
verification performed by Lean. The issuer must enforce the credential's use
rules before any external payment effect.
-/

namespace CedarPooSpec.Vertical.FinancialServices

/-- The issuer attests a credential for one reserved purchase and checkout.
    Storing complete terms here makes substitution visible to the pure model. -/
structure AgentCommerceCredential where
  credentialId : String
  issuerId : String
  mandate : AgentCommerceMandate
  purchaseId : String
  terms : AgentPurchaseTerms
  expiresAt : Nat
  verified : Bool
  deriving DecidableEq, Repr

def AgentCommerceBudget.acceptsCredential (state : AgentCommerceBudget)
    (offer : AgentMerchantOffer) (purchase : AgentPurchase)
    (credential : AgentCommerceCredential) : Bool :=
  !state.revoked && state.mandate.verified && offer.verified &&
  credential.verified && !credential.credentialId.isEmpty &&
  !credential.issuerId.isEmpty &&
  decide (credential.mandate = state.mandate) &&
  state.reservations.contains purchase &&
  purchase.mandateId == state.mandate.mandateId &&
  purchase.agentId == state.mandate.agentId &&
  credential.purchaseId == purchase.purchaseId &&
  decide (purchase.terms = offer.terms) &&
  decide (credential.terms = purchase.terms) &&
  state.mandate.allowedMerchants.contains purchase.terms.merchantId &&
  state.mandate.allowedProducts.contains purchase.terms.productId &&
  purchase.terms.asset == state.mandate.asset &&
  !purchase.terms.checkoutCommitment.isEmpty &&
  purchase.terms.amountMinor > 0 &&
  purchase.terms.amountMinor <= state.mandate.perPurchaseCap &&
  state.now < state.mandate.expiresAt && state.now < offer.expiresAt &&
  state.now < credential.expiresAt

end CedarPooSpec.Vertical.FinancialServices
