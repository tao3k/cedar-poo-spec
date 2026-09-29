import CedarPooSpec.Governance.Personnel.Status
import Cedar.Spec.Entities

/-!
The personnel authority supplies project assignments and engagement class.
Policies can compare those attributes with asset ownership instead of
enumerating each human in a static ACL. This record is a projection, not an
identity proof or an HR system.
-/

namespace CedarPooSpec.Governance.Personnel

open Cedar.Spec Cedar.Data

inductive Engagement where
  | intern
  | researcher
  | core
  deriving BEq, DecidableEq, Repr

def Engagement.label : Engagement → String
  | .intern => "intern"
  | .researcher => "researcher"
  | .core => "core"

structure Assignment where
  engagement : Engagement
  projects : List String
  stage : Status.Stage := .active
  deriving BEq

def Assignment.entityData (assignment : Assignment) : EntityData :=
  { attrs := Map.make [
      ("engagement", .prim (.string assignment.engagement.label)),
      ("projects", .set (Set.make
        (assignment.projects.map (fun project => .prim (.string project))))),
      ("employmentStage", .prim (.string assignment.stage.label))],
    ancestors := Set.empty, tags := Map.empty }

end CedarPooSpec.Governance.Personnel
