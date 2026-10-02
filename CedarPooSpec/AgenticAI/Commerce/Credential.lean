import CedarPooSpec.AgenticAI.Commerce.Delegation

/-!
An exact, agent-specific credential admission boundary. `verified` remains a
Host assertion about the credential issuer and signature, not a cryptographic
verification performed by Lean. The issuer must enforce the credential's use
rules before any external payment effect.
-/

namespace CedarPooSpec.AgenticAI.Commerce

/-- The issuer attests a credential for one reserved purchase and checkout.
    Storing complete terms here makes substitution visible to the pure model. -/
structure Credential where
  credentialId : String
  issuerId : String
  mandate : Mandate
  purchaseId : String
  terms : PurchaseTerms
  expiresAt : Nat
  verified : Bool
  deriving DecidableEq, Repr

def Budget.acceptsCredential (state : Budget)
    (offer : MerchantOffer) (purchase : Purchase)
    (credential : Credential) : Bool :=
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

end CedarPooSpec.AgenticAI.Commerce
