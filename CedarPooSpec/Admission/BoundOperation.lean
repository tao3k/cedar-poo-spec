import CedarPooSpec.CompoundAuthorization

/-!
A typed operation projects the effect and observed state into Cedar's request
model. The projection is fixed when the operation is constructed; a later Host
must still authenticate the actual effect and state before execution.
-/

namespace CedarPooSpec.Admission

open Cedar.Spec CedarPooSpec.PolicyModules

structure BoundOperation (Effect State : Type)
    (project : Effect → State → Request) where
  effect : Effect
  state : State

def BoundOperation.request {Effect State : Type}
    {project : Effect → State → Request}
    (operation : BoundOperation Effect State project) : Request :=
  project operation.effect operation.state

/-- Check a concrete operation against the actual effect and state supplied
    by the caller. This equality check does not authenticate either input. -/
def BoundOperation.matches {Effect State : Type}
    {project : Effect → State → Request}
    [DecidableEq Effect] [DecidableEq State]
    (operation : BoundOperation Effect State project)
    (effect : Effect) (state : State) : Bool :=
  decide (operation.effect = effect ∧ operation.state = state)

/-- Reuse the existing proof-bearing Cedar evaluation for the request derived
    from one bound operation and one POO root. -/
def BoundOperation.authorize {Effect State : Type}
    {project : Effect → State → Request}
    (operation : BoundOperation Effect State project)
    (model : Model) (root : String) (entities : Entities) :
    Except PolicyModules.Error
      (CompoundAuthorization.Receipt model root [operation.request] entities) :=
  CompoundAuthorization.authorizeAll model root [operation.request] entities

end CedarPooSpec.Admission
