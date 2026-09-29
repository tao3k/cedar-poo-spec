import CedarPooSpec.PolicyModules

/-!
An admission ticket may name a stable POO root while its declarations change
between prepare and commit. Bind the exact compiled Cedar policy set to the
ticket; the Host still owns authentication, durable epochs, and execution.
-/

namespace CedarPooSpec.Admission

open Cedar.Spec CedarPooSpec.PolicyModules

structure PolicySnapshot where
  root : String
  policies : Policies
  deriving BEq

inductive PolicySnapshot.Error where
  | compilation (error : PolicyModules.Error)
  | changed
  deriving Repr

/-- Capture the exact C4-composed Cedar policies used at preparation. -/
def PolicySnapshot.capture (model : Model) (root : String) :
    Except PolicyModules.Error PolicySnapshot := do
  let policies ← model.compile root
  return ⟨root, policies⟩

/-- Return the current policies only when this root still compiles to the
    exact same policy set. A changed body, order, or compilation error fails. -/
def PolicySnapshot.currentPolicies (snapshot : PolicySnapshot)
    (model : Model) : Except PolicySnapshot.Error Policies :=
  match model.compile snapshot.root with
  | .ok policies => if policies == snapshot.policies then .ok policies else .error .changed
  | .error error => .error (.compilation error)

end CedarPooSpec.Admission
