import CedarPooSpec.AgenticAI.Commerce.Credential
import CedarPooSpec.AgenticAI.Commerce.Acceptance

/-!
Consumption is unique by budget scope and purchase, across credential reissue
and provider changes. The Host persists the claim before provider release.
Unknown outcomes retain the claim; recovery reads the exact original request.
This pure model executes no storage or payment operation.
-/
namespace CedarPooSpec.AgenticAI.Commerce

structure PaymentDispatch where
  providerId : String
  idempotencyKey : String
  credential : Credential
  authority : RootFence
  deriving DecidableEq, Repr

structure ConsumptionLedger where
  budgetScope : String
  revision : Nat
  requests : List PaymentDispatch
  deriving DecidableEq, Repr

def ConsumptionLedger.hasPurchase (state : ConsumptionLedger) (purchaseId : String) : Bool :=
  state.requests.any (fun request =>
    request.credential.receipt.reservation.purchase.purchaseId == purchaseId)

/-- Phase and credential identity cannot reopen an already consumed purchase. -/
def ConsumptionLedger.claim (state : ConsumptionLedger) (expectedRevision : Nat)
    (budget : SharedBudget) (offer : MerchantOffer) (purchase : Purchase)
    (request : PaymentDispatch) : Option ConsumptionLedger :=
  if state.hasPurchase purchase.purchaseId then none else
  if expectedRevision = state.revision && !request.providerId.isEmpty &&
      !request.idempotencyKey.isEmpty && !request.authority.retired &&
      decide (request.authority.root.budgetScope = state.budgetScope) &&
      decide (request.authority.root.mandateId = budget.root.mandateId) &&
      budget.acceptsCredential state.budgetScope offer purchase request.credential then
    some { state with revision := state.revision + 1, requests := request :: state.requests }
  else none

inductive ProviderOutcome where
  | succeeded | rejected
  deriving DecidableEq, Repr

/-- Unknown is a transport/status result, never a signed successful payment. -/
structure ProviderReceipt where
  providerId : String
  request : PaymentDispatch
  outcome : ProviderOutcome
  reference : String
  verified : Bool
  deriving DecidableEq, Repr

def PaymentDispatch.acceptsReceipt (request : PaymentDispatch)
    (receipt : ProviderReceipt) : Bool :=
  receipt.verified && receipt.providerId == request.providerId &&
  decide (receipt.request = request) && !receipt.reference.isEmpty

theorem consumedPurchaseCannotClaimAgain (state : ConsumptionLedger) (expectedRevision : Nat)
    (budget : SharedBudget) (offer : MerchantOffer) (purchase : Purchase)
    (request : PaymentDispatch) (used : state.hasPurchase purchase.purchaseId = true) :
    state.claim expectedRevision budget offer purchase request = none := by
  simp [ConsumptionLedger.claim, used]

theorem consumptionClaimAdvancesRevision (state next : ConsumptionLedger)
    (expectedRevision : Nat) (budget : SharedBudget) (offer : MerchantOffer)
    (purchase : Purchase) (request : PaymentDispatch)
    (h : state.claim expectedRevision budget offer purchase request = some next) :
    next.revision = state.revision + 1 := by
  unfold ConsumptionLedger.claim at h
  split at h <;> simp_all
  rcases h with ⟨_, rfl⟩
  rfl

end CedarPooSpec.AgenticAI.Commerce
