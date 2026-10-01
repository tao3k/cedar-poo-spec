import CedarPooSpec.Vertical.FinancialServices.PaymentOperation

/-!
A pure Host protocol for one payment after authorization and audit. Reservation,
submission, processor acceptance, and settlement are distinct states. The
Host must persist transitions and authenticate processor evidence; no network
call, signature check, or economic effect occurs in this module.
-/

namespace CedarPooSpec.Vertical.FinancialServices

inductive PaymentPhase where
  | reserved | submitted | accepted | settled | rejected
  deriving DecidableEq, Repr

structure PaymentAttempt where
  payment : PaymentOperation
  phase : PaymentPhase
  providerReference : Option String := none
  deriving DecidableEq, Repr

inductive ProcessorOutcome where
  | accepted | settled | rejected
  deriving DecidableEq, Repr

/-- `verified` means the Host authenticated this observation. The exact
    payment and provider reference remain part of the transition check. -/
structure ProcessorEvidence where
  payment : PaymentOperation
  providerReference : String
  outcome : ProcessorOutcome
  verified : Bool
  deriving DecidableEq, Repr

/-- Reserve the nonce and create the pending attempt in one pure transition.
    The Host must persist both and the intended effect atomically. -/
def PaymentOperation.prepare (payment : PaymentOperation)
    (authorization : PaymentAuthorization) (state : PaymentState)
    (evidence : List AuditEvidence) : Option (PaymentState × PaymentAttempt) := do
  let next ← payment.reserve authorization state evidence
  pure (next, { payment, phase := .reserved })

/-- A Host may dispatch only from `reserved`. A lost response leaves the
    attempt `submitted`; re-invoking `submit` cannot authorize another send. -/
def PaymentAttempt.submit (attempt : PaymentAttempt) : Option PaymentAttempt :=
  if attempt.phase == .reserved then
    some { attempt with phase := .submitted }
  else none

/-- Processor acceptance is not final settlement. A later settlement or
    rejection must carry the same provider reference; both are terminal. -/
def PaymentAttempt.observe (attempt : PaymentAttempt)
    (evidence : ProcessorEvidence) : Option PaymentAttempt :=
  if !evidence.verified || evidence.providerReference.isEmpty ||
      !decide (evidence.payment = attempt.payment) then none
  else
    match attempt.phase, evidence.outcome with
    | .submitted, .accepted =>
        some { payment := attempt.payment, phase := .accepted,
               providerReference := some evidence.providerReference }
    | .submitted, .settled =>
        some { payment := attempt.payment, phase := .settled,
               providerReference := some evidence.providerReference }
    | .submitted, .rejected =>
        some { payment := attempt.payment, phase := .rejected,
               providerReference := some evidence.providerReference }
    | .accepted, .settled =>
        if attempt.providerReference == some evidence.providerReference then
          some { attempt with phase := .settled }
        else none
    | .accepted, .rejected =>
        if attempt.providerReference == some evidence.providerReference then
          some { attempt with phase := .rejected }
        else none
    | _, _ => none

theorem submittedCannotSubmitAgain (attempt next : PaymentAttempt)
    (h : attempt.submit = some next) : next.submit = none := by
  unfold PaymentAttempt.submit at h ⊢
  split at h
  · cases h
    simp
  · simp at h

theorem acceptedIsNotSettlement (payment : PaymentOperation)
    (reference : String) :
    (PaymentAttempt.observe
      { payment, phase := .submitted }
      { payment, providerReference := reference, outcome := .accepted,
        verified := true }).map PaymentAttempt.phase ≠ some .settled := by
  by_cases h : reference.isEmpty
  · simp [PaymentAttempt.observe, h]
  · simp [PaymentAttempt.observe, h]

end CedarPooSpec.Vertical.FinancialServices
