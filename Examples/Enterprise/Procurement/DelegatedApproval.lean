import Examples.Enterprise.Procurement.PurchaseApproval

/-!
Delegated procurement approval. The user remains the principal and the agent
is a request-context entity, following Cedar's documented viaAgent pattern.
The procurement rules and identities here are fictive.
-/

namespace CedarPooSpec.DelegatedApprovalExample

open Cedar.Spec Cedar.Data Cedar.Validation CedarPooSpec.PolicyModules
open CedarPooSpec.PurchaseApprovalExample

def agentType : EntityType := ⟨"Agent", []⟩
def purchasingBot : EntityUID := ⟨agentType, "purchasing-bot"⟩
def aliceBot : EntityUID := ⟨agentType, "alice-bot"⟩
def dormantBot : EntityUID := ⟨agentType, "dormant-bot"⟩
def missingBot : EntityUID := ⟨agentType, "missing-bot"⟩
def agentData (operator : EntityUID) (enabled : Bool) : EntityData :=
  { attrs := Map.make [
      ("operator", .prim (.entityUID operator)),
      ("enabled", .prim (.bool enabled))],
    ancestors := Set.empty, tags := Map.empty }

def delegatedEntities : Entities := Map.make [
  (alice, emptyData [approver]), (bob, emptyData [approver]),
  (approver, emptyData), (operations, emptyData), (research, emptyData),
  (operationsOrder, orderData alice operations),
  (researchOrder, orderData bob research),
  (purchasingBot, agentData bob true),
  (aliceBot, agentData alice true),
  (dormantBot, agentData bob false),
  (approve, emptyData)]

def agentEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.make [
    ("operator", .required (.entity userType)),
    ("enabled", .required (.bool .anyBool))], none⟩

def delegatedActionEntry : ActionSchemaEntry :=
  ⟨Set.make [userType], Set.make [orderType], Set.empty,
    Map.make [
      ("amount", .required (.ext .decimal)),
      ("viaAgent", .required (.entity agentType))]⟩

def delegatedSchema : Schema :=
  ⟨Map.make [(userType, userEntry), (roleType, roleEntry),
    (orderType, orderEntry), (groupType, groupEntry), (agentType, agentEntry)],
    Map.make [(approve, delegatedActionEntry)]⟩

def viaAgentExpr : Expr := .getAttr (.var .context) "viaAgent"
def agentIsOperator : Expr :=
  .binaryApp .eq (.getAttr viaAgentExpr "operator") (.var .principal)
def agentEnabled : Expr := .getAttr viaAgentExpr "enabled"
def validAgent : Expr :=
  .and (.hasAttr viaAgentExpr "operator")
    (.and (.hasAttr viaAgentExpr "enabled")
      (.and agentIsOperator agentEnabled))

def delegatedPermit : Policy :=
  { boundedPermit with condition := [{ kind := .when, body := .and withinBudget validAgent }] }

def revokeAgent : Policy :=
  { id := "revoke-purchasing-bot", effect := .forbid,
    principalScope := .principalScope (.mem approver),
    actionScope := .actionScope (.eq approve),
    resourceScope := .resourceScope (.mem operations),
    condition := [{ kind := .when, body := .binaryApp .eq viaAgentExpr (.lit (.entityUID purchasingBot)) }] }

def delegatedModel : Model := { modules := PurchaseApprovalExample.model.modules ++ [
  { name := "Delegated", parentOrders := [["Integrated"]],
    edits := [.overlay delegatedPermit] },
  { name := "Revoked", parentOrders := [["Delegated"]],
    edits := [.extend revokeAgent] }] }

def delegatedRequest (principal resource agent : EntityUID) (requested : String) : Request :=
  ⟨principal, approve, resource,
    Map.make [
      ("amount", .ext (.decimal (decimal requested))),
      ("viaAgent", .prim (.entityUID agent))]⟩

def delegatedCases : List (String × String × Request × Decision) := [
  ("delegated-active", "Delegated", delegatedRequest bob operationsOrder purchasingBot "250.0000", .allow),
  ("delegated-self-approval", "Delegated", delegatedRequest alice operationsOrder aliceBot "250.0000", .deny),
  ("delegated-over-limit", "Delegated", delegatedRequest bob operationsOrder purchasingBot "500.0001", .deny),
  ("delegated-zero", "Delegated", delegatedRequest bob operationsOrder purchasingBot "0.0000", .deny),
  ("delegated-negative", "Delegated", delegatedRequest bob operationsOrder purchasingBot "-1.0000", .deny),
  ("delegated-inactive-agent", "Delegated", delegatedRequest bob operationsOrder dormantBot "250.0000", .deny),
  ("delegated-missing-agent", "Delegated", delegatedRequest bob operationsOrder missingBot "250.0000", .deny),
  ("delegated-cross-department", "Delegated", delegatedRequest alice researchOrder aliceBot "250.0000", .deny),
  ("revoked-agent", "Revoked", delegatedRequest bob operationsOrder purchasingBot "250.0000", .deny),
  ("revoked-inactive-agent", "Revoked", delegatedRequest bob operationsOrder dormantBot "250.0000", .deny)]

def delegatedDecisionsExact : Bool := delegatedCases.all fun (_, root, req, expected) =>
  match delegatedModel.compile root with
  | .error _ => false
  | .ok policies =>
      let response := isAuthorized req delegatedEntities policies
      response.decision == expected && response.erroringPolicies.isEmpty

theorem delegatedDecisionsExactFully : delegatedDecisionsExact = true := by native_decide

theorem delegatedPublication :
    (CedarPooSpec.PolicyJson.publish delegatedModel "Delegated" delegatedSchema).isOk = true := by
  native_decide

theorem revokedPublication :
    (CedarPooSpec.PolicyJson.publish delegatedModel "Revoked" delegatedSchema).isOk = true := by
  native_decide

end CedarPooSpec.DelegatedApprovalExample
