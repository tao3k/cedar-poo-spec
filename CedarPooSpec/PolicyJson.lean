import CedarPooSpec.PolicyModules
import Cedar.Spec.Entities
import Cedar.Spec.Request
import Cedar.Spec.Authorizer
import Lean

/-!
Export the concrete subset of Cedar's Lean policy AST to Cedar's documented
JSON policy-set format. Unsupported abstract forms fail before deployment.
-/

namespace CedarPooSpec.PolicyJson

open Cedar.Spec

inductive Error where
  | unsupportedScope (policyId : PolicyID)
  | unsupportedExpression (policyId : PolicyID)
  | expressionDepthExceeded (policyId : PolicyID)
  | duplicatePolicyId (policyId : PolicyID)
  | duplicateRecordKey (policyId : PolicyID)
  | duplicateEntityAttribute
  | unsupportedValue
  | valueDepthExceeded
  deriving Repr, BEq

private def obj (fields : List (String × Lean.Json)) : Lean.Json := Lean.Json.mkObj fields

def entity (uid : EntityUID) : Lean.Json :=
  obj [("type", Lean.toJson (toString uid.ty)), ("id", Lean.toJson uid.eid)]

private def scope : Scope → Except Error Lean.Json
  | .any => .ok (obj [("op", Lean.toJson "All")])
  | .eq uid => .ok (obj [("op", Lean.toJson "=="), ("entity", entity uid)])
  | .mem uid => .ok (obj [("op", Lean.toJson "in"), ("entity", entity uid)])
  | .is ty => .ok (obj [("op", Lean.toJson "is"),
      ("entity_type", Lean.toJson (toString ty))])
  | .isMem ty uid => .ok (obj [("op", Lean.toJson "is"),
      ("entity_type", Lean.toJson (toString ty)),
      ("in", obj [("entity", entity uid)])])

private def actionScope (id : PolicyID) : ActionScope → Except Error Lean.Json
  | .actionScope (.is _) => .error (.unsupportedScope id)
  | .actionScope (.isMem _ _) => .error (.unsupportedScope id)
  | .actionScope s => scope s
  | .actionInAny uids =>
      .ok (obj [("op", Lean.toJson "in"), ("entities", Lean.toJson (uids.map entity))])

private def primitive : Prim → Lean.Json
  | .bool value => Lean.toJson value
  | .int value => Lean.toJson value.toInt
  | .string value => Lean.toJson value
  | .entityUID uid => obj [("__entity", entity uid)]

private def varName : Var → String
  | .principal => "principal"
  | .action => "action"
  | .resource => "resource"
  | .context => "context"

private def binaryName : BinaryOp → String
  | .eq => "=="
  | .mem => "in"
  | .hasTag => "hasTag"
  | .getTag => "getTag"
  | .less => "<"
  | .lessEq => "<="
  | .add => "+"
  | .sub => "-"
  | .mul => "*"
  | .contains => "contains"
  | .containsAll => "containsAll"
  | .containsAny => "containsAny"

private def pair (name : String) (left right : Lean.Json) : Lean.Json :=
  obj [(name, obj [("left", left), ("right", right)])]

private def unary (name : String) (arg : Lean.Json) : Lean.Json :=
  obj [(name, obj [("arg", arg)])]

private def patternElement : PatElem → Lean.Json
  | .star => Lean.toJson "Wildcard"
  | .justChar char => obj [("Literal", Lean.toJson (String.ofList [char]))]

private def expressionFuel (id : PolicyID) : Nat → Cedar.Spec.Expr → Except Error Lean.Json
  | 0, _ => .error (.expressionDepthExceeded id)
  | _fuel + 1, .lit value => .ok (obj [("Value", primitive value)])
  | _fuel + 1, .var value => .ok (obj [("Var", Lean.toJson (varName value))])
  | fuel + 1, .and left right => do
      return pair "&&" (← expressionFuel id fuel left) (← expressionFuel id fuel right)
  | fuel + 1, .or left right => do
      return pair "||" (← expressionFuel id fuel left) (← expressionFuel id fuel right)
  | fuel + 1, .binaryApp op left right => do
      return pair (binaryName op) (← expressionFuel id fuel left) (← expressionFuel id fuel right)
  | fuel + 1, .getAttr left attr => do
      return obj [(".", obj [("left", ← expressionFuel id fuel left), ("attr", Lean.toJson attr)])]
  | fuel + 1, .hasAttr left attr => do
      return obj [("has", obj [("left", ← expressionFuel id fuel left), ("attr", Lean.toJson attr)])]
  | fuel + 1, .extHasAttr left attr attrs => do
      return obj [("has", obj [("left", ← expressionFuel id fuel left),
        ("attr", Lean.toJson (attr :: attrs))])]
  | fuel + 1, .unaryApp .not arg => do return unary "!" (← expressionFuel id fuel arg)
  | fuel + 1, .unaryApp .neg arg => do return unary "neg" (← expressionFuel id fuel arg)
  | fuel + 1, .unaryApp .isEmpty arg => do return unary "isEmpty" (← expressionFuel id fuel arg)
  | fuel + 1, .unaryApp (.is ty) arg => do
      return obj [("is", obj [("left", ← expressionFuel id fuel arg),
        ("entity_type", Lean.toJson (toString ty))])]
  | fuel + 1, .unaryApp (.like pattern) arg => do
      return obj [("like", obj [("left", ← expressionFuel id fuel arg),
        ("pattern", Lean.toJson (pattern.map patternElement))])]
  | fuel + 1, .ite cond yes no => do
      return obj [("if-then-else", obj [
        ("if", ← expressionFuel id fuel cond), ("then", ← expressionFuel id fuel yes),
        ("else", ← expressionFuel id fuel no)])]
  | fuel + 1, .set members => do
      return obj [("Set", Lean.toJson (← members.mapM (expressionFuel id fuel)))]
  | fuel + 1, .record fields => do
      if !(decide (fields.map Prod.fst).Nodup) then
        throw (.duplicateRecordKey id)
      let fields ← fields.mapM fun (key, value) => do
        return (key, ← expressionFuel id fuel value)
      return obj [("Record", obj fields)]
  | _, _ => .error (.unsupportedExpression id)

private def expression (id : PolicyID) (expr : Cedar.Spec.Expr) : Except Error Lean.Json :=
  expressionFuel id 1024 expr

private def condition (id : PolicyID) (c : Condition) : Except Error Lean.Json := do
  return obj [("kind", Lean.toJson (match c.kind with
    | .when => "when"
    | .unless => "unless")), ("body", ← expression id c.body)]

/-- Serialize a materialized Lean policy to Cedar's public JSON form. -/
def policy (value : Policy) : Except Error Lean.Json := do
  return obj [
    ("effect", Lean.toJson (match value.effect with
      | .permit => "permit"
      | .forbid => "forbid")),
    ("principal", ← scope value.principalScope.scope),
    ("action", ← actionScope value.id value.actionScope),
    ("resource", ← scope value.resourceScope.scope),
    ("conditions", Lean.toJson (← value.condition.mapM (condition value.id)))]

/-- A materialized policy set with no templates or links. -/
def policySet (policies : Policies) : Except Error Lean.Json := do
  let mut entries : List (String × Lean.Json) := []
  for value in policies do
    if entries.any (fun entry => entry.1 == value.id) then
      throw (.duplicatePolicyId value.id)
    entries := entries ++ [(value.id, ← policy value)]
  return obj [
    ("staticPolicies", obj entries),
    ("templates", obj []),
    ("templateLinks", Lean.toJson (#[] : Array Lean.Json))]

private def valueFuel : Nat → Value → Except Error Lean.Json
  | 0, _ => .error .valueDepthExceeded
  | _fuel + 1, .prim (.bool b) => .ok (Lean.toJson b)
  | _fuel + 1, .prim (.int n) => .ok (Lean.toJson n.toInt)
  | _fuel + 1, .prim (.string s) => .ok (Lean.toJson s)
  | _fuel + 1, .prim (.entityUID uid) => .ok (obj [("__entity", entity uid)])
  | fuel + 1, .set members => do
      return Lean.toJson (← members.toList.mapM (valueFuel fuel))
  | fuel + 1, .record attrs => do
      if !(decide (attrs.toList.map Prod.fst).Nodup) then
        throw .duplicateEntityAttribute
      let fields ← attrs.toList.mapM fun (key, val) => do
        return (key, ← valueFuel fuel val)
      return obj fields
  | _, .ext _ => .error .unsupportedValue

private def value (input : Value) : Except Error Lean.Json :=
  valueFuel 1024 input

private def attrs (values : Cedar.Data.Map String Value) : Except Error Lean.Json := do
  if !(decide (values.toList.map Prod.fst).Nodup) then
    throw .duplicateEntityAttribute
  let fields ← values.toList.mapM fun (key, val) => do
    return (key, ← value val)
  return obj fields

/-- Export Cedar entities using the public entity JSON format. -/
def entities (values : Cedar.Spec.Entities) : Except Error Lean.Json := do
  let rows ← Cedar.Data.Map.toList values |>.mapM fun (uid, data) => do
    return obj [
      ("uid", entity uid),
      ("attrs", ← attrs data.attrs),
      ("parents", Lean.toJson (data.ancestors.toList.map entity)),
      ("tags", ← attrs data.tags)]
  return Lean.toJson rows

/-- Export a request with explicit Cedar entity UIDs and context. -/
def request (req : Cedar.Spec.Request) : Except Error Lean.Json := do
  return obj [
    ("principal", Lean.toJson (toString req.principal)),
    ("action", Lean.toJson (toString req.action)),
    ("resource", Lean.toJson (toString req.resource)),
    ("context", ← attrs req.context)]

/-- Compile POO edits, then export the resulting ordinary Cedar policies. -/
def compiled (model : PolicyModules.Model) (root : String) :
    Except (Sum PolicyModules.Error Error) Lean.Json := do
  let policies ← (model.compile root).mapError Sum.inl
  (policySet policies).mapError Sum.inr

/-- A concrete Cedar authorization receipt for a compiled POO root. -/
def authorizationCase (name revision : String) (model : PolicyModules.Model)
    (root : String) (req : Request) (store : Entities) : Except String Lean.Json := do
  let convert {α β : Type} [Repr α] (result : Except α β) : Except String β :=
    result.mapError reprStr
  let policies ← convert (model.compile root)
  let exported ← convert (policySet policies)
  let exportedEntities ← convert (entities store)
  let exportedRequest ← convert (request req)
  let response := isAuthorized req store policies
  return obj [
    ("name", Lean.toJson name),
    ("revision", Lean.toJson revision),
    ("policy_ids", Lean.toJson (policies.map Policy.id)),
    ("policies", exported),
    ("entities", exportedEntities),
    ("request", exportedRequest),
    ("expected", Lean.toJson (match response.decision with
      | .allow => "allow"
      | .deny => "deny")),
    ("expected_errors", Lean.toJson response.erroringPolicies.toList.length)]

end CedarPooSpec.PolicyJson
