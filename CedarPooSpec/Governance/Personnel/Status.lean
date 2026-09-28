import CedarPooSpec.Governance.Veto

/-!
An organization-controlled personnel status is an attribute of the human
origin, including when an Agent executes. This control does not infer intent
from behavior; the Host must project a current, authenticated roster snapshot.
-/

namespace CedarPooSpec.Governance.Personnel.Status

open Cedar.Spec CedarPooSpec.Governance

inductive Stage where
  | active
  | departureWindow
  | separated
  deriving BEq, DecidableEq, Repr

def Stage.label : Stage → String
  | .active => "active"
  | .departureWindow => "departure-window"
  | .separated => "separated"

/-- Restrict a selected operation when the originating human is in a roster
    stage. An Agent cannot escape the rule by using its own principal. -/
def veto (id : PolicyID) (actions : ActionScope) (stage : Stage) : Veto :=
  { policyId := id, actionScope := actions,
    denyWhen := .binaryApp .eq
      (.getAttr (.getAttr (.var .context) "origin") "employmentStage")
      (.lit (.string stage.label)) }

end CedarPooSpec.Governance.Personnel.Status
