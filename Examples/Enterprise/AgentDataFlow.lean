import Examples.Enterprise.AgentDelegation

/-!
An agent's right to read a document does not imply a right to publish its
contents to a repository. Both decisions use one caller-supplied entity store.
-/

namespace CedarPooSpec.AgentDataFlowExample

open Cedar.Spec Cedar.Data Cedar.Validation CedarPooSpec.PolicyModules
open CedarPooSpec.AgentDelegationExample

def documentType : EntityType := ⟨"Document", []⟩
def repositoryType : EntityType := ⟨"Repository", []⟩
def securityRole : EntityUID := ⟨roleType, "Security"⟩
def knowledgeBot : EntityUID := ⟨agentType, "knowledge-bot"⟩
def reviewer : EntityUID := ⟨userType, "reviewer"⟩
def internalDoc : EntityUID := ⟨documentType, "internal"⟩
def publicDoc : EntityUID := ⟨documentType, "public"⟩
def foreignDoc : EntityUID := ⟨documentType, "foreign"⟩
def internalRepo : EntityUID := ⟨repositoryType, "internal"⟩
def publicRepo : EntityUID := ⟨repositoryType, "public"⟩
def foreignRepo : EntityUID := ⟨repositoryType, "foreign"⟩
def readDocument : EntityUID := ⟨actionType, "read-document"⟩
def publishDocument : EntityUID := ⟨actionType, "publish-document"⟩

def classified (tenant classification : String) : EntityData :=
  { emptyData with attrs := Map.make [
      ("tenant", .prim (.string tenant)),
      ("classification", .prim (.string classification))] }
def destination (tenant visibility : String) : EntityData :=
  { emptyData with attrs := Map.make [
      ("tenant", .prim (.string tenant)),
      ("visibility", .prim (.string visibility))] }
def dataEntities : Entities := Map.make (entities.toList ++ [
  (knowledgeBot, agentData 4 "knowledge" "production" ["read", "publish"]),
  (securityRole, emptyData),
  (reviewer, { userData adminRole true with ancestors := Set.make [adminRole, securityRole] }),
  (internalDoc, classified "acme" "internal"),
  (publicDoc, classified "acme" "public"),
  (foreignDoc, classified "other" "internal"),
  (internalRepo, destination "acme" "internal"),
  (publicRepo, destination "acme" "public"),
  (foreignRepo, destination "other" "public"),
  (readDocument, emptyData), (publishDocument, emptyData)])

def documentEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.make [
    ("tenant", .required .string), ("classification", .required .string)], none⟩
def repositoryEntry : EntitySchemaEntry :=
  .standard ⟨Set.empty, Map.make [
    ("tenant", .required .string), ("visibility", .required .string)], none⟩
def readEntry : ActionSchemaEntry :=
  ⟨Set.make [agentType], Set.make [documentType], Set.empty,
    Map.make [("origin", .required (.entity userType))]⟩
def publishEntry : ActionSchemaEntry :=
  ⟨Set.make [agentType], Set.make [repositoryType], Set.empty,
    Map.make [("source", .required (.entity documentType)),
      ("origin", .required (.entity userType)),
      ("reviewer", .required (.entity userType)),
      ("approved", .required (.bool .anyBool))]⟩
def dataSchema : Schema :=
  ⟨Map.make (schema.ets.toList ++ [
      (documentType, documentEntry), (repositoryType, repositoryEntry)]),
    Map.make (schema.acts.toList ++ [
      (readDocument, readEntry), (publishDocument, publishEntry)])⟩

def sourceFact (name : String) : Expr := .getAttr (ctx "source") name
def dataTenant : Expr :=
  .and (eq (resourceFact "tenant") (.lit (.string "acme")))
    (.binaryApp .mem (ctx "origin") (.lit (.entityUID adminRole)))
def destinationTenant : Expr :=
  eq (resourceFact "tenant") (sourceFact "tenant")
def internalDestination : Expr :=
  eq (resourceFact "visibility") (.lit (.string "internal"))
def publicSource : Expr :=
  eq (sourceFact "classification") (.lit (.string "public"))
def classificationBoundary : Expr :=
  .and destinationTenant (.or internalDestination publicSource)
def independentReview : Expr :=
  .and (ctx "approved")
    (.and (.binaryApp .mem (ctx "reviewer") (.lit (.entityUID securityRole)))
      (.and (.getAttr (ctx "reviewer") "mfa")
        (.unaryApp .not (eq (ctx "reviewer") (ctx "origin")))))
def reviewedBoundary : Expr :=
  .and classificationBoundary (.or internalDestination independentReview)

def readBase : Policy :=
  policy "agent-document-read" readDocument (.eq knowledgeBot) .any (.lit (.bool true))
def readTenant : Policy :=
  { readBase with condition := [{ kind := .when, body := dataTenant }] }
def publishBase : Policy :=
  policy "agent-document-publish" publishDocument (.eq knowledgeBot) .any (.lit (.bool true))
def publishScoped : Policy :=
  { publishBase with condition := [{ kind := .when, body := destinationTenant }] }
def publishClassified : Policy :=
  { publishScoped with condition := [{ kind := .when, body := classificationBoundary }] }
def publishReviewed : Policy :=
  { publishClassified with condition := [{ kind := .when, body := reviewedBoundary }] }
def publicDocumentRevoked : Policy :=
  { id := "revoke-public-document-publication", effect := .forbid,
    principalScope := .principalScope (.eq knowledgeBot),
    actionScope := .actionScope (.eq publishDocument),
    resourceScope := .resourceScope .any,
    condition := [
      { kind := .when, body := eq (ctx "source") (.lit (.entityUID publicDoc)) }] }

def dataModel : Model := { modules := [
  { name := "ReadBase", edits := [.extend readBase] },
  { name := "ReadTenant", parentOrders := [["ReadBase"]], edits := [.overlay readTenant] },
  { name := "PublishBase", edits := [.extend publishBase] },
  { name := "PublishScoped", parentOrders := [["PublishBase"]],
    edits := [.overlay publishScoped] },
  { name := "PublishClassified", parentOrders := [["PublishScoped"]],
    edits := [.overlay publishClassified] },
  { name := "PublishReviewed", parentOrders := [["PublishClassified"]],
    edits := [.overlay publishReviewed] },
  { name := "PublishRevoked", parentOrders := [["PublishReviewed"]],
    edits := [.extend publicDocumentRevoked] }] }

def readRequest (source origin : EntityUID) : Request :=
  ⟨knowledgeBot, readDocument, source, Map.make [
    ("origin", .prim (.entityUID origin))]⟩
def publishRequest (source repo origin approver : EntityUID) (approved : Bool) : Request :=
  ⟨knowledgeBot, publishDocument, repo, Map.make [
    ("source", .prim (.entityUID source)),
    ("origin", .prim (.entityUID origin)),
    ("reviewer", .prim (.entityUID approver)),
    ("approved", .prim (.bool approved))]⟩
def checks (readRoot publishRoot : String) (source repo origin approver : EntityUID)
    (approved : Bool) : List (String × Request) := [
  (readRoot, readRequest source origin),
  (publishRoot, publishRequest source repo origin approver approved)]
def authorizeFlow (readRoot publishRoot : String) (source repo origin approver : EntityUID)
    (approved : Bool) : Bool :=
  match CedarPooSpec.CompoundAuthorization.authorizeLayers dataModel
      (checks readRoot publishRoot source repo origin approver approved) dataEntities with
  | .error _ => false
  | .ok receipts => CedarPooSpec.CompoundAuthorization.layersAllowed receipts

def cases : List (String × String × String × EntityUID × EntityUID × EntityUID × EntityUID × Bool × Bool) := [
  ("legacy-internal-to-public", "ReadBase", "PublishBase", internalDoc, publicRepo, admin, support, false, true),
  ("read-foreign-tenant", "ReadTenant", "PublishBase", foreignDoc, internalRepo, admin, reviewer, true, false),
  ("scoped-internal-to-public", "ReadTenant", "PublishScoped", internalDoc, publicRepo, admin, reviewer, true, true),
  ("classified-internal-to-public", "ReadTenant", "PublishClassified", internalDoc, publicRepo, admin, reviewer, true, false),
  ("classified-public-without-review", "ReadTenant", "PublishClassified", publicDoc, publicRepo, admin, support, false, true),
  ("reviewed-public", "ReadTenant", "PublishReviewed", publicDoc, publicRepo, admin, reviewer, true, true),
  ("reviewed-unapproved", "ReadTenant", "PublishReviewed", publicDoc, publicRepo, admin, reviewer, false, false),
  ("reviewed-wrong-role", "ReadTenant", "PublishReviewed", publicDoc, publicRepo, admin, support, true, false),
  ("reviewed-self-approval", "ReadTenant", "PublishReviewed", publicDoc, publicRepo, reviewer, reviewer, true, false),
  ("internal-to-internal", "ReadTenant", "PublishReviewed", internalDoc, internalRepo, admin, support, false, true),
  ("cross-tenant-publish", "ReadTenant", "PublishReviewed", publicDoc, foreignRepo, admin, reviewer, true, false),
  ("unprivileged-origin", "ReadTenant", "PublishReviewed", publicDoc, publicRepo, support, reviewer, true, false),
  ("revoked-public-document", "ReadTenant", "PublishRevoked", publicDoc, publicRepo, admin, reviewer, true, false)]

def casesExact : Bool := cases.all fun (_, readRoot, publishRoot, source, repo,
    origin, approver, approved, expected) =>
  authorizeFlow readRoot publishRoot source repo origin approver approved == expected
theorem casesExactFully : casesExact = true := by native_decide

def casesErrorFree : Bool := cases.all fun (_, readRoot, publishRoot, source, repo,
    origin, approver, approved, _) =>
  match CedarPooSpec.CompoundAuthorization.authorizeLayers dataModel
      (checks readRoot publishRoot source repo origin approver approved) dataEntities with
  | .error _ => false
  | .ok receipts => receipts.all fun layer => layer.response.erroringPolicies.isEmpty
theorem casesErrorFreeFully : casesErrorFree = true := by native_decide

def classifiedLeakBoundary : Bool :=
  match CedarPooSpec.CompoundAuthorization.authorizeLayers dataModel
      (checks "ReadTenant" "PublishClassified" internalDoc publicRepo admin reviewer true)
      dataEntities with
  | .error _ => false
  | .ok [readLayer, publishLayer] =>
      readLayer.response.decision == .allow && publishLayer.response.decision == .deny
  | .ok _ => false
theorem classifiedLeakBoundaryFully : classifiedLeakBoundary = true := by native_decide

def allRootsValidated : Bool :=
  ["ReadBase", "ReadTenant", "PublishBase", "PublishScoped",
    "PublishClassified", "PublishReviewed", "PublishRevoked"].all fun root =>
      (CedarPooSpec.PolicyJson.publish dataModel root dataSchema).isOk
theorem allRootsValidatedFully : allRootsValidated = true := by native_decide

end CedarPooSpec.AgentDataFlowExample
