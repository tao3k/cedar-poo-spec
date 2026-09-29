import CedarPooSpec.Governance.Veto

/-!
Result release is a separate owned permission after a token join. Cedar checks
the projected predicates; a Host must authenticate them and consume the budget
in the same durable transaction as the actual result release.
-/

namespace CedarPooSpec.Pseudonymization

open Cedar.Spec CedarPooSpec.PolicyModules CedarPooSpec.Governance

structure ResultRelease where
  permitId : PolicyID
  ownerVetoId : PolicyID
  actionScope : ActionScope
  sameTarget : Expr
  tenantBound : Expr
  actorAllowed : Expr
  targetTenantBound : Expr
  ownerApproved : Expr
  releaseApproved : Expr
  budgetAvailable : Expr
  principalScope : PrincipalScope := .principalScope .any
  resourceScope : ResourceScope := .resourceScope .any

def ResultRelease.permit (control : ResultRelease) : Policy :=
  let body :=
    .and control.sameTarget (.and control.tenantBound
      (.and control.actorAllowed (.and control.targetTenantBound
        (.and control.releaseApproved control.budgetAvailable))))
  { id := control.permitId, effect := .permit,
    principalScope := control.principalScope,
    actionScope := control.actionScope,
    resourceScope := control.resourceScope,
    condition := [{ kind := .when, body }] }

def ResultRelease.ownerVeto (control : ResultRelease) : Policy :=
  (Veto.mk control.ownerVetoId control.actionScope
    (.unaryApp .not control.ownerApproved)
    control.principalScope control.resourceScope).policy

inductive ResultRelease.Change where
  | introduce | revise | withdraw

def ResultRelease.edits (control : ResultRelease) : ResultRelease.Change → List Edit
  | .introduce => [.extend control.permit, .extend control.ownerVeto]
  | .revise => [.overlay control.permit, .overlay control.ownerVeto]
  | .withdraw => [.remove control.permitId, .remove control.ownerVetoId]

end CedarPooSpec.Pseudonymization
