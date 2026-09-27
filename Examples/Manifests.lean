import Examples.Governance.TicketSharingExport
import Examples.Health.ClinicalBreakGlassExport
import Examples.Health.WearableTriageExport
import Examples.Governance.AttestedDataAccessExport
import Examples.Language.ScopeAndPatternExport
import Examples.Governance.TrustedNetworkDataAccessExport
import Examples.Governance.CountryApprovalExport
import Examples.Enterprise.Procurement.PurchaseApprovalExport
import Examples.Enterprise.Procurement.DelegatedApprovalExport
import Examples.Enterprise.Procurement.DelegatedApprovalMatrixExport
import Examples.Enterprise.Payment.PaymentReleaseExport
import Examples.Enterprise.Agent.Delegation.AgentDelegationExport
import Examples.Enterprise.Agent.Chain.AgentChainExport
import Examples.Enterprise.Agent.Payment.AgentPaymentExport
import Examples.Enterprise.Agent.DataFlow.AgentDataFlowExport
import Examples.Enterprise.Vehicle.SupplierTransitionExport
import Examples.Language.ExtensionCoverageExport

/-! Evaluate the same pure manifest definitions in one Lean process. -/

namespace CedarPooSpec.Manifests

def entries : List (String × (Unit → Except String Lean.Json)) := [
  ("ticket-sharing", fun _ => TicketSharingExport.manifest),
  ("clinical", fun _ => ClinicalBreakGlassExport.manifest),
  ("wearable-triage", fun _ => WearableTriageExport.manifest),
  ("attested", fun _ => AttestedDataAccessExport.manifest),
  ("scope-pattern", fun _ => ScopeAndPatternExport.manifest),
  ("network", fun _ => TrustedNetworkDataAccessExport.manifest),
  ("country-approval", fun _ => CountryApprovalExport.manifest),
  ("purchase-approval", fun _ => PurchaseApprovalExport.manifest),
  ("delegated-approval", fun _ => DelegatedApprovalExport.manifest),
  ("delegated-matrix", fun _ => DelegatedApprovalMatrixExport.manifest),
  ("payment-release", fun _ => PaymentReleaseExport.manifest),
  ("agent-delegation", fun _ => AgentDelegationExport.manifest),
  ("agent-chain", fun _ => AgentChainExport.manifest),
  ("agent-payment", fun _ => AgentPaymentExport.manifest),
  ("agent-data-flow", fun _ => AgentDataFlowExport.manifest),
  ("supplier-transition", fun _ => SupplierTransitionExport.manifest),
  ("extension-coverage", fun _ => ExtensionCoverageExport.manifest)]

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
