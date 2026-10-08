/-! A selected AP2 checkout receipt/lifecycle subprofile. `verified` is a Host
projection of issuer/signature/schema/reference verification, not caller evidence.
A ledger belongs to one independently authenticated open-mandate/agent scope. -/
namespace CedarPooSpec.AgenticAI.Commerce
structure CheckoutPresentation where
  reference : String
  merchantIssuer : String
  presentedAt : Nat
  deriving DecidableEq, Repr
inductive CheckoutStatus where
  | success | error
  deriving DecidableEq, Repr
structure CheckoutReceipt where
  reference : String
  issuer : String
  issuedAt : Nat
  status : CheckoutStatus
  verified : Bool
  deriving DecidableEq, Repr
structure PresentationLedger where
  openMandateScope : String
  revision : Nat
  pending : Option CheckoutPresentation
  spent : Bool
  seen : List String
  deriving DecidableEq, Repr

def PresentationLedger.present (state : PresentationLedger) (openVct closedVct : String)
    (presentation : CheckoutPresentation) : Option PresentationLedger :=
  if state.spent then none else
  if state.pending.isSome || state.openMandateScope.isEmpty ||
      openVct != "mandate.checkout.open.1" || closedVct != "mandate.checkout.1" ||
      presentation.reference.isEmpty || presentation.merchantIssuer.isEmpty ||
      state.seen.contains presentation.reference then none else
    some { state with revision := state.revision + 1, pending := some presentation, seen := state.seen ++ [presentation.reference] }

def PresentationLedger.complete (state : PresentationLedger) (receipt : CheckoutReceipt) :
    Option PresentationLedger :=
  if state.spent then none else
  match state.pending with
  | none => none
  | some pending =>
    if receipt.verified && receipt.reference == pending.reference &&
        receipt.issuer == pending.merchantIssuer && decide (receipt.issuedAt ≥ pending.presentedAt) then
      some { state with revision := state.revision + 1, pending := none, spent := decide (receipt.status = .success) }
    else none

theorem spentCannotPresent (state : PresentationLedger) (p : CheckoutPresentation)
    (openVct closedVct : String) (h : state.spent = true) :
    state.present openVct closedVct p = none := by simp [PresentationLedger.present, h]
theorem pendingCannotPresent (state : PresentationLedger) (p q : CheckoutPresentation)
    (openVct closedVct : String) (h : state.pending = some q) :
    state.present openVct closedVct p = none := by simp [PresentationLedger.present, h]
theorem unverifiedCannotComplete (state : PresentationLedger) (receipt : CheckoutReceipt)
    (h : receipt.verified = false) : state.complete receipt = none := by
  unfold PresentationLedger.complete
  split <;> simp_all
  split <;> simp_all
end CedarPooSpec.AgenticAI.Commerce
