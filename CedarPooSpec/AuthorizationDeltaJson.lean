import CedarPooSpec.AuthorizationDelta
import CedarPooSpec.PolicyJson

/-! JSON projection for authorization-delta reports and Cedar replay cases. -/

namespace CedarPooSpec.AuthorizationDeltaJson

open CedarPooSpec.AuthorizationDelta CedarPooSpec.PolicyModules

private def change (witness : Cedar.Spec.Env)
    (beforeResponse afterResponse : Cedar.Spec.Response) : Except String Lean.Json := do
  let request ← CedarPooSpec.PolicyJson.request witness.request |>.mapError reprStr
  let entities ← CedarPooSpec.PolicyJson.entities witness.entities |>.mapError reprStr
  return Lean.Json.mkObj [
    ("request", request),
    ("entities", entities),
    ("before_decision", Lean.toJson beforeResponse.decision),
    ("after_decision", Lean.toJson afterResponse.decision),
    ("before_reasons", Lean.toJson beforeResponse.determiningPolicies.toList),
    ("after_reasons", Lean.toJson afterResponse.determiningPolicies.toList)]

def expansion (item : Expansion) : Except String Lean.Json :=
  change item.witness item.beforeResponse item.afterResponse

def contraction (item : Contraction) : Except String Lean.Json :=
  change item.witness item.beforeResponse item.afterResponse

def report (item : Report) : Except String Lean.Json := do
  let expansions ← item.expansions.mapM expansion
  return Lean.Json.mkObj [
    ("status", Lean.toJson (if item.noExpansion then "no-expansion-in-schema" else "expanded")),
    ("changed_policy_ids", Lean.toJson item.changedPolicyIds),
    ("environments_checked", Lean.toJson item.environmentsChecked),
    ("counterexamples", Lean.toJson expansions)]

def impactReport (item : ImpactReport) : Except String Lean.Json := do
  let gains ← item.gains.mapM expansion
  let losses ← item.losses.mapM contraction
  return Lean.Json.mkObj [
    ("changed_policy_ids", Lean.toJson item.changedPolicyIds),
    ("environments_checked", Lean.toJson item.environmentsChecked),
    ("gains", Lean.toJson gains),
    ("losses", Lean.toJson losses)]

def witnessCases (item : Report) (model : Model)
    (beforeRoot afterRoot : String) : Except String Lean.Json := do
  let cases ← item.expansions.zipIdx.mapM fun (entry, index) => do
    let before ← CedarPooSpec.PolicyJson.authorizationCase s!"delta-before-{index}"
      beforeRoot model beforeRoot entry.witness.request entry.witness.entities
    let after ← CedarPooSpec.PolicyJson.authorizationCase s!"delta-after-{index}"
      afterRoot model afterRoot entry.witness.request entry.witness.entities
    return [before, after]
  return Lean.Json.mkObj [("cases", Lean.toJson cases.flatten)]

/-- Replay both directions using the original before and after roots. -/
def impactWitnessCases (item : ImpactReport) (model : Model)
    (beforeRoot afterRoot : String) : Except String Lean.Json := do
  let witnesses := item.gains.map (·.witness) ++ item.losses.map (·.witness)
  let cases ← witnesses.zipIdx.mapM fun (witness, index) => do
    let before ← CedarPooSpec.PolicyJson.authorizationCase s!"impact-before-{index}"
      beforeRoot model beforeRoot witness.request witness.entities
    let after ← CedarPooSpec.PolicyJson.authorizationCase s!"impact-after-{index}"
      afterRoot model afterRoot witness.request witness.entities
    return [before, after]
  return Lean.Json.mkObj [("cases", Lean.toJson cases.flatten)]

/-- Preserve both concrete Host snapshots; they need not share context or
    entity attributes, only the principal/action/resource identity. -/
def snapshotReport (item : SnapshotImpact) (before after : Cedar.Spec.Env) :
    Except String Lean.Json := do
  let beforeRequest ← CedarPooSpec.PolicyJson.request before.request |>.mapError reprStr
  let afterRequest ← CedarPooSpec.PolicyJson.request after.request |>.mapError reprStr
  let beforeEntities ← CedarPooSpec.PolicyJson.entities before.entities |>.mapError reprStr
  let afterEntities ← CedarPooSpec.PolicyJson.entities after.entities |>.mapError reprStr
  return Lean.Json.mkObj [
    ("before_request", beforeRequest), ("after_request", afterRequest),
    ("before_entities", beforeEntities), ("after_entities", afterEntities),
    ("before_decision", Lean.toJson item.beforeResponse.decision),
    ("after_decision", Lean.toJson item.afterResponse.decision)]

def snapshotCases (name : String) (model : Model) (beforeRoot afterRoot : String)
    (before after : Cedar.Spec.Env) : Except String Lean.Json := do
  let beforeCase ← CedarPooSpec.PolicyJson.authorizationCase s!"{name}-before"
    beforeRoot model beforeRoot before.request before.entities
  let afterCase ← CedarPooSpec.PolicyJson.authorizationCase s!"{name}-after"
    afterRoot model afterRoot after.request after.entities
  return Lean.Json.mkObj [("cases", Lean.toJson [beforeCase, afterCase])]

end CedarPooSpec.AuthorizationDeltaJson
