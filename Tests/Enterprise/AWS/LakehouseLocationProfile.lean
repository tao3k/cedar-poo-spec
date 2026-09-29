import Examples.Enterprise.AWS.FinancialServices.LakehouseGateway.LakehouseGateway

namespace CedarPooSpec.AWS.LakehouseLocationProfileTest

open CedarPooSpec.LakehouseGatewayExample
open CedarPooSpec.Data.Lakehouse

def expectedRestricted : LocationBoundary :=
  let named := { euTemplate with policyId := "restricted-geography" }
  let withActions := { named with actionScope := .actionInAny tools }
  { withActions with deniedLocation := "RESTRICTED" }

def expectedUnresolved : LocationBoundary :=
  let named := { expectedRestricted with policyId := "unresolved-geography" }
  let unknown := { named with deniedLocation := "UNKNOWN" }
  { unknown with denyMissing := true }

theorem locationEditsPreserveTheParentAndRenderExactPolicies :
    euProfile.read .location = some "EU" ∧
    euProfile.read .denyMissing = some false ∧
    restrictedProfile.read .location = some "RESTRICTED" ∧
    restrictedProfile.read .denyMissing = some false ∧
    restrictedProfile.plan.precedence = ["RestrictedProfile", "EUProfile"] ∧
    unresolvedProfile.read .location = some "UNKNOWN" ∧
    unresolvedProfile.read .denyMissing = some true ∧
    unresolvedProfile.plan.precedence =
      ["UnresolvedProfile", "RestrictedProfile", "EUProfile"] ∧
    euControl.policy = euTemplate.policy ∧
    restrictedControl.policy = expectedRestricted.policy ∧
    unresolvedControl.policy = expectedUnresolved.policy := by
  native_decide

end CedarPooSpec.AWS.LakehouseLocationProfileTest
