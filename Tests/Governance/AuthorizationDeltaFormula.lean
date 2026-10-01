import CedarPooSpec.AuthorizationDeltaOperationalExactProof
import Examples.Governance.TicketSharing

open Cedar.Spec Cedar.Validation Cedar.SymCC
open CedarPooSpec.AuthorizationDelta
open CedarPooSpec.TicketSharingExample

namespace CedarPooSpec.AuthorizationDeltaFixture

def typeEnv : TypeEnv := schema.environments.head!
def symEnv : SymEnv := SymEnv.ofTypeEnv typeEnv
def revision := (model.compileRevision "Published" "Posture").toOption.get (by native_decide)
def before := (wellTypedPolicies revision.beforePolicies typeEnv).toOption.get (by native_decide)
def after := (wellTypedPolicies revision.afterPolicies typeEnv).toOption.get (by native_decide)
def asserts := (verifyErrorFreeAllowExpansion before after symEnv).toOption.get (by native_decide)

def attrs : UnaryFunction := (symEnv.entities.attrs ticketType).get (by native_decide)
def pb : Term := Factory.eq symEnv.request.principal (.entity bob)
def pa : Term := Factory.eq symEnv.request.principal (.entity alice)
def ra : Term := Factory.eq symEnv.request.resource (.entity ticketA)
def rb : Term := Factory.eq symEnv.request.resource (.entity ticketB)
def st : Term := Factory.eq (Factory.record.get (Factory.app attrs symEnv.request.resource) "status") (.string "OPEN")
def td : Term := Factory.record.get symEnv.request.context "deviceTrusted"
def base : Term := Factory.and pb (Factory.and ra st)
def v2b : Term := Factory.and pb (Factory.and rb (Factory.and st td))
def v2a : Term := Factory.and pa (Factory.and ra (Factory.and st td))
def v1b : Term := Factory.and pb (Factory.and rb st)
def v1a : Term := Factory.and pa (Factory.and ra st)
def formula : Term := Factory.and (Factory.or base (Factory.or v2b v2a))
  (Factory.not (Factory.or base (Factory.or v1b v1a)))

/-- The pinned, typechecked ticket-sharing revision generates exactly this
    two-assertion symbolic query. This is a structural identity, not an UNSAT proof. -/
theorem exactQueryShape : asserts = [(true : Term), formula] := by
  native_decide

/-- Propositional core of the fixed revision: every new Allow case is already
    covered by an old Allow case when the six atomic conditions are Boolean. -/
theorem formulaBooleanCore (pb pa ra rb st td : Bool) :
    (((pb && ra && st) || (pb && rb && st && td) || (pa && ra && st && td)) &&
      !((pb && ra && st) || (pb && rb && st) || (pa && ra && st))) = false := by
  cases pb <;> cases pa <;> cases ra <;> cases rb <;> cases st <;> cases td <;> decide

end CedarPooSpec.AuthorizationDeltaFixture
