import Cedar.Spec.Policy

/-!
Relations over Cedar's own expression AST. Attribute names and their schema
requirements belong to the caller; this module does not define an entity
catalog or a second policy evaluator.
-/

namespace CedarPooSpec.Data

open Cedar.Spec

/-- Require a named attribute to agree between two Cedar entity expressions. -/
def sameAttribute (left right : Expr) (name : String) : Expr :=
  .binaryApp .eq (.getAttr left name) (.getAttr right name)

end CedarPooSpec.Data
