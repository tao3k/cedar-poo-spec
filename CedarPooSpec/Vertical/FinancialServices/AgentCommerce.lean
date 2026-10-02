import CedarPooSpec.Vertical.FinancialServices.PaymentOperation

/-!
An agent-commerce admission boundary before any payment instrument is chosen.
The Host authenticates the mandate and merchant offer, supplies their `verified`
flags, and atomically persists the returned budget revision and exact purchase.
This module neither issues a payment credential nor contacts a payment rail.
-/

namespace CedarPooSpec.Vertical.FinancialServices

open Cedar.Spec

/-- A principal delegates bounded purchasing authority to one agent identity.
    The lists are explicit allowlists; an empty list grants no scope. -/
structure AgentCommerceMandate where
  mandateId : String
  principal : EntityUID
  agentId : String
  allowedMerchants : List String
  allowedProducts : List String
  asset : String
  perPurchaseCap : Nat
  totalCap : Nat
  policyEpoch : Nat
  expiresAt : Nat
  verified : Bool
  deriving DecidableEq, Repr

/-- Exact seller terms selected by the agent. Amounts are integer minor units;
    an asset adapter must define the unit and supported asset before use. -/
structure AgentPurchaseTerms where
  merchantId : String
  productId : String
  offerId : String
  amountMinor : Nat
  asset : String
  deriving DecidableEq, Repr

/-- The Host asserts that these terms came from the named merchant. -/
structure AgentMerchantOffer where
  terms : AgentPurchaseTerms
  expiresAt : Nat
  verified : Bool
  deriving DecidableEq, Repr

/-- An agent's proposed purchase, bound to an exact merchant offer. -/
structure AgentPurchase where
  purchaseId : String
  mandateId : String
  agentId : String
  terms : AgentPurchaseTerms
  deriving DecidableEq, Repr

/-- Durable Host state for one mandate. The Host must compare `revision`
    atomically before making any later external payment effect. -/
structure AgentCommerceBudget where
  mandate : AgentCommerceMandate
  now : Nat
  spentMinor : Nat
  reservations : List AgentPurchase
  revoked : Bool
  revision : Nat
  deriving DecidableEq, Repr

def AgentCommerceBudget.admits (state : AgentCommerceBudget)
    (mandate : AgentCommerceMandate) (offer : AgentMerchantOffer)
    (purchase : AgentPurchase) : Bool :=
  mandate.verified && offer.verified && !state.revoked &&
  !mandate.mandateId.isEmpty && !mandate.agentId.isEmpty &&
  !purchase.purchaseId.isEmpty &&
  decide (state.mandate = mandate) &&
  purchase.mandateId == mandate.mandateId &&
  purchase.agentId == mandate.agentId &&
  state.now < mandate.expiresAt && state.now < offer.expiresAt &&
  decide (purchase.terms = offer.terms) &&
  !offer.terms.merchantId.isEmpty && !offer.terms.productId.isEmpty &&
  !offer.terms.offerId.isEmpty && !offer.terms.asset.isEmpty &&
  mandate.allowedMerchants.contains offer.terms.merchantId &&
  mandate.allowedProducts.contains offer.terms.productId &&
  offer.terms.asset == mandate.asset &&
  offer.terms.amountMinor > 0 &&
  offer.terms.amountMinor <= mandate.perPurchaseCap &&
  state.spentMinor + offer.terms.amountMinor <= mandate.totalCap &&
  !state.reservations.any (fun previous =>
    previous.purchaseId == purchase.purchaseId ||
    (previous.terms.merchantId == offer.terms.merchantId &&
     previous.terms.offerId == offer.terms.offerId))

/-- Reserve exact purchase terms and cumulative spend in one pure transition.
    It is effective only if the Host persists the revision with a compare-and-swap. -/
def AgentCommerceBudget.reserve (state : AgentCommerceBudget)
    (mandate : AgentCommerceMandate) (offer : AgentMerchantOffer)
    (purchase : AgentPurchase) : Option AgentCommerceBudget :=
  if state.admits mandate offer purchase then
    some { state with
      spentMinor := state.spentMinor + offer.terms.amountMinor,
      reservations := purchase :: state.reservations,
      revision := state.revision + 1 }
  else none

theorem deniedMandateCannotReserve (state : AgentCommerceBudget)
    (mandate : AgentCommerceMandate) (offer : AgentMerchantOffer)
    (purchase : AgentPurchase) (h : mandate.verified = false) :
    state.reserve mandate offer purchase = none := by
  simp [AgentCommerceBudget.reserve, AgentCommerceBudget.admits, h]

end CedarPooSpec.Vertical.FinancialServices
