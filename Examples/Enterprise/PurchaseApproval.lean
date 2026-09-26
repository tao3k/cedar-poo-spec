import CedarPooSpec.PolicyJson

/-!
A procurement authorization model combining Cedar decimal amounts with
separation of duties. Amount limits, organization, and identities are fictive.
-/

namespace CedarPooSpec.PurchaseApprovalExample

open Cedar.Spec Cedar.Data CedarPooSpec.PolicyModules

def userType : EntityType := ⟨"User", []⟩
def roleType : EntityType := ⟨"Role", []⟩
def orderType : EntityType := ⟨"PurchaseOrder", []⟩
def groupType : EntityType := ⟨"OrderGroup", []⟩
def actionType : EntityType := ⟨"Action", []⟩
def alice : EntityUID := ⟨userType, "alice"⟩
def bob : EntityUID := ⟨userType, "bob"⟩
def approver : EntityUID := ⟨roleType, "Approver"⟩
def operations : EntityUID := ⟨groupType, "Operations"⟩
def research : EntityUID := ⟨groupType, "Research"⟩
def operationsOrder : EntityUID := ⟨orderType, "ops-1"⟩
def researchOrder : EntityUID := ⟨orderType, "research-1"⟩
def approve : EntityUID := ⟨actionType, "approve"⟩

def decimal (value : String) : Cedar.Spec.Ext.Decimal :=
  match Cedar.Spec.Ext.Decimal.decimal value with
  | some amount => amount
  | none => panic! s!"invalid example amount: {value}"

def orderData (owner group : EntityUID) : EntityData :=
  { attrs := Map.make [
      ("requester", .prim (.entityUID owner)),
      ("limit", .ext (.decimal (decimal "500.0000")))],
    ancestors := Set.make [group], tags := Map.empty }

def emptyData (parents : List EntityUID := []) : EntityData :=
  { attrs := Map.empty, ancestors := Set.make parents, tags := Map.empty }

def entities : Entities := Map.make [
  (alice, emptyData [approver]), (bob, emptyData [approver]),
  (approver, emptyData), (operations, emptyData), (research, emptyData),
  (operationsOrder, orderData alice operations),
  (researchOrder, orderData bob research),
  (approve, emptyData)]

def amount : Expr := .getAttr (.var .context) "amount"
def limit : Expr := .getAttr (.var .resource) "limit"
def withinLimit : Expr := .call .lessThanOrEqual [amount, limit]
def selfApproval : Expr :=
  .binaryApp .eq (.var .principal) (.getAttr (.var .resource) "requester")

def legacyPermit : Policy :=
  { id := "operations-approval", effect := .permit,
    principalScope := .principalScope (.mem approver),
    actionScope := .actionScope (.eq approve),
    resourceScope := .resourceScope (.mem operations),
    condition := [] }

def boundedPermit : Policy :=
  { legacyPermit with condition := [{ kind := .when, body := withinLimit }] }

def dutiesVeto : Policy :=
  { id := "no-self-approval", effect := .forbid,
    principalScope := .principalScope (.mem approver),
    actionScope := .actionScope (.eq approve),
    resourceScope := .resourceScope (.is orderType),
    condition := [{ kind := .when, body := selfApproval }] }

def model : Model := { modules := [
  { name := "Base", edits := [.extend legacyPermit] },
  { name := "Budget", parentOrders := [["Base"]],
    edits := [.overlay boundedPermit] },
  { name := "Duties", parentOrders := [["Base"]],
    edits := [.extend dutiesVeto] },
  { name := "Integrated", parentOrders := [["Budget", "Duties"]] }] }

def request (principal resource : EntityUID) (requested : String) : Request :=
  ⟨principal, approve, resource,
    Map.make [("amount", .ext (.decimal (decimal requested)))]⟩

def cases : List (String × String × Request × Decision) := [
  ("base-self-over-limit", "Base", request alice operationsOrder "500.0001", .allow),
  ("budget-self-under-limit", "Budget", request alice operationsOrder "499.9999", .allow),
  ("duties-other-over-limit", "Duties", request bob operationsOrder "500.0001", .allow),
  ("integrated-self-under-limit", "Integrated", request alice operationsOrder "499.9999", .deny),
  ("integrated-other-exact-limit", "Integrated", request bob operationsOrder "500.0000", .allow),
  ("integrated-other-over-limit", "Integrated", request bob operationsOrder "500.0001", .deny),
  ("integrated-other-zero", "Integrated", request bob operationsOrder "0.0000", .allow),
  ("integrated-cross-department", "Integrated", request alice researchOrder "10.0000", .deny)]

def decisionsExact : Bool := cases.all fun (_, root, req, expected) =>
  match model.compile root with
  | .error _ => false
  | .ok policies =>
      let response := isAuthorized req entities policies
      response.decision == expected && response.erroringPolicies.isEmpty

theorem decisionsExactFully : decisionsExact = true := by native_decide

theorem budgetEditLocal :
    ((model.compileRevision "Base" "Budget").toOption.get
      (by native_decide)).changedPolicyIds = ["operations-approval"] := by native_decide

end CedarPooSpec.PurchaseApprovalExample
