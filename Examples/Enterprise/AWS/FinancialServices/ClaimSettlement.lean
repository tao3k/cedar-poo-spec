import Examples.Enterprise.AWS.FinancialServices.LakehouseGateway.LakehouseGateway
import Examples.Enterprise.AWS.FinancialServices.MultiAccountBanking.Lineage

/-! Proposed cross-organization claim-settlement plan. The lakehouse and
banking modules model separate published AWS examples; this composition is an
engineering scenario, not a claim that AWS deployed them together. A Cedar
allow represents one Gateway decision, never a claim-data receipt, delegated
identity, bank execution, or completed settlement. -/

namespace CedarPooSpec.AWS.ClaimSettlement

open Cedar.Spec

/-- The insurance adjuster and the banking operator are distinct identities.
    Their organizational handoff needs an independently verified binding. -/
structure Actors where
  adjuster : EntityUID
  bankOperator : EntityUID
  deriving BEq

def sampleActors : Actors :=
  ⟨CedarPooSpec.LakehouseGatewayExample.adjusterUS, CedarPooSpec.MultiAccountBankingExample.banker⟩

/-- A review plan draws from two claim-data calls and four banking calls.
    The latter retain the published bank route's Retail/Transaction owners. -/
structure Plan where
  actors : Actors
  claimsQuery : Decision
  claimDetails : Decision
  bankCalls : List CedarPooSpec.MultiAccountBankingLineage.PlannedCall
  requiresVerifiedHandoff : Bool

def planned (claimsRoot bankRoot mode : String) (actors : Actors)
    (geography : Option String) : Option Plan := do
  let claimsQuery ← CedarPooSpec.LakehouseGatewayExample.decideAt claimsRoot
    (CedarPooSpec.LakehouseGatewayExample.request actors.adjuster CedarPooSpec.LakehouseGatewayExample.queryClaims geography)
  let claimDetails ← CedarPooSpec.LakehouseGatewayExample.decideAt claimsRoot
    (CedarPooSpec.LakehouseGatewayExample.request actors.adjuster CedarPooSpec.LakehouseGatewayExample.claimDetails geography)
  let bankCalls ← CedarPooSpec.MultiAccountBankingLineage.transferRoute.mapM fun call =>
    CedarPooSpec.MultiAccountBankingLineage.plannedCall mode bankRoot
      { call with origin := actors.bankOperator }
  return ⟨actors, claimsQuery, claimDetails, bankCalls, true⟩

/-- Only Gateway decisions and POO-derived obligation plans are evaluated.
    The verified inter-organization handoff remains an external requirement. -/
def gatewayPlanAllows (claimsRoot bankRoot mode : String) (actors : Actors)
    (geography : Option String) : Bool :=
  match planned claimsRoot bankRoot mode actors geography with
  | none => false
  | some plan =>
      plan.claimsQuery == .allow && plan.claimDetails == .allow &&
      plan.bankCalls.length == CedarPooSpec.MultiAccountBankingLineage.transferRoute.length &&
      plan.bankCalls.all fun call =>
        call.gatewayDecision == .allow &&
        call.required.contains .userJwtAgentToGateway &&
        call.required.contains .cedarAtGateway &&
        call.required.contains .jwtAtLob

/-- The cross-domain chain needs both claims restrictions and the composed
    Retail/Transaction bank owners. Neither single bank owner can complete it. -/
theorem twoGatewaysAndOwners :
    gatewayPlanAllows "FailClosed" "OwnerCombined" "SourceM2M"
      sampleActors (some "US") = true ∧
    gatewayPlanAllows "FailClosed" "Retail" "SourceM2M"
      sampleActors (some "US") = false ∧
    gatewayPlanAllows "FailClosed" "Transaction" "SourceM2M"
      sampleActors (some "US") = false := by
  native_decide

/-- A transaction-owner overlay pauses settlement without rewriting the
    claims, Retail, Lending, or credential-mode modules. -/
theorem transactionPausePropagatesAcrossPlan :
    gatewayPlanAllows "FailClosed" "TransferPaused" "SourceM2M"
      sampleActors (some "US") = false ∧
    gatewayPlanAllows "FailClosed" "TransferResumed" "SourceM2M"
      sampleActors (some "US") = true := by
  native_decide

/-- An EU or unresolved claim-data request cannot produce an admissible
    Gateway plan, even if all banking owners would permit their local calls. -/
theorem claimsVetoStopsSettlementPlan :
    gatewayPlanAllows "FailClosed" "OwnerCombined" "SourceM2M"
      sampleActors (some "EU") = false ∧
    gatewayPlanAllows "FailClosed" "OwnerCombined" "SourceM2M"
      sampleActors none = false ∧
    gatewayPlanAllows "FailClosed" "OwnerCombined" "SourceM2M"
      sampleActors (some "UNKNOWN") = false := by
  native_decide

/-- The source-shaped claims root does not close the missing-geography gap;
    this distinguishes a local proposed extension from the published rules. -/
theorem sourceRootGapCrossesBoundary :
    gatewayPlanAllows "SourceCombined" "OwnerCombined" "SourceM2M"
      sampleActors none = true := by
  native_decide

/-- The Cedar tool decision alone cannot certify that a policyholder's
    returned claim belongs to the case later passed to the banking operator.
    Lake Formation and a trusted handoff must establish that separately. -/
theorem policyholderToolAccessIsNotClaimProvenance :
    gatewayPlanAllows "FailClosed" "OwnerCombined" "SourceM2M"
      { adjuster := CedarPooSpec.LakehouseGatewayExample.policyholderUS,
        bankOperator := CedarPooSpec.MultiAccountBankingExample.banker }
      (some "US") = true := by
  native_decide

/-- The plan carries two distinct actors and a required handoff; it does not
    equate the insurance user with the banking user. -/
theorem actorsStayDistinct :
    sampleActors.adjuster != sampleActors.bankOperator ∧
    (planned "FailClosed" "OwnerCombined" "SourceM2M"
      sampleActors (some "US")).toList.all
        (fun plan => plan.requiresVerifiedHandoff) = true := by
  native_decide

end CedarPooSpec.AWS.ClaimSettlement
