import Examples.Enterprise.Agent.Department.DepartmentSynthesis

/-!
A replaceable record and delivery port for the connected department workflow.
The example below supplies synthetic records. A downstream host supplies its
own record and delivery implementation together with trusted authority state.
-/

namespace CedarPooSpec.DepartmentSynthesisExample.Simulation

/-- Data and effect operations required by the workflow. An implementation may
    use real records, but must enforce its own identity, storage, and execution
    transaction contract. -/
structure Port (m : Type → Type) where
  fetch : Cedar.Spec.EntityUID → m (Except String String)
  publish : String → m (Except String Unit)

/-- This one implementation is synthetic; the workflow does not depend on it. -/
def syntheticPort : Port Id where
  fetch := fun resource =>
    if resource == salesRecord then
      .ok "SYNTHETIC Sales contract: project Aurora"
    else if resource == financeRecord then
      .ok "SYNTHETIC Finance invoice: project Aurora"
    else
      .error "Unknown synthetic record"
  publish := fun _ => .ok ()

/-- Counts a fetch as one and a publish as one hundred, so the finite
    examples can distinguish an attempted external effect from reads. -/
private def countedPort : Port (StateM Nat) where
  fetch := fun resource => do
    modify (· + 1)
    return syntheticPort.fetch resource
  publish := fun _ => do
    modify (· + 100)
    return .ok ()

inductive Command where
  | readSales
  | readFinance
  | sendReport
  | revokeDelegation
  deriving BEq, DecidableEq, Repr

inductive Outcome where
  | read (content : String)
  | sent (content : String)
  | denied
  | revoked
  | portError (message : String)
  deriving BEq, DecidableEq, Repr

structure Snapshot where
  authority : State := {}
  draft : List String := []
  published : List String := []
  outcomes : List Outcome := []

private def read [Monad m] (port : Port m) (root : String)
    (snapshot : Snapshot) (attempt : Attempt) : m Snapshot := do
  if !authorized root snapshot.authority attempt then
    return { snapshot with outcomes := snapshot.outcomes ++ [.denied] }
  match ← port.fetch attempt.resource with
  | .error message =>
      return { snapshot with outcomes := snapshot.outcomes ++ [.portError message] }
  | .ok content =>
      return { snapshot with
        authority := advance snapshot.authority attempt,
        draft := snapshot.draft ++ [content],
        outcomes := snapshot.outcomes ++ [.read content] }

private def send [Monad m] (port : Port m) (root : String)
    (snapshot : Snapshot) : m Snapshot := do
  if !authorized root snapshot.authority sendReport then
    return { snapshot with outcomes := snapshot.outcomes ++ [.denied] }
  let content := String.intercalate "\n" snapshot.draft
  match ← port.publish content with
  | .error message =>
      return { snapshot with outcomes := snapshot.outcomes ++ [.portError message] }
  | .ok () =>
      return { snapshot with
        authority := advance snapshot.authority sendReport,
        published := snapshot.published ++ [content],
        outcomes := snapshot.outcomes ++ [.sent content] }

/-- Apply one command using the supplied record and delivery port. -/
def step [Monad m] (port : Port m) (root : String) (snapshot : Snapshot)
    (command : Command) : m Snapshot :=
  match command with
  | .readSales => read port root snapshot readSales
  | .readFinance => read port root snapshot readFinance
  | .sendReport => send port root snapshot
  | .revokeDelegation => pure
      { snapshot with
        authority := { snapshot.authority with delegationActive := false },
        outcomes := snapshot.outcomes ++ [.revoked] }

/-- Run a serial workflow. The supplied origin must come from trusted host
    identity; this function itself does not authenticate it. -/
def run [Monad m] (port : Port m) (root originDept : String)
    (commands : List Command) : m Snapshot :=
  commands.foldlM (step port root)
    { authority := { originDept := originDept } }

theorem singleDepartmentSend :
    (run syntheticPort "DepartmentGoverned" "Joint"
      [.readSales, .sendReport]).published =
      ["SYNTHETIC Sales contract: project Aurora"] := by
  native_decide

theorem jointResultBlocked :
    let result := run syntheticPort "DepartmentGoverned" "Joint"
      [.readSales, .readFinance, .sendReport]
    result.draft.length = 2 ∧ result.published = [] ∧
      result.outcomes.getLast? = some .denied := by
  native_decide

theorem otherDepartmentReadBlocked :
    (run syntheticPort "DepartmentGoverned" "Sales" [.readFinance]).draft = [] := by
  native_decide

theorem revokedBeforeSend :
    let result := run syntheticPort "DepartmentGoverned" "Joint"
      [.readSales, .revokeDelegation, .sendReport]
    result.draft.length = 1 ∧ result.published = [] ∧
      result.outcomes.getLast? = some .denied := by
  native_decide

theorem deniedSendDoesNotCallPort :
    ((run countedPort "DepartmentGoverned" "Joint"
      [.readSales, .readFinance, .sendReport]).run 0).2 = 2 ∧
    ((run countedPort "DepartmentGoverned" "Joint"
      [.readSales, .sendReport]).run 0).2 = 101 := by
  native_decide

end CedarPooSpec.DepartmentSynthesisExample.Simulation
