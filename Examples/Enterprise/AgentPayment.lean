import Examples.Enterprise.AgentDelegation

/-!
Per-call value authorization for an AI agent's payment tool request. The
amount, account, and originating user are checked on each proposed call.
-/

namespace CedarPooSpec.AgentPaymentExample

open Cedar.Spec Cedar.Data Cedar.Validation CedarPooSpec.PolicyModules
open CedarPooSpec.AgentDelegationExample

def accountType : EntityType := ⟨"Account", []⟩
def accountGroupType : EntityType := ⟨"AccountGroup", []⟩
def financeBot : EntityUID := ⟨agentType, "finance-bot"⟩
def paymentTool : EntityUID := ⟨toolType, "process-payment"⟩
def approvedGroup : EntityUID := ⟨accountGroupType, "Approved"⟩
def externalGroup : EntityUID := ⟨accountGroupType, "External"⟩
def approvedAccount : EntityUID := ⟨accountType, "approved"⟩
def externalAccount : EntityUID := ⟨accountType, "external"⟩
def transfer : EntityUID := ⟨actionType, "transfer"⟩

def paymentEntities : Entities := Map.make (entities.toList ++ [
  (financeBot, agentData 4 "payments" "production" ["process_payment"]),
  (paymentTool, emptyData),
  (approvedGroup, emptyData), (externalGroup, emptyData),
  (approvedAccount, { emptyData with ancestors := Set.make [approvedGroup] }),
  (externalAccount, { emptyData with ancestors := Set.make [externalGroup] }),
  (transfer, emptyData)])

def accountEntry : EntitySchemaEntry :=
  .standard ⟨Set.make [accountGroupType], Map.empty, none⟩
def paymentActionEntry : ActionSchemaEntry :=
  ⟨Set.make [agentType], Set.make [accountType], Set.empty,
    Map.make [("amount", .required (.ext .decimal)),
      ("origin", .required (.entity userType))]⟩
def paymentSchema : Schema :=
  ⟨Map.make (schema.ets.toList ++ [
      (accountType, accountEntry), (accountGroupType, emptyEntry)]),
    Map.make (schema.acts.toList ++ [(transfer, paymentActionEntry)])⟩

def decimal (text : String) : Cedar.Spec.Ext.Decimal :=
  match Cedar.Spec.Ext.Decimal.decimal text with
  | some value => value
  | none => panic! s!"invalid transfer amount: {text}"

def amount : Expr := ctx "amount"
def positive : Expr :=
  .call .greaterThan [amount, .call .decimal [.lit (.string "0.0000")]]
def withinCeiling : Expr :=
  .call .lessThanOrEqual [amount, .call .decimal [.lit (.string "100.0000")]]
def originAuthorized : Expr :=
  .and (.binaryApp .mem (ctx "origin") (.lit (.entityUID adminRole)))
    (.getAttr (ctx "origin") "mfa")

def financeToolPolicy : Policy :=
  policy "finance-agent-tool" invoke (.eq financeBot) (.eq paymentTool)
    (.and (.binaryApp .lessEq (.lit (.int 3)) (principalFact "trust"))
      (.and (eq (principalFact "namespace") (.lit (.string "payments")))
        (eq (principalFact "stage") (.lit (.string "production")))))

def paymentBase : Policy :=
  policy "agent-payment" transfer (.eq financeBot) .any (.lit (.bool true))
def paymentScoped : Policy :=
  { paymentBase with resourceScope := .resourceScope (.mem approvedGroup) }
def paymentCapped : Policy :=
  { paymentScoped with condition := [{ kind := .when, body := .and positive withinCeiling }] }
def paymentHuman : Policy :=
  { paymentCapped with condition := [
      { kind := .when, body := .and (.and positive withinCeiling) originAuthorized }] }

def paymentModel : Model := { modules := model.modules ++ [
  { name := "FinanceTool", edits := [.extend financeToolPolicy] },
  { name := "PaymentBase", edits := [.extend paymentBase] },
  { name := "PaymentScoped", parentOrders := [["PaymentBase"]],
    edits := [.overlay paymentScoped] },
  { name := "PaymentCapped", parentOrders := [["PaymentScoped"]],
    edits := [.overlay paymentCapped] },
  { name := "PaymentHuman", parentOrders := [["PaymentCapped"]],
    edits := [.overlay paymentHuman] }] }

def paymentRequest (account origin : EntityUID) (requested : String) : Request :=
  ⟨financeBot, transfer, account, Map.make [
    ("amount", .ext (.decimal (decimal requested))),
    ("origin", .prim (.entityUID origin))]⟩

def checks (root : String) (account origin : EntityUID) (requested : String) :
    List (String × Request) := [
  ("FinanceTool", requestTool financeBot paymentTool),
  (root, paymentRequest account origin requested)]

def authorizePayment (root : String) (account origin : EntityUID)
    (requested : String) : Bool :=
  match CedarPooSpec.CompoundAuthorization.authorizeLayers paymentModel
      (checks root account origin requested) paymentEntities with
  | .error _ => false
  | .ok receipts => CedarPooSpec.CompoundAuthorization.layersAllowed receipts

def cases : List (String × String × EntityUID × EntityUID × String × Bool) := [
  ("base-external-high-support", "PaymentBase", externalAccount, support, "500.0000", true),
  ("scoped-external", "PaymentScoped", externalAccount, admin, "50.0000", false),
  ("scoped-high", "PaymentScoped", approvedAccount, admin, "500.0000", true),
  ("capped-high", "PaymentCapped", approvedAccount, admin, "100.0001", false),
  ("capped-support", "PaymentCapped", approvedAccount, support, "50.0000", true),
  ("human-exact-ceiling", "PaymentHuman", approvedAccount, admin, "100.0000", true),
  ("human-over-ceiling", "PaymentHuman", approvedAccount, admin, "100.0001", false),
  ("human-zero", "PaymentHuman", approvedAccount, admin, "0.0000", false),
  ("human-external", "PaymentHuman", externalAccount, admin, "50.0000", false),
  ("human-support", "PaymentHuman", approvedAccount, support, "50.0000", false),
  ("human-no-mfa", "PaymentHuman", approvedAccount, adminNoMfa, "50.0000", false)]

def casesExact : Bool := cases.all fun (_, root, account, origin, requested, expected) =>
  authorizePayment root account origin requested == expected

theorem casesExactFully : casesExact = true := by native_decide

def allRootsValidated : Bool :=
  ["FinanceTool", "PaymentBase", "PaymentScoped", "PaymentCapped", "PaymentHuman"].all
    fun root => (CedarPooSpec.PolicyJson.publish paymentModel root paymentSchema).isOk

theorem allRootsValidatedFully : allRootsValidated = true := by native_decide

end CedarPooSpec.AgentPaymentExample
