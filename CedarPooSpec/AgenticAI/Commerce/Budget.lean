import Cedar.Spec.Entities

/-!
An agentic AI commerce admission boundary before any payment instrument is chosen.
The Host authenticates the mandate and merchant offer, supplies their `verified`
flags, and atomically persists the returned budget revision and exact purchase.
This module neither issues a payment credential nor contacts a payment rail.
-/

namespace CedarPooSpec.AgenticAI.Commerce

open Cedar.Spec

/-- A principal delegates bounded purchasing authority to one agent identity.
    The lists are explicit allowlists; an empty list grants no scope. -/
structure Mandate where
  mandateId : String
  principal : EntityUID
  agentId : String
  /-- The principal binds an agent verification key to this grant. The Host
      validates its encoding and possession before marking the grant verified. -/
  agentPublicKey : String
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
structure PurchaseTerms where
  merchantId : String
  productId : String
  offerId : String
  checkoutCommitment : String
  amountMinor : Nat
  asset : String
  deriving DecidableEq, Repr

/-- The Host asserts that these terms came from the named merchant. -/
structure MerchantOffer where
  terms : PurchaseTerms
  expiresAt : Nat
  verified : Bool
  deriving DecidableEq, Repr

/-- An agent's proposed purchase, bound to an exact merchant offer. -/
structure Purchase where
  purchaseId : String
  mandateId : String
  agentId : String
  terms : PurchaseTerms
  deriving DecidableEq, Repr

/-- Durable Host state for one mandate. The Host must compare `revision`
    atomically before making any later external payment effect. -/
structure Budget where
  mandate : Mandate
  now : Nat
  spentMinor : Nat
  reservations : List Purchase
  revoked : Bool
  revision : Nat
  deriving DecidableEq, Repr

def Budget.admits (state : Budget)
    (mandate : Mandate) (offer : MerchantOffer)
    (purchase : Purchase) : Bool :=
  mandate.verified && offer.verified && !state.revoked &&
  !mandate.mandateId.isEmpty && !mandate.agentId.isEmpty &&
  !mandate.agentPublicKey.isEmpty &&
  !purchase.purchaseId.isEmpty &&
  decide (state.mandate = mandate) &&
  purchase.mandateId == mandate.mandateId &&
  purchase.agentId == mandate.agentId &&
  state.now < mandate.expiresAt && state.now < offer.expiresAt &&
  decide (purchase.terms = offer.terms) &&
  !offer.terms.merchantId.isEmpty && !offer.terms.productId.isEmpty &&
  !offer.terms.offerId.isEmpty && !offer.terms.checkoutCommitment.isEmpty &&
  !offer.terms.asset.isEmpty &&
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
def Budget.reserve (state : Budget)
    (mandate : Mandate) (offer : MerchantOffer)
    (purchase : Purchase) : Option Budget :=
  if state.admits mandate offer purchase then
    some { state with
      spentMinor := state.spentMinor + offer.terms.amountMinor,
      reservations := purchase :: state.reservations,
      revision := state.revision + 1 }
  else none

theorem deniedMandateCannotReserve (state : Budget)
    (mandate : Mandate) (offer : MerchantOffer)
    (purchase : Purchase) (h : mandate.verified = false) :
    state.reserve mandate offer purchase = none := by
  simp [Budget.reserve, Budget.admits, h]

end CedarPooSpec.AgenticAI.Commerce
