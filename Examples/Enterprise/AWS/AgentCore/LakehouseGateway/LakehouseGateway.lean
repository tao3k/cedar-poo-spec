import CedarPooSpec.PolicyJson
import CedarPooSpec.Revision

/-! A Cedar projection of the AWS AgentCore lakehouse Policy + Interceptor
example. The interceptor, token exchange, and Lake Formation checks remain
external authorities. The source gives the role, EU, and restricted-region
forbids; the final unresolved-geography veto is a locally proposed hardening. -/

namespace CedarPooSpec.LakehouseGatewayExample

open Cedar.Spec Cedar.Data Cedar.Validation CedarPooSpec.PolicyModules

def userType : EntityType := ⟨"OAuthUser", ["AgentCore"]⟩
def gatewayType : EntityType := ⟨"Gateway", ["AgentCore"]⟩
def actionType : EntityType := ⟨"Action", ["AgentCore"]⟩

def policyholderUS : EntityUID := ⟨userType, "policyholder001"⟩
def policyholderEU : EntityUID := ⟨userType, "policyholder002"⟩
def adjusterUS : EntityUID := ⟨userType, "adjuster001"⟩
def adjusterEU : EntityUID := ⟨userType, "adjuster002"⟩
def gateway : EntityUID := ⟨gatewayType, "lakehouse-gateway"⟩
def queryClaims : EntityUID :=
  ⟨actionType, "lakehouse-mcp-target___query_claims"⟩
def claimDetails : EntityUID :=
  ⟨actionType, "lakehouse-mcp-target___get_claim_details"⟩
def claimsSummary : EntityUID :=
  ⟨actionType, "lakehouse-mcp-target___get_claims_summary"⟩
def loginAudit : EntityUID :=
  ⟨actionType, "lakehouse-mcp-target___query_login_audit"⟩
def textToSql : EntityUID :=
  ⟨actionType, "lakehouse-mcp-target___text_to_sql"⟩

def tools : List EntityUID :=
  [queryClaims, claimDetails, claimsSummary, loginAudit, textToSql]

def inputType : RecordType := Map.make [("geography", .optional .string)]
def actionEntry : ActionSchemaEntry :=
  ⟨Set.make [userType], Set.make [gatewayType], Set.empty,
    Map.make [("input", .required (.record inputType))]⟩
def schema : Schema :=
  ⟨Map.make [
    (userType, .standard ⟨Set.empty, Map.empty, some .string⟩),
    (gatewayType, .standard ⟨Set.empty, Map.empty, none⟩)],
    Map.make (tools.map (·, actionEntry))⟩

def data (tags : List (String × Value) := []) : EntityData :=
  { attrs := Map.empty, ancestors := Set.empty, tags := Map.make tags }
def entities : Entities := Map.make (
  [(policyholderUS, data [("cognito:groups", .prim (.string "policyholders"))]),
   (policyholderEU, data [("cognito:groups", .prim (.string "policyholders"))]),
   (adjusterUS, data [("cognito:groups", .prim (.string "adjusters"))]),
   (adjusterEU, data [("cognito:groups", .prim (.string "adjusters"))]),
   (gateway, data)] ++ tools.map (·, data))

def request (user action : EntityUID) (geography : Option String) : Request :=
  let attrs := geography.toList.map fun location =>
    ("geography", Value.prim (.string location))
  ⟨user, action, gateway,
    Map.make [("input", .record (Map.make attrs))]⟩

def input : Expr := .getAttr (.var .context) "input"
def hasGeography : Expr := .hasAttr input "geography"
def geography : Expr := .getAttr input "geography"
def locationIs (place : String) : Expr :=
  .and hasGeography (.binaryApp .eq geography (.lit (.string place)))
def groups : Expr :=
  .binaryApp .getTag (.var .principal) (.lit (.string "cognito:groups"))
def hasGroups : Expr :=
  .binaryApp .hasTag (.var .principal) (.lit (.string "cognito:groups"))
def policyholderPattern : Pattern :=
  [.star, .justChar 'p', .justChar 'o', .justChar 'l', .justChar 'i',
   .justChar 'c', .justChar 'y', .justChar 'h', .justChar 'o',
   .justChar 'l', .justChar 'd', .justChar 'e', .justChar 'r',
   .justChar 's', .star]
def isPolicyholder : Expr :=
  .and hasGroups (.unaryApp (.like policyholderPattern) groups)

def baselinePermit : Policy :=
  { id := "gateway-baseline", effect := .permit,
    principalScope := .principalScope (.is userType),
    actionScope := .actionScope .any,
    resourceScope := .resourceScope (.eq gateway),
    condition := [] }
def roleVeto : Policy :=
  { id := "policyholder-summary", effect := .forbid,
    principalScope := .principalScope (.is userType),
    actionScope := .actionScope (.eq claimsSummary),
    resourceScope := .resourceScope (.eq gateway),
    condition := [{ kind := .when, body := isPolicyholder }] }
def euVeto : Policy :=
  { id := "eu-individual-claims", effect := .forbid,
    principalScope := .principalScope (.is userType),
    actionScope := .actionInAny [queryClaims, claimDetails],
    resourceScope := .resourceScope (.eq gateway),
    condition := [{ kind := .when, body := locationIs "EU" }] }
def restrictedVeto : Policy :=
  { id := "restricted-geography", effect := .forbid,
    principalScope := .principalScope (.is userType),
    actionScope := .actionInAny tools,
    resourceScope := .resourceScope (.eq gateway),
    condition := [{ kind := .when, body := locationIs "RESTRICTED" }] }

/-- A proposed extension: deny calls when geography is absent or the sample
    interceptor's `UNKNOWN` fallback is used. Neither matches the source's
    EU or RESTRICTED rules. -/
def unresolvedGeographyVeto : Policy :=
  { id := "unresolved-geography", effect := .forbid,
    principalScope := .principalScope (.is userType),
    actionScope := .actionInAny tools,
    resourceScope := .resourceScope (.eq gateway),
    condition := [{ kind := .when, body :=
      (.or (.unaryApp .not hasGeography) (locationIs "UNKNOWN")) }] }

def model : Model := { modules := [
  { name := "GatewayBase", edits := [.extend baselinePermit] },
  { name := "Role", parentOrders := [["GatewayBase"]],
    edits := [.extend roleVeto] },
  { name := "EU", parentOrders := [["GatewayBase"]],
    edits := [.extend euVeto] },
  { name := "Restricted", parentOrders := [["GatewayBase"]],
    edits := [.extend restrictedVeto] },
  { name := "SourceCombined", parentOrders := [["Role", "EU", "Restricted"]] },
  { name := "FailClosed", parentOrders := [["SourceCombined"]],
    edits := [.extend unresolvedGeographyVeto] }] }

def sourceCases : List (String × EntityUID × EntityUID × Option String × Decision) := [
  ("policyholder-us-query", policyholderUS, queryClaims, some "US", .allow),
  ("policyholder-eu-query", policyholderEU, queryClaims, some "EU", .deny),
  ("policyholder-eu-summary", policyholderEU, claimsSummary, some "EU", .deny),
  ("adjuster-us-summary", adjusterUS, claimsSummary, some "US", .allow),
  ("adjuster-eu-details", adjusterEU, claimDetails, some "EU", .deny),
  ("restricted-tool", adjusterUS, loginAudit, some "RESTRICTED", .deny)]

def decideAt (root : String) (req : Request) : Option Decision := do
  let policies ← (model.compile root).toOption
  let response := isAuthorized req entities policies
  if response.erroringPolicies.isEmpty then some response.decision else none

theorem sourceDecisionsExact :
    sourceCases.all (fun (_, user, action, location, expected) =>
      decideAt "SourceCombined" (request user action location) == some expected) = true := by
  native_decide

/-- Neither individual owner catches both independent restrictions. -/
theorem ownerBranchesNeedComposition :
    decideAt "Role" (request policyholderEU queryClaims (some "EU")) = some .allow ∧
    decideAt "EU" (request policyholderEU claimsSummary (some "EU")) = some .allow ∧
    decideAt "Restricted" (request policyholderEU claimsSummary (some "EU")) = some .allow := by
  native_decide

theorem unresolvedGeographyGapAndExtension :
    decideAt "SourceCombined" (request adjusterUS queryClaims none) = some .allow ∧
    decideAt "FailClosed" (request adjusterUS queryClaims none) = some .deny ∧
    decideAt "SourceCombined" (request adjusterUS queryClaims (some "UNKNOWN")) = some .allow ∧
    decideAt "FailClosed" (request adjusterUS queryClaims (some "UNKNOWN")) = some .deny ∧
    sourceCases.all (fun (_, user, action, location, expected) =>
      decideAt "FailClosed" (request user action location) == some expected) = true := by
  native_decide

theorem localRevision :
    ((model.compileRevision "SourceCombined" "FailClosed").toOption.get
      (by native_decide)).changedPolicyIds = [unresolvedGeographyVeto.id] := by
  native_decide

theorem oneFreshPolicyBody :
    ((model.compileRevision "SourceCombined" "FailClosed").toOption.get
      (by native_decide)).freshPolicies = [unresolvedGeographyVeto] := by
  native_decide

theorem allRootsValidated :
    ["GatewayBase", "Role", "EU", "Restricted", "SourceCombined",
      "FailClosed"].all (fun root =>
        (CedarPooSpec.PolicyJson.publish model root schema).isOk) = true := by
  native_decide

end CedarPooSpec.LakehouseGatewayExample
