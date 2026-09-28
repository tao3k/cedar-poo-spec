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

/-- Keep the viewer grant static while contributor grants remain linked. -/
def staticViewer : Cedar.Spec.Policy :=
  (viewer.link? "bob-ticket-a" (slotEnv bob ticketA)).toOption.get (by native_decide)

def contributorLinks : Cedar.Spec.TemplateLinkedPolicies :=
  links.filter fun link => link.id != "bob-ticket-a"

def contributorTemplates : Cedar.Spec.Templates :=
  Cedar.Data.Map.make [("contributor", contributorV2)]

theorem unlinkedTemplateRejected :
    (match CedarPooSpec.PolicyJson.sourceSet [staticViewer] templatesV2 contributorLinks with
     | .error (.unlinkedTemplateId "viewer") => true
     | _ => false) = true := by
  native_decide

theorem staticLinkCollisionRejected :
    (match CedarPooSpec.PolicyJson.sourceSet [staticViewer] templatesV2 links with
     | .error (.duplicatePolicyId "bob-ticket-a") => true
     | _ => false) = true := by
  native_decide

def mixedBundle : Except String Lean.Json := do
  let source ←
    (CedarPooSpec.PolicyJson.sourceSet [staticViewer] contributorTemplates contributorLinks).mapError
      reprStr
  let materialized ←
    (CedarPooSpec.PolicyJson.policySet revised.validated.policies).mapError reprStr
  return Lean.Json.mkObj [("source", source), ("materialized", materialized)]

end CedarPooSpec.TemplateSourceExport

def main (args : List String) : IO Unit := do
  let result ← match args with
    | [] => pure CedarPooSpec.TemplateSourceExport.bundle
    | ["mixed"] => pure CedarPooSpec.TemplateSourceExport.mixedBundle
    | _ => throw (IO.userError "usage: TemplateSourceExport [mixed]")
  match result with
  | .ok json => IO.println json.compress
  | .error error => throw (IO.userError error)
