import CedarPooSpec.Vertical.FinancialServices.PaymentOperation
import Examples.Enterprise.Agent.Payment.AgentPayment

/-! Example adapter: bind a public payment operation to this Cedar policy. -/

namespace CedarPooSpec.AgentPaymentAuditExample

open CedarPooSpec.Vertical.FinancialServices
open CedarPooSpec.AgentPaymentExample

/-- This example requires three audit stages. Other payment instruments and risk
    levels may use a different policy without changing `PaymentOperation`. -/
def auditPolicy : PaymentAuditPolicy :=
  { requirements := [
      { kind := .model, source := "risk-v1", minimum := 1 },
      { kind := .human, source := "risk", minimum := 1,
        excludeProposer := true },
      { kind := .human, source := "compliance", minimum := 1,
        excludeProposer := true }],
    distinctHumanActors := true }

def cedarAllowed (payment : PaymentOperation) : Bool :=
  match Cedar.Spec.Ext.Decimal.decimal payment.amount with
  | none => false
  | some _ =>
    authorizePayment "PaymentGoverned" payment.payerAccount payment.origin
      payment.amount

def cedarAuthorization (payment : PaymentOperation) : PaymentAuthorization :=
  { payment, auditPolicy, allowed := cedarAllowed payment, verified := true }

def reserveWithCedar (payment : PaymentOperation) (state : PaymentState)
    (evidence : List AuditEvidence) : Option PaymentState :=
  payment.reserve (cedarAuthorization payment) state evidence

end CedarPooSpec.AgentPaymentAuditExample
