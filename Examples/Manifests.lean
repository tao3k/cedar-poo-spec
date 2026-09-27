import Examples.Governance.TicketSharingExport
import Examples.Health.ClinicalBreakGlassExport
import Examples.Health.WearableTriageExport
import Examples.Governance.AttestedDataAccessExport
import Examples.Governance.AttestedSchemaEvolutionExport
import Examples.Language.ScopeAndPatternExport
import Examples.Language.ScopeAndPatternValidatedExport
import Examples.Language.NamespacedEnumValidatedExport
import Examples.Governance.TrustedNetworkDataAccessExport
import Examples.Governance.TrustedNetworkValidatedExport
import Examples.Governance.CountryApprovalExport
import Examples.Governance.CountryApprovalValidatedExport
import Examples.Enterprise.Procurement.PurchaseApprovalExport
import Examples.Enterprise.Procurement.DelegatedApprovalExport
import Examples.Enterprise.Procurement.DelegatedApprovalMatrixExport
import Examples.Enterprise.Payment.PaymentReleaseExport
import Examples.Enterprise.Agent.Delegation.AgentDelegationExport
import Examples.Enterprise.Agent.Chain.AgentChainExport
import Examples.Enterprise.Agent.Payment.AgentPaymentExport
import Examples.Enterprise.Agent.Payment.ValidatedExport
import Examples.Enterprise.Agent.DataFlow.AgentDataFlowExport
import Examples.Enterprise.Agent.DataFlow.ValidatedExport
import Examples.Enterprise.Agent.LakehouseGateway.ValidatedExport
import Examples.Enterprise.Agent.MultiAccountBanking.ValidatedExport
import Examples.Enterprise.Agent.Session.BoundedSessionExport
import Examples.Enterprise.Agent.Fanout.SharedBudgetExport
import Examples.Enterprise.Exchange.Signing.SigningBoundaryExport
import Examples.Enterprise.Exchange.Signing.SigningValidatedExport
import Examples.Enterprise.Vehicle.Uptane.SupplierTransitionExport
import Examples.Enterprise.Vehicle.VLA.CommandBoundaryExport
import Examples.Enterprise.Vehicle.Mission.SuccessorBoundaryExport
import Examples.Language.ExtensionCoverageExport
import Examples.Scenarios.TenantDevicePolicyEvolutionExport

/-! Evaluate the same pure manifest definitions in one Lean process. -/

namespace CedarPooSpec.Manifests

def entries : List (String × (Unit → Except String Lean.Json)) := [
  ("ticket-sharing", fun _ => TicketSharingExport.manifest),
  ("clinical", fun _ => ClinicalBreakGlassExport.manifest),
  ("wearable-triage", fun _ => WearableTriageExport.manifest),
  ("attested", fun _ => AttestedDataAccessExport.manifest),
  ("attested-schema-evolution", fun _ => AttestedSchemaEvolutionExport.bundle),
  ("scope-pattern", fun _ => ScopeAndPatternExport.manifest),
  ("scope-pattern-validated", fun _ => ScopeAndPatternValidatedExport.manifest),
  ("namespaced-enum-validated", fun _ => NamespacedEnumValidatedExport.manifest),
  ("network", fun _ => TrustedNetworkDataAccessExport.manifest),
  ("network-validated", fun _ => TrustedNetworkValidatedExport.manifest),
  ("country-approval", fun _ => CountryApprovalExport.manifest),
  ("country-approval-validated", fun _ => CountryApprovalValidatedExport.manifest),
  ("purchase-approval", fun _ => PurchaseApprovalExport.manifest),
  ("delegated-approval", fun _ => DelegatedApprovalExport.manifest),
  ("delegated-matrix", fun _ => DelegatedApprovalMatrixExport.manifest),
  ("payment-release", fun _ => PaymentReleaseExport.manifest),
  ("agent-delegation", fun _ => AgentDelegationExport.manifest),
  ("agent-chain", fun _ => AgentChainExport.manifest),
  ("agent-payment", fun _ => AgentPaymentExport.manifest),
  ("agent-payment-validated", fun _ => AgentPaymentValidatedExport.manifest),
  ("agent-data-flow", fun _ => AgentDataFlowExport.manifest),
  ("agent-data-flow-validated", fun _ => AgentDataFlowValidatedExport.manifest),
  ("lakehouse-gateway-validated", fun _ => LakehouseGatewayValidatedExport.manifest),
  ("multi-account-banking-validated", fun _ => MultiAccountBankingValidatedExport.manifest),
  ("bounded-session", fun _ => BoundedSessionExport.manifest),
  ("shared-budget", fun _ => SharedBudgetExport.manifest),
  ("exchange-signing", fun _ => ExchangeSigningExport.manifest),
  ("exchange-signing-validated", fun _ => ExchangeSigningValidatedExport.manifest),
  ("supplier-transition", fun _ => SupplierTransitionExport.manifest),
  ("vla-command", fun _ => VlaCommandBoundaryExport.manifest),
  ("mission-successor", fun _ => SuccessorBoundaryExport.manifest),
  ("extension-coverage", fun _ => ExtensionCoverageExport.manifest),
  ("tenant-device", fun _ => TenantDevicePolicyEvolutionExport.manifest)]

def evaluate (produce : Unit → Except String Lean.Json) : IO Lean.Json :=
  match produce () with
  | .ok json => pure json
  | .error message => throw (IO.userError message)

def run (args : List String) : IO Unit :=
  match args with
  | ["all"] => do
      let outputs ← entries.mapM fun (name, produce) => do
        let json ← evaluate produce
        pure (name, json)
      for (name, json) in outputs do
        IO.FS.writeFile s!".lake/build/{name}-manifest.json" json.compress
  | [name] =>
      match entries.find? (fun entry => entry.1 == name) with
      | some (_, produce) => do
          let json ← evaluate produce
          IO.println json.compress
      | none => throw (IO.userError s!"unknown manifest: {name}")
  | _ => throw (IO.userError "expected a manifest name or all")

end CedarPooSpec.Manifests

def main (args : List String) : IO Unit := CedarPooSpec.Manifests.run args
