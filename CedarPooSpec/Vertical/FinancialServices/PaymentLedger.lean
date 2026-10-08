import CedarPooSpec.Vertical.FinancialServices.PaymentLifecycle

/-!
A pure, multi-payment Host ledger for request-key ownership and cached
processor state. The Host must persist every returned ledger with an atomic
compare-and-swap before using an outbound command. This model does not provide
storage, network I/O, or a provider-side idempotency guarantee.
-/

namespace CedarPooSpec.Vertical.FinancialServices

structure PaymentLedger where
  revision : Nat := 0
  state : PaymentState
  attempts : List PaymentAttempt := []
  deriving DecidableEq, Repr

/-- Exactly one record may own a request key. Missing and duplicated keys both
    fail closed, including if the Host loaded a malformed ledger. -/
def PaymentLedger.attemptFor (ledger : PaymentLedger)
    (key : String) : Option PaymentAttempt :=
  match ledger.attempts.filter (fun attempt => attempt.payment.nonce == key) with
  | [attempt] => some attempt
  | _ => none

private def PaymentLedger.replace (ledger : PaymentLedger)
    (key : String) (next : PaymentAttempt) : PaymentLedger :=
  let attempts := ledger.attempts.map fun attempt =>
    if attempt.payment.nonce == key then next else attempt
  { ledger with revision := ledger.revision + 1, attempts }

/-- The nonce reservation and pending record are one abstract transaction.
    A key already present in the ledger cannot be rebound to another payment. -/
def PaymentLedger.prepare (ledger : PaymentLedger)
    (payment : PaymentOperation) (authorization : PaymentAuthorization)
    (evidence : List AuditEvidence) : Option PaymentLedger := do
  if ledger.attempts.any (fun attempt => attempt.payment.nonce == payment.nonce) then
    none
  else
    let (nextState, attempt) ← payment.prepare authorization ledger.state evidence
    some { revision := ledger.revision + 1,
           state := nextState, attempts := attempt :: ledger.attempts }

/-- A nonce reservation and exactly one matching record are required to issue
    a command. On success the returned ledger contains the `submitted` record
    and must be durably committed before the request is sent. -/
def PaymentLedger.dispatch (ledger : PaymentLedger)
    (key : String) : Option (PaymentLedger × ProcessorRequest) := do
  if !(ledger.state.usedNonces.contains key) then none
  let current ← ledger.attemptFor key
  let (next, request) ← current.submit
  if request.idempotencyKey != key then none
  else some (ledger.replace key next, request)

/-- Read the cached outcome or pending state without creating an effect. -/
def PaymentLedger.cached (ledger : PaymentLedger)
    (key : String) : Option PaymentAttempt :=
  ledger.attemptFor key

/-- A read-only provider lookup for submitted or accepted records. -/
def PaymentLedger.statusQuery (ledger : PaymentLedger)
    (key : String) : Option ProcessorStatusQuery := do
  let current ← ledger.attemptFor key
  current.statusQuery

/-- Authenticated processor evidence advances exactly its key's record. -/
def PaymentLedger.reconcile (ledger : PaymentLedger)
    (evidence : ProcessorEvidence) : Option PaymentLedger := do
  let current ← ledger.attemptFor evidence.idempotencyKey
  let next ← current.observe evidence
  some (ledger.replace evidence.idempotencyKey next)

end CedarPooSpec.Vertical.FinancialServices
