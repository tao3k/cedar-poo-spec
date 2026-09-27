import CedarPooSpec.PolicyJson
import Examples.Governance.TicketSharing

/-! Export the editable ticket-sharing templates beside their Lean-linked policies. -/

namespace CedarPooSpec.TemplateSourceExport

open CedarPooSpec.TicketSharingExample

theorem duplicateLinkIdsRejected :
    (match CedarPooSpec.PolicyJson.templateSet templatesV2
      (links ++ [linked "alice-ticket-a" "contributor" alice ticketA]) with
     | .error .duplicateTemplateLinkId => true
     | _ => false) = true := by
  native_decide

def bundle : Except String Lean.Json := do
  let source ←
    (CedarPooSpec.PolicyJson.templateSet revised.templates revised.links).mapError reprStr
  let materialized ←
    (CedarPooSpec.PolicyJson.policySet revised.validated.policies).mapError reprStr
  return Lean.Json.mkObj [("source", source), ("materialized", materialized)]

end CedarPooSpec.TemplateSourceExport

def main : IO Unit :=
  match CedarPooSpec.TemplateSourceExport.bundle with
  | .ok json => IO.println json.compress
  | .error error => throw (IO.userError error)
