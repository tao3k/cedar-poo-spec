import LeanPoo.Object.Multimethod

/-!
Reusable, fail-closed boundary for tool-using agentic systems. Tool actions and
sink classes are typed inputs, not names selected by a model prompt. LeanPoo's
two-argument multimethod composes every applicable check; a specialized method
can add a veto but cannot erase a less-specific one.
-/

namespace CedarPooSpec.AgenticAI

structure SelectionDelta where
  before : List String
  after : List String
  deriving DecidableEq

def SelectionDelta.wellFormed (delta : SelectionDelta) : Bool :=
  !delta.before.isEmpty && !delta.after.isEmpty &&
    delta.before.eraseDups == delta.before &&
    delta.after.eraseDups == delta.after &&
    delta.after.length < delta.before.length &&
    delta.after.all (delta.before.contains ·)

inductive ToolAction where
  | contentWrite | selectionMutation
  deriving DecidableEq

inductive SinkClass where
  | sharedWorkspace | directMessage | remoteModel
  deriving DecidableEq

structure BoundaryFacts where
  action : ToolAction
  sink : SinkClass
  intendedSelection : Option SelectionDelta := none
  observedSelection : Option SelectionDelta := none
  candidateIds : List String := []
  outputBound : Bool := false
  audienceAllowed : Bool := false
  remoteModelApproved : Bool := false

def actionOrder : ToolAction → List String
  | .contentWrite => ["ContentWrite", "ToolEffect"]
  | .selectionMutation => ["SelectionMutation", "ToolEffect"]

def sinkOrder : SinkClass → List String
  | .sharedWorkspace => ["SharedWorkspace", "ExternalSink"]
  | .directMessage => ["DirectMessage", "ExternalSink"]
  | .remoteModel => ["RemoteModel", "ExternalSink"]

abbrev Check := BoundaryFacts → Bool

def generic : LeanPoo.Object.Multimethod BoundaryFacts Check Bool :=
  { arity := 2
    precedence := fun facts => [actionOrder facts.action, sinkOrder facts.sink]
    combine := fun checks facts =>
      !checks.isEmpty && checks.toList.all (fun check => check facts) }

def checks : Except LeanPoo.Object.MultimethodError
    (LeanPoo.Object.Multimethod BoundaryFacts Check Bool) := do
  let g ← generic.register [.any, .any] (fun facts => facts.outputBound)
  let g ← g.contribute [.prototype "ContentWrite", .any]
    (fun facts => facts.intendedSelection.isNone && facts.observedSelection.isNone)
  let g ← g.contribute [.prototype "SelectionMutation", .any]
    (fun facts => match facts.intendedSelection with
      | none => false
      | some delta =>
          facts.observedSelection == some delta && delta.wellFormed &&
          facts.candidateIds == delta.after)
  let g ← g.contribute [.any, .prototype "ExternalSink"]
    (fun facts => facts.audienceAllowed)
  g.contribute [.any, .prototype "RemoteModel"]
    (fun facts => facts.remoteModelApproved)

def admitted (facts : BoundaryFacts) : Bool :=
  match checks with
  | .error _ => false
  | .ok g =>
      match g.call facts with
      | .error _ => false
      | .ok (answer, _) => answer

end CedarPooSpec.AgenticAI
