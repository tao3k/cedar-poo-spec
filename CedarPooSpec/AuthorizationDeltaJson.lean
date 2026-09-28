import CedarPooSpec.AuthorizationDelta
import CedarPooSpec.PolicyJson

/-! JSON projection for authorization-delta reports and Cedar replay cases. -/

namespace CedarPooSpec.AuthorizationDeltaJson

open CedarPooSpec.AuthorizationDelta CedarPooSpec.PolicyModules

def expansion (item : Expansion) : Except String Lean.Json := do
  let request ← CedarPooSpec.PolicyJson.request item.witness.request |>.mapError reprStr
  let entities ← CedarPooSpec.PolicyJson.entities item.witness.entities |>.mapError reprStr
  return Lean.Json.mkObj [
    ("request", request),
    ("entities", entities),
    ("before_decision", Lean.toJson item.beforeResponse.decision),
    ("after_decision", Lean.toJson item.afterResponse.decision),
    ("before_reasons", Lean.toJson item.beforeResponse.determiningPolicies.toList),
    ("after_reasons", Lean.toJson item.afterResponse.determiningPolicies.toList)]

def report (item : Report) : Except String Lean.Json := do
  let expansions ← item.expansions.mapM expansion
  return Lean.Json.mkObj [
    ("status", Lean.toJson (if item.noExpansion then "no-expansion-in-schema" else "expanded")),
    ("changed_policy_ids", Lean.toJson item.changedPolicyIds),
    ("environments_checked", Lean.toJson item.environmentsChecked),
    ("counterexamples", Lean.toJson expansions)]

def witnessCases (item : Report) (model : Model)
    (beforeRoot afterRoot : String) : Except String Lean.Json := do
  let cases ← item.expansions.zipIdx.mapM fun (entry, index) => do
    let before ← CedarPooSpec.PolicyJson.authorizationCase s!"delta-before-{index}"
      beforeRoot model beforeRoot entry.witness.request entry.witness.entities
    let after ← CedarPooSpec.PolicyJson.authorizationCase s!"delta-after-{index}"
      afterRoot model afterRoot entry.witness.request entry.witness.entities
    return [before, after]
  return Lean.Json.mkObj [("cases", Lean.toJson cases.flatten)]

end CedarPooSpec.AuthorizationDeltaJson
