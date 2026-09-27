import CedarPooSpec.PolicyJson

/-! Projection of the Gateway Cedar boundary in the AWS multi-account banking
sample. LOB JWT authorization, M2M exchange, IAM, and data access remain outside
this model. The owner-composed policy is an equivalent rewrite over the eighteen
named actions below, not a claim about the sample's deployed policy structure. -/

namespace CedarPooSpec.MultiAccountBankingExample

open Cedar.Spec Cedar.Data Cedar.Validation CedarPooSpec.PolicyModules

def userType : EntityType := ⟨"OAuthUser", ["AgentCore"]⟩
def gatewayType : EntityType := ⟨"Gateway", ["AgentCore"]⟩
def actionType : EntityType := ⟨"Action", ["AgentCore"]⟩

def banker : EntityUID := ⟨userType, "relationship-manager"⟩
def colleague : EntityUID := ⟨userType, "colleague"⟩
def gateway : EntityUID := ⟨gatewayType, "lobfederation-gateway"⟩
def customer : EntityUID := ⟨actionType, "retail-banking___get_customer"⟩
def accounts : EntityUID := ⟨actionType, "retail-banking___get_accounts"⟩
def balance : EntityUID := ⟨actionType, "retail-banking___get_balance"⟩
def profile : EntityUID := ⟨actionType, "retail-banking___get_profile"⟩
def updateBalance : EntityUID := ⟨actionType, "retail-banking___update_balance"⟩
def deleteCustomer : EntityUID := ⟨actionType, "retail-banking___delete_customer"⟩
def payments : EntityUID := ⟨actionType, "transaction-banking___get_payments"⟩
def transfer : EntityUID := ⟨actionType, "transaction-banking___transfer_funds"⟩
def beneficiaries : EntityUID := ⟨actionType, "transaction-banking___get_beneficiaries"⟩
def schedulePayment : EntityUID := ⟨actionType, "transaction-banking___schedule_payment"⟩
def loans : EntityUID := ⟨actionType, "lending-wealth___get_loans"⟩
def creditScore : EntityUID := ⟨actionType, "lending-wealth___get_credit_score"⟩
def eligibility : EntityUID := ⟨actionType, "lending-wealth___check_eligibility"⟩
def emiDetails : EntityUID := ⟨actionType, "lending-wealth___get_emi_details"⟩
def calculateEmi : EntityUID := ⟨actionType, "lending-wealth___calculate_emi"⟩
def lendingPolicy : EntityUID := ⟨actionType, "lending-wealth___search_lending_policies"⟩
def listTools : EntityUID := ⟨actionType, "tools/list"⟩
def initializeAction : EntityUID := ⟨actionType, "initialize"⟩

def retailTools : List EntityUID :=
  [customer, accounts, balance, profile, updateBalance, deleteCustomer]
def transactionTools : List EntityUID :=
  [payments, transfer, beneficiaries, schedulePayment]
def lendingTools : List EntityUID :=
  [loans, creditScore, eligibility, emiDetails, calculateEmi, lendingPolicy]
def protocolActions : List EntityUID := [listTools, initializeAction]
def namedActions : List EntityUID :=
  retailTools ++ transactionTools ++ lendingTools ++ protocolActions

def actionEntry : ActionSchemaEntry :=
  ⟨Set.make [userType], Set.make [gatewayType], Set.empty, Map.empty⟩
def schema : Schema :=
  ⟨Map.make [
    (userType, .standard ⟨Set.empty, Map.empty, none⟩),
    (gatewayType, .standard ⟨Set.empty, Map.empty, none⟩)],
    Map.make (namedActions.map (·, actionEntry))⟩

def emptyData : EntityData :=
  { attrs := Map.empty, ancestors := Set.empty, tags := Map.empty }
def entities : Entities := Map.make (
  [(banker, emptyData), (colleague, emptyData), (gateway, emptyData)] ++
    namedActions.map (·, emptyData))
def request (user action : EntityUID) : Request :=
  ⟨user, action, gateway, Map.empty⟩

def permitActions (id : String) (actions : List EntityUID) : Policy :=
  { id, effect := .permit,
    principalScope := .principalScope (.is userType),
    actionScope := .actionInAny actions,
    resourceScope := .resourceScope (.eq gateway),
    condition := [] }

def retailPermit : Policy :=
  permitActions "retail-owned-tools" (retailTools.filter (· != deleteCustomer))
def transactionPermit : Policy :=
  permitActions "transaction-owned-tools" transactionTools
def lendingPermit : Policy :=
  permitActions "lending-owned-tools" lendingTools
def protocolPermit : Policy :=
  permitActions "gateway-protocol" protocolActions
def broadPermit : Policy :=
  { permitActions "sample-broad-permit" namedActions with
    actionScope := .actionScope .any }
def deleteVeto : Policy :=
  { id := "sample-delete-customer-veto", effect := .forbid,
    principalScope := .principalScope (.is userType),
    actionScope := .actionScope (.eq deleteCustomer),
    resourceScope := .resourceScope (.eq gateway),
    condition := [] }

/-- The sample's broad grant and delete veto are compared with a POO rewrite
    that assigns all sixteen published tools to independent LOB owners. -/
def model : Model := { modules := [
  { name := "Gateway", edits := [.extend deleteVeto] },
  { name := "SampleBroad", parentOrders := [["Gateway"]],
    edits := [.extend broadPermit] },
  { name := "Protocol", parentOrders := [["Gateway"]],
    edits := [.extend protocolPermit] },
  { name := "Retail", parentOrders := [["Gateway"]],
    edits := [.extend retailPermit] },
  { name := "Transaction", parentOrders := [["Gateway"]],
    edits := [.extend transactionPermit] },
  { name := "Lending", parentOrders := [["Gateway"]],
    edits := [.extend lendingPermit] },
  { name := "OwnerCombined", parentOrders := [["Retail", "Transaction", "Lending", "Protocol"]] }] }

def decideAt (root : String) (req : Request) : Option Decision := do
  let policies ← (model.compile root).toOption
  let response := isAuthorized req entities policies
  if response.erroringPolicies.isEmpty then some response.decision else none

def expected (action : EntityUID) : Decision :=
  if action == deleteCustomer then .deny else .allow

theorem sourceNamedDecisions :
    [banker, colleague].all (fun user =>
      namedActions.all (fun action =>
        decideAt "SampleBroad" (request user action) == some (expected action))) = true := by
  native_decide

theorem ownerRewriteNamedDecisions :
    [banker, colleague].all (fun user =>
      namedActions.all (fun action =>
        decideAt "OwnerCombined" (request user action) ==
          decideAt "SampleBroad" (request user action))) = true := by
  native_decide

/-- The source's transfer scenario crosses two LOB tools. Neither owner-local
    branch can authorize the entire sequence; their C4 composition can. -/
theorem transferRequiresBothOwners :
    decideAt "Retail" (request banker updateBalance) = some .allow ∧
    decideAt "Retail" (request banker transfer) = some .deny ∧
    decideAt "Transaction" (request banker updateBalance) = some .deny ∧
    decideAt "Transaction" (request banker transfer) = some .allow ∧
    decideAt "OwnerCombined" (request banker updateBalance) = some .allow ∧
    decideAt "OwnerCombined" (request banker transfer) = some .allow := by
  native_decide

theorem lendingNeedsItsOwner :
    decideAt "Retail" (request banker creditScore) = some .deny ∧
    decideAt "OwnerCombined" (request banker creditScore) = some .allow ∧
    decideAt "OwnerCombined" (request banker lendingPolicy) = some .allow := by
  native_decide

theorem allRootsValidated :
    ["Gateway", "SampleBroad", "Protocol", "Retail", "Transaction", "Lending",
      "OwnerCombined"].all (fun root =>
        (CedarPooSpec.PolicyJson.publish model root schema).isOk) = true := by
  native_decide

end CedarPooSpec.MultiAccountBankingExample
