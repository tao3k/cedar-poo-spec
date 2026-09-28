import CedarPooSpec.Admission.BoundOperation
import CedarPooSpec.Governance.Veto
import CedarPooSpec.Governance.ScopedApproval
import CedarPooSpec.Governance.Personnel.Delegation

/-!
Typed input for an organization-mediated asset operation. The principal is the
actual executor; an agent never impersonates its originating human. The Host
authenticates identities, device posture, approvals, epochs, and the eventual
effect before using this projection. Policy evaluation alone cannot control a
copy already present on an unmanaged device.
-/

namespace CedarPooSpec.Governance.Personnel.AssetAccess

open Cedar.Spec CedarPooSpec.Governance

structure Effect where
  executor : EntityUID
  action : EntityUID
  asset : EntityUID
  destination : EntityUID
  purpose : String
  deriving BEq, DecidableEq

structure Snapshot where
  origin : EntityUID
  device : EntityUID
  deviceTrusted : Bool
  delegationValid : Bool
  approvalValid : Bool
  incident : Bool
  epoch : Nat
  deriving BEq, DecidableEq

def project (effect : Effect) (state : Snapshot) : Request :=
  ⟨effect.executor, effect.action, effect.asset, Cedar.Data.Map.make [
    ("origin", .prim (.entityUID state.origin)),
    ("device", .prim (.entityUID state.device)),
    ("deviceTrusted", .prim (.bool state.deviceTrusted)),
    ("delegationValid", .prim (.bool state.delegationValid)),
    ("approvalValid", .prim (.bool state.approvalValid)),
    ("incident", .prim (.bool state.incident)),
    ("destination", .prim (.entityUID effect.destination)),
    ("purpose", .prim (.string effect.purpose)),
    ("epoch", .prim (.string (toString state.epoch)))]⟩

abbrev Operation := CedarPooSpec.Admission.BoundOperation Effect Snapshot project

/-- Project an already authenticated, scoped approval into the snapshot. -/
def Snapshot.withApproval (state : Snapshot) (grant : ScopedApproval)
    (effect : Effect) (now : Nat) : Snapshot :=
  { state with approvalValid :=
      (grant.applies state.origin effect.action effect.purpose effect.asset
        effect.destination state.epoch now) }

/-- Project one scoped, authenticated human-to-Agent delegation. -/
def Snapshot.withDelegation (state : Snapshot) (grant : Personnel.Delegation)
    (effect : Effect) (now : Nat) : Snapshot :=
  { state with delegationValid :=
      (grant.applies state.origin effect.executor effect.action effect.asset
        effect.destination effect.purpose state.epoch now) }

private def ctx (name : String) : Expr := .getAttr (.var .context) name

/-- Require a Host-attested trusted device for the selected operation. -/
def deviceVeto (id : PolicyID) (actions : ActionScope) : Veto :=
  { policyId := id, actionScope := actions,
    denyWhen := .unaryApp .not (ctx "deviceTrusted") }

/-- An agent must carry a separate, authenticated delegation. Human requests
    use their own principal and origin identity. -/
def delegationVeto (id : PolicyID) (actions : ActionScope) : Veto :=
  { policyId := id, actionScope := actions,
    denyWhen := .and
      (.unaryApp .not (.binaryApp .eq (.var .principal) (ctx "origin")))
      (.unaryApp .not (ctx "delegationValid")) }

/-- A trusted incident snapshot can freeze selected actions without changing
    an unrelated read policy. -/
def incidentVeto (id : PolicyID) (actions : ActionScope) : Veto :=
  { policyId := id, actionScope := actions,
    denyWhen := ctx "incident" }

end CedarPooSpec.Governance.Personnel.AssetAccess
