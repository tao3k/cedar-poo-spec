import Examples.Scenarios.TenantDevicePolicyEvolution
import CedarPooSpec.PolicyJson

/-! Export every POO revision and named tenant/device decision to Cedar Rust. -/

namespace CedarPooSpec.TenantDevicePolicyEvolutionExport

open CedarPooSpec.TenantDeviceAuthorizationExample

def manifest : Except String Lean.Json := do
  let rows ← expectedDecisions.zipIdx.mapM fun ((root, req, _), index) =>
    CedarPooSpec.PolicyJson.authorizationCase
      s!"{root.toLower}-case-{index}" root.toLower model root req entities
  return Lean.Json.mkObj [("cases", Lean.toJson rows)]

end CedarPooSpec.TenantDevicePolicyEvolutionExport
