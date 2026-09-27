import Examples.Enterprise.Agent.Delegation.AgentDelegation

/-!
The same POO delegation policy is evaluated once per hop. A path with one,
two, or three hops has three, four, or five authorization layers respectively.
-/

namespace CedarPooSpec.AgentChainExample

open Cedar.Spec Cedar.Data Cedar.Validation CedarPooSpec.PolicyModules
open CedarPooSpec.AgentDelegationExample

def routingBot : EntityUID := ⟨agentType, "routing-bot"⟩
def complianceBot : EntityUID := ⟨agentType, "compliance-bot"⟩
def weakRoutingBot : EntityUID := ⟨agentType, "weak-routing-bot"⟩
def limitedBot : EntityUID := ⟨agentType, "limited-bot"⟩

def chainEntities : Entities := Map.make (entities.toList ++ [
  (routingBot, agentData 4 "data" "production" ["delegate"]),
  (complianceBot, agentData 4 "data" "production" ["delegate"]),
  (weakRoutingBot, agentData 2 "data" "production" ["delegate"]),
  (limitedBot, agentData 4 "data" "production" ["read_records"])])

def delegatorTrusted : Expr :=
  .and (.binaryApp .lessEq (.lit (.int 3)) (principalFact "trust"))
    (.binaryApp .contains (principalFact "capabilities") (.lit (.string "delegate")))
def chainDelegation : Policy :=
  { delegationBounded with
    principalScope := .principalScope .any,
    resourceScope := .resourceScope .any,
    condition := [{ kind := .when, body := .and delegationBody delegatorTrusted }] }
def depthOnlyDelegation : Policy :=
  { chainDelegation with condition := [{ kind := .when, body := delegationBody }] }
def chainOrigin : Policy :=
  { originBounded with condition := [
      { kind := .when,
        body := .and (.and originRole originMfa)
          (.binaryApp .lessEq (ctx "depth") (.lit (.int 3))) }] }
def revokedEdge : Policy :=
  { id := "revoke-routing-to-compliance", effect := .forbid,
    principalScope := .principalScope (.eq routingBot),
    actionScope := .actionScope (.eq delegate),
    resourceScope := .resourceScope (.eq complianceBot),
    condition := [{ kind := .when, body := .lit (.bool true) }] }

def chainModel : Model := { modules := model.modules ++ [
  { name := "ChainDelegation", parentOrders := [["DelegationBounded"]],
    edits := [.overlay chainDelegation] },
  { name := "ChainOrigin", parentOrders := [["OriginBounded"]],
    edits := [.overlay chainOrigin] },
  { name := "ChainGoverned", parentOrders := [["ChainDelegation", "ChainOrigin"]] },
  { name := "ChainGovernedRevoked", parentOrders := [["ChainGoverned"]],
    edits := [.extend revokedEdge] },
  { name := "ChainGovernedRestored", parentOrders := [["ChainGovernedRevoked"]],
    edits := [.remove revokedEdge.id] },
  { name := "ChainDepthOnly", parentOrders := [["DelegationBounded"]],
    edits := [.overlay depthOnlyDelegation] },
  { name := "ChainConflicted", parentOrders := [["ChainDelegation", "ChainDepthOnly"]] }] }

def requestHop (source target : EntityUID) (depth : Int64) : Request :=
  let requested := if target == dataBot then "delete_records" else "delegate"
  ⟨source, delegate, target, Map.make [
    ("depth", .prim (.int depth)),
    ("requestedCaps", .set (Set.make [.prim (.string requested)]))]⟩

def validPath (path : List EntityUID) : Bool :=
  path.head? == some orchestrator && path.getLast? == some dataBot &&
    path.length >= 2 && path.length <= 4 &&
    path.eraseDups.length == path.length

def hopChecks (delegationRoot : String) (path : List EntityUID) :
    List (String × Request) :=
  ((path.zip path.tail).zipIdx).map fun ((source, target), index) =>
    (delegationRoot, requestHop source target (Int64.ofNat (index + 1)))

def checks (delegationRoot originRoot : String) (path : List EntityUID)
    (origin : EntityUID) : List (String × Request) :=
  [("ToolHardened", requestTool dataBot deleteRecords)] ++
    hopChecks delegationRoot path ++
    [(originRoot, requestOrigin dataBot deleteRecords origin
      (Int64.ofNat (path.length - 1)))]

def authorizeChain (delegationRoot originRoot : String) (path : List EntityUID)
    (origin : EntityUID) : Bool :=
  if !validPath path then false else
    match CedarPooSpec.CompoundAuthorization.authorizeLayers chainModel
        (checks delegationRoot originRoot path origin) chainEntities with
    | .error _ => false
    | .ok receipts => CedarPooSpec.CompoundAuthorization.layersAllowed receipts

def shortPath : List EntityUID := [orchestrator, dataBot]
def routedPath : List EntityUID := [orchestrator, routingBot, dataBot]
def reviewedPath : List EntityUID :=
  [orchestrator, routingBot, complianceBot, dataBot]
def weakPath : List EntityUID :=
  [orchestrator, weakRoutingBot, complianceBot, dataBot]
def limitedPath : List EntityUID :=
  [orchestrator, routingBot, limitedBot, dataBot]
def cyclicPath : List EntityUID :=
  [orchestrator, routingBot, routingBot, dataBot]

def cases : List (String × String × String × List EntityUID × EntityUID × Bool) := [
  ("three-layers-admin", "ChainDelegation", "OriginBounded", shortPath, admin, true),
  ("three-layers-support", "ChainDelegation", "OriginBounded", shortPath, support, false),
  ("four-layers-admin", "ChainDelegation", "OriginBounded", routedPath, admin, true),
  ("five-layers-old-origin-bound", "ChainDelegation", "OriginBounded", reviewedPath, admin, false),
  ("five-layers-revised-origin", "ChainGoverned", "ChainGoverned", reviewedPath, admin, true),
  ("five-layers-support", "ChainGoverned", "ChainGoverned", reviewedPath, support, false),
  ("five-layers-weak-hop", "ChainGoverned", "ChainGoverned", weakPath, admin, false),
  ("five-layers-missing-capability", "ChainGoverned", "ChainGoverned", limitedPath, admin, false),
  ("three-layers-unaffected-by-edge-revoke", "ChainGovernedRevoked", "ChainGovernedRevoked", shortPath, admin, true),
  ("four-layers-unaffected-by-edge-revoke", "ChainGovernedRevoked", "ChainGovernedRevoked", routedPath, admin, true),
  ("five-layers-revoked-edge", "ChainGovernedRevoked", "ChainGovernedRevoked", reviewedPath, admin, false),
  ("five-layers-restored-edge", "ChainGovernedRestored", "ChainGovernedRestored", reviewedPath, admin, true),
  ("five-layers-cyclic-path", "ChainGoverned", "ChainGoverned", cyclicPath, admin, false)]

def casesExact : Bool := cases.all fun (_, delegationRoot, originRoot, path,
    origin, expected) =>
  authorizeChain delegationRoot originRoot path origin == expected
theorem casesExactFully : casesExact = true := by native_decide

def allValidCasesErrorFree : Bool := cases.all fun (_, delegationRoot, originRoot,
    path, origin, _) =>
  if !validPath path then true else
    match CedarPooSpec.CompoundAuthorization.authorizeLayers chainModel
        (checks delegationRoot originRoot path origin) chainEntities with
    | .error _ => false
    | .ok receipts => receipts.all fun layer => layer.response.erroringPolicies.isEmpty
theorem allValidCasesErrorFreeFully : allValidCasesErrorFree = true := by native_decide

def layerCounts : Bool :=
  (checks "ChainDelegation" "OriginBounded" shortPath admin).length == 3 &&
  (checks "ChainDelegation" "OriginBounded" routedPath admin).length == 4 &&
  (checks "ChainGoverned" "ChainGoverned" reviewedPath admin).length == 5
theorem layerCountsFully : layerCounts = true := by native_decide

def compilationRootCounts : Bool :=
  ((checks "ChainDelegation" "OriginBounded" shortPath admin).map Prod.fst).eraseDups.length == 3 &&
  ((checks "ChainGoverned" "ChainGoverned" reviewedPath admin).map Prod.fst).eraseDups.length == 2
theorem compilationRootCountsFully : compilationRootCounts = true := by native_decide

def governedPolicyIds : Bool :=
  match chainModel.compile "ChainGoverned" with
  | .error _ => false
  | .ok policies =>
      let ids := policies.map Policy.id
      ids.length == 2 && ids.contains "agent-delegation" && ids.contains "origin-user"
theorem governedPolicyIdsFully : governedPolicyIds = true := by native_decide

def rootsValidated : Bool :=
  ["ToolHardened", "DelegationBounded", "ChainDelegation",
    "OriginBounded", "ChainOrigin", "ChainGoverned", "ChainGovernedRevoked",
    "ChainGovernedRestored"].all fun root =>
      (CedarPooSpec.PolicyJson.publish chainModel root schema).isOk
theorem rootsValidatedFully : rootsValidated = true := by native_decide

def unaffectedRoots : Bool :=
  chainModel.compile "ToolHardened" == model.compile "ToolHardened" &&
  chainModel.compile "OriginBounded" == model.compile "OriginBounded"
theorem unaffectedRootsFully : unaffectedRoots = true := by native_decide

theorem delegationEditLocal :
    ((chainModel.compileRevision "DelegationBounded" "ChainDelegation").toOption.get
      (by native_decide)).changedPolicyIds = ["agent-delegation"] := by native_decide

theorem originEditLocal :
    ((chainModel.compileRevision "OriginBounded" "ChainOrigin").toOption.get
      (by native_decide)).changedPolicyIds = ["origin-user"] := by native_decide

theorem revokedEdgeLocal :
    ((chainModel.compileRevision "ChainGoverned" "ChainGovernedRevoked").toOption.get
      (by native_decide)).changedPolicyIds = ["revoke-routing-to-compliance"] := by native_decide

theorem restoredEdgeLocal :
    ((chainModel.compileRevision "ChainGovernedRevoked" "ChainGovernedRestored").toOption.get
      (by native_decide)).changedPolicyIds = ["revoke-routing-to-compliance"] := by native_decide

theorem restoredPoliciesEqualGoverned :
    (chainModel.compile "ChainGovernedRestored" ==
      chainModel.compile "ChainGoverned") = true := by
  native_decide

def conflictingDelegationEdits : Bool :=
  match chainModel.compile "ChainConflicted" with
  | .error (.competingEdits id _ _) => id == "agent-delegation"
  | _ => false
theorem conflictingDelegationEditsRejected : conflictingDelegationEdits = true := by
  native_decide

end CedarPooSpec.AgentChainExample
