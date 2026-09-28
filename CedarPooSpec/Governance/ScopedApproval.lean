import CedarPooSpec.PolicyModules

/-!
An approval is bound to one actor, operation, purpose, and source/target pair.
The Host authenticates the approver and owns the revision and clock; this
value check cannot establish either fact by itself.
-/

namespace CedarPooSpec.Governance

open Cedar.Spec

structure ScopedApproval where
  id : String
  approver : EntityUID
  actor : EntityUID
  operation : EntityUID
  purpose : String
  source : EntityUID
  target : EntityUID
  revision : Nat
  expiresAt : Nat
  deriving BEq

def ScopedApproval.applies (grant : ScopedApproval)
    (actor operation : EntityUID) (purpose : String)
    (source target : EntityUID) (revision now : Nat) : Bool :=
  grant.actor == actor && grant.operation == operation &&
  grant.purpose == purpose && grant.source == source &&
  grant.target == target && grant.revision == revision &&
  decide (now < grant.expiresAt)

end CedarPooSpec.Governance
