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

/-- Processor-reported effect terms. `chargedFee` is checked by the selected
    payment-rail adapter; this generic contract only requires it to be present. -/
structure SettlementDetails where
  payerAccount : Cedar.Spec.EntityUID
  instrument : String
  beneficiary : String
  amount : String
  asset : String
  network : String
  chargedFee : String
  deriving DecidableEq, Repr

def SettlementDetails.matches (details : SettlementDetails)
    (payment : PaymentOperation) : Bool :=
  details.payerAccount == payment.payerAccount &&
  details.instrument == payment.instrument &&
  details.beneficiary == payment.beneficiary &&
  details.amount == payment.amount && details.asset == payment.asset &&
  details.network == payment.network && !details.chargedFee.isEmpty

structure PaymentAttempt where
  payment : PaymentOperation
  phase : PaymentPhase
  providerReference : Option String := none
  settlement : Option SettlementDetails := none
  deriving DecidableEq, Repr

/-- The only outbound effect request issued by the pure transition. The Host
    must persist the returned `submitted` attempt before sending it. -/
structure ProcessorRequest where
  payment : PaymentOperation
  idempotencyKey : String
  deriving DecidableEq, Repr

/-- A read-only lookup after an uncertain response. The provider must resolve
    this key to the original request and return authenticated evidence. -/
structure ProcessorStatusQuery where
  payment : PaymentOperation
  idempotencyKey : String
  providerReference : Option String
  deriving DecidableEq, Repr

inductive ProcessorOutcome where
  | accepted | settled | rejected
  deriving DecidableEq, Repr

/-- `verified` means the Host authenticated this observation. The exact
    payment, request key, and provider reference are transition checks. -/
structure ProcessorEvidence where
  payment : PaymentOperation
  idempotencyKey : String
  providerReference : String
  outcome : ProcessorOutcome
  settlement : Option SettlementDetails := none
  verified : Bool
  deriving DecidableEq, Repr

def ProcessorEvidence.settlementMatches (evidence : ProcessorEvidence)
    (payment : PaymentOperation) : Bool :=
  match evidence.outcome, evidence.settlement with
  | .settled, some details => details.matches payment
  | .settled, none => false
  | _, none => true
  | _, some _ => false

/-- Reserve the nonce and create the pending attempt in one pure transition.
    The Host must persist both and the intended effect atomically. -/
def PaymentOperation.prepare (payment : PaymentOperation)
    (authorization : PaymentAuthorization) (state : PaymentState)
    (evidence : List AuditEvidence) : Option (PaymentState × PaymentAttempt) := do
  let next ← payment.reserve authorization state evidence
  pure (next, { payment, phase := .reserved })

/-- A Host may dispatch only from `reserved`. The nonce is the stable provider
    idempotency key. A lost response leaves the attempt `submitted`; calling
    `submit` on that returned state cannot issue another outbound request.
    The Host must reject concurrent or stale copies of `reserved` atomically. -/
def PaymentAttempt.submit (attempt : PaymentAttempt) :
    Option (PaymentAttempt × ProcessorRequest) :=
  if attempt.phase == .reserved && !attempt.payment.nonce.isEmpty then
    some ({ attempt with phase := .submitted },
      { payment := attempt.payment, idempotencyKey := attempt.payment.nonce })
  else none

/-- Recovery reads status using the same key; it never issues an effect
    request. An accepted attempt additionally carries its provider reference. -/
def PaymentAttempt.statusQuery (attempt : PaymentAttempt) :
    Option ProcessorStatusQuery :=
  if (attempt.phase == .submitted || attempt.phase == .accepted) &&
      !attempt.payment.nonce.isEmpty then
    some { payment := attempt.payment,
           idempotencyKey := attempt.payment.nonce,
           providerReference := attempt.providerReference }
  else none

/-- Processor acceptance is not final settlement. Settlement requires exact
    effect terms and a later outcome must retain the same provider reference;
    rejection and settlement are terminal. -/
def PaymentAttempt.observe (attempt : PaymentAttempt)
    (evidence : ProcessorEvidence) : Option PaymentAttempt :=
  if !evidence.verified || attempt.payment.nonce.isEmpty ||
      evidence.providerReference.isEmpty ||
      evidence.idempotencyKey != attempt.payment.nonce ||
      !decide (evidence.payment = attempt.payment) ||
      !evidence.settlementMatches attempt.payment then none
  else
    match attempt.phase, evidence.outcome with
    | .submitted, .accepted =>
        some { payment := attempt.payment, phase := .accepted,
               providerReference := some evidence.providerReference }
    | .submitted, .settled =>
        some { payment := attempt.payment, phase := .settled,
               providerReference := some evidence.providerReference,
               settlement := evidence.settlement }
    | .submitted, .rejected =>
        some { payment := attempt.payment, phase := .rejected,
               providerReference := some evidence.providerReference }
    | .accepted, .settled =>
        if attempt.providerReference == some evidence.providerReference then
          some { attempt with phase := .settled, settlement := evidence.settlement }
        else none
    | .accepted, .rejected =>
        if attempt.providerReference == some evidence.providerReference then
          some { attempt with phase := .rejected }
        else none
    | _, _ => none

theorem submittedCannotSubmitAgain (attempt next : PaymentAttempt)
    (request : ProcessorRequest)
    (h : attempt.submit = some (next, request)) : next.submit = none := by
  unfold PaymentAttempt.submit at h ⊢
  split at h
  · cases h
    simp
  · simp at h

theorem wrongIdempotencyKeyCannotAdvance (attempt : PaymentAttempt)
    (evidence : ProcessorEvidence)
    (h : evidence.idempotencyKey ≠ attempt.payment.nonce) :
    attempt.observe evidence = none := by
  simp [PaymentAttempt.observe, h]

theorem acceptedIsNotSettlement (payment : PaymentOperation)
    (reference : String) :
    (PaymentAttempt.observe
      { payment, phase := .submitted }
      { payment, idempotencyKey := payment.nonce,
        providerReference := reference, outcome := .accepted,
        verified := true }).map PaymentAttempt.phase ≠ some .settled := by
  by_cases h : reference.isEmpty
  · simp [PaymentAttempt.observe, h]
  · simp [PaymentAttempt.observe, h]

end CedarPooSpec.Vertical.FinancialServices
