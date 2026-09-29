import CedarPooSpec.Governance.Veto

/-! Provider-neutral, digest-bound deployment admission. The Host verifies
the attestation and executes an enforced deployment for the selected digest. -/

namespace CedarPooSpec.Cloud.Pipeline

open Cedar.Spec CedarPooSpec.Governance

structure DeploymentBoundary where
  policyId : PolicyID
  actionScope : ActionScope
  resourceScope : ResourceScope
  requiredAttestor : String
  requiredReleaseRoot : String
  principalScope : PrincipalScope := .principalScope .any

private def fact (name : String) : Expr := .getAttr (.var .context) name
private def target (name : String) : Expr := .getAttr (.var .resource) name
private def claim (name : String) : Expr :=
  .getAttr (fact "attestation") name
private def release (name : String) : Expr :=
  .getAttr (fact "releaseReceipt") name
private def same (left right : Expr) : Expr := .binaryApp .eq left right
private def all (conditions : List Expr) : Expr :=
  conditions.foldr Expr.and (.lit (.bool true))

/-- The admitted deployment reference, verified attestation subject, and
    selected artifact must name one digest and the required attestor. -/
def DeploymentBoundary.ready (boundary : DeploymentBoundary) : Expr :=
  all [fact "attestationVerified", fact "immutableReference",
    fact "policyEnforced", fact "releaseReceiptVerified",
    same (release "artifactDigest") (target "artifactDigest"),
    same (release "sourceCommit") (target "sourceCommit"),
    same (release "policyRoot") (.lit (.string boundary.requiredReleaseRoot)),
    same (release "epoch") (fact "currentEpoch"),
    same (fact "deploymentDigest") (target "artifactDigest"),
    same (claim "subjectDigest") (target "artifactDigest"),
    same (claim "attestor") (.lit (.string boundary.requiredAttestor))]

def DeploymentBoundary.veto (boundary : DeploymentBoundary) : Veto :=
  { policyId := boundary.policyId
    actionScope := boundary.actionScope
    resourceScope := boundary.resourceScope
    principalScope := boundary.principalScope
    denyWhen := .unaryApp .not boundary.ready }

end CedarPooSpec.Cloud.Pipeline
