import Examples.Governance.AttestedDataAccess
import CedarPooSpec.PolicyJson

/-!
A network-boundary revision of the attested-data scenario. An upstream gateway
projects the verified source IP as a Cedar extension value; this model does
not authenticate the address or enforce the returned decision.
-/

namespace CedarPooSpec.TrustedNetworkDataAccessExample

open Cedar.Spec Cedar.Validation Cedar.Data CedarPooSpec.PolicyModules
open CedarPooSpec.AttestedDataAccessExample

def networkCondition (range : String) : Expr :=
  .call .isInRange [
    .getAttr (.var .context) "sourceIp",
    .call .ip [.lit (.string range)]]

def networkVeto (range : String) : Policy :=
  queryPolicy "network-boundary" .forbid
    (.unaryApp .not (networkCondition range))

def corporate : Module :=
  { name := "CorporateNetwork", parentOrders := [["GovernedV2"]],
    edits := [.extend (networkVeto "10.0.0.0/8")] }

def enclave : Module :=
  { name := "EnclaveNetwork", parentOrders := [["CorporateNetwork"]],
    edits := [.overlay (networkVeto "10.20.0.0/16")] }

def networkModel : Model :=
  { modules := CedarPooSpec.AttestedDataAccessExample.model.modules ++
      [corporate, enclave] }

def networkContextType : RecordType := Map.make
  (contextType.toList ++ [("sourceIp", .required (.ext .ipAddr))])

def networkActionEntry : ActionSchemaEntry :=
  ⟨Set.make [workerType], Set.make [datasetType], Set.empty, networkContextType⟩

def networkSchema : Schema :=
  ⟨schemaV2.ets, Map.make [(queryAction, networkActionEntry)]⟩

def networkEntities : Entities := Map.make
  (entities.toList.map fun (uid, data) =>
    if uid == queryAction then
      (uid, actionSchemaEntryToEntityData networkActionEntry)
    else (uid, data))

def officeIp : IPAddr :=
  (Ext.IPAddr.ip "10.20.1.7").get (by native_decide)
def otherCorporateIp : IPAddr :=
  (Ext.IPAddr.ip "10.30.1.7").get (by native_decide)
def outsideIp : IPAddr :=
  (Ext.IPAddr.ip "198.51.100.7").get (by native_decide)

def requestWithIp (dataset : EntityUID) (facts : Facts) (ip : IPAddr) : Request :=
  let original := request dataset facts
  let context := Map.make
    (original.context.toList ++ [("sourceIp", .ext (.ipaddr ip))])
  ⟨original.principal, original.action, original.resource, context⟩

def cases : List (String × String × Request × Decision) := [
  ("corporate-office", "CorporateNetwork",
    requestWithIp customerDataset {} officeIp, .allow),
  ("corporate-other-subnet", "CorporateNetwork",
    requestWithIp customerDataset {} otherCorporateIp, .allow),
  ("corporate-outside", "CorporateNetwork",
    requestWithIp customerDataset {} outsideIp, .deny),
  ("enclave-office", "EnclaveNetwork",
    requestWithIp customerDataset {} officeIp, .allow),
  ("enclave-other-subnet", "EnclaveNetwork",
    requestWithIp customerDataset {} otherCorporateIp, .deny),
  ("enclave-outside", "EnclaveNetwork",
    requestWithIp customerDataset {} outsideIp, .deny),
  ("enclave-stale-attestation", "EnclaveNetwork",
    requestWithIp customerDataset { attestationFresh := false } officeIp, .deny),
  ("enclave-owner-rejected", "EnclaveNetwork",
    requestWithIp customerDataset { ownerApproved := false } officeIp, .deny),
  ("enclave-other-project", "EnclaveNetwork",
    requestWithIp financeDataset {} officeIp, .deny)]

def decisionsExact : Bool :=
  cases.all fun (_, root, req, expected) =>
    match networkModel.compile root with
    | .error _ => false
    | .ok policies =>
        let response := isAuthorized req networkEntities policies
        response.decision == expected && response.erroringPolicies.isEmpty

theorem decisionsExactFully : decisionsExact = true := by native_decide

def policyRevision : Revision :=
  (networkModel.compileRevision "CorporateNetwork" "EnclaveNetwork").toOption.get
    (by native_decide)

theorem onlyNetworkBodyChanged :
    policyRevision.changedPolicyIds = ["network-boundary"] := by native_decide

theorem validatedRevisions :
    (validate policyRevision.beforePolicies networkSchema).isOk = true ∧
    (validate policyRevision.afterPolicies networkSchema).isOk = true := by
  native_decide

def earlierRootAllowsExternal : Bool :=
  match networkModel.compile "GovernedV2" with
  | .error _ => false
  | .ok policies =>
      (isAuthorized (requestWithIp customerDataset {} outsideIp)
        networkEntities policies).decision == .allow &&
      (isAuthorized (requestWithIp customerDataset {} outsideIp)
        networkEntities policyRevision.afterPolicies).decision == .deny

theorem externalAccessClosed : earlierRootAllowsExternal = true := by native_decide

end CedarPooSpec.TrustedNetworkDataAccessExample
