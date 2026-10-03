import CedarPooSpec.AgenticAI.Commerce.Presentation
import Lean
namespace CedarPooSpec.AgenticAI.CommercePresentationTest
open CedarPooSpec.AgenticAI.Commerce
open Lean
def fresh : PresentationLedger := ⟨"agent/open-mandate-A", 1, none, false, []⟩
def p : CheckoutPresentation := ⟨"closed-A", "merchant", 10⟩
def pending : PresentationLedger := ⟨fresh.openMandateScope, 2, some p, false, [p.reference]⟩
def rejected : PresentationLedger := ⟨fresh.openMandateScope, 3, none, false, [p.reference]⟩
def succeeded : PresentationLedger := ⟨fresh.openMandateScope, 3, none, true, [p.reference]⟩
def reject : CheckoutReceipt := ⟨p.reference, p.merchantIssuer, 11, .error, true⟩
def success : CheckoutReceipt := { reject with status := .success }
theorem presentationIsExact : fresh.present "mandate.checkout.open.1" "mandate.checkout.1" p = some pending := by decide
theorem rejectionIsExact : pending.complete reject = some rejected := by decide
theorem successIsExact : pending.complete success = some succeeded := by decide
theorem oldRejectionCannotClearNewPresentation :
    (rejected.present "mandate.checkout.open.1" "mandate.checkout.1" { p with reference := "closed-B" }).bind
      (fun state => state.complete reject) = none := by decide
theorem sameReferenceCannotReopen : rejected.present "mandate.checkout.open.1" "mandate.checkout.1" p = none := by decide
private def presentationJson (p : CheckoutPresentation) : Json := Json.mkObj [
  ("reference", toJson p.reference), ("merchantIssuer", toJson p.merchantIssuer), ("presentedAt", toJson p.presentedAt)]
private def stateJson (s : PresentationLedger) : Json := Json.mkObj [
  ("openMandateScope", toJson s.openMandateScope), ("revision", toJson s.revision),
  ("pending", match s.pending with | none => Json.null | some p => presentationJson p),
  ("spent", toJson s.spent), ("seen", toJson s.seen)]
def fixture : Json := Json.mkObj [
  ("schema", toJson "cedar-poo.commerce.presentation.v1"),
  ("ap2Revision", toJson "e1ea56db72a6385bce3e5c1112b3a56ce60acb43"),
  ("fresh", stateJson fresh), ("pending", stateJson pending),
  ("rejected", stateJson rejected), ("succeeded", stateJson succeeded)]
end CedarPooSpec.AgenticAI.CommercePresentationTest
def main : IO Unit := IO.println CedarPooSpec.AgenticAI.CommercePresentationTest.fixture.compress
