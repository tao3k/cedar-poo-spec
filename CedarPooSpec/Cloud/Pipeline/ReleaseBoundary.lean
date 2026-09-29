import CedarPooSpec.Governance.Veto

/-!
Reusable Cedar policy controls for a code-to-artifact release. Every context
field is an authenticated Host projection; these expressions do not inspect a
repository, runner, cache, signature, or deployment on their own.
-/

namespace CedarPooSpec.Cloud.Pipeline

open Cedar.Spec CedarPooSpec.Governance

inductive Stage where
  | source
  | dependencies
  | runner
  | artifact
  deriving DecidableEq, Repr

def Stage.name : Stage → String
  | .source => "source"
  | .dependencies => "dependencies"
  | .runner => "runner"
  | .artifact => "artifact"

private def context (name : String) : Expr :=
  .getAttr (.var .context) name

private def resource (name : String) : Expr :=
  .getAttr (.var .resource) name

private def equalField (name : String) : Expr :=
  .binaryApp .eq (context name) (resource name)

private def all (conditions : List Expr) : Expr :=
  conditions.foldr Expr.and (.lit (.bool true))

/-- Stage evidence and exact target bindings required for one release. -/
def Stage.ready : Stage → Expr
  | .source => all [context "reviewed", context "protectedRef",
      equalField "sourceCommit", equalField "workflow"]
  | .dependencies => all [context "lockVerified",
      context "dependenciesQuarantined", context "actionsPinned",
      equalField "lockDigest"]
  | .runner => all [context "ephemeralRunner", context "cacheIsolated",
      context "untrustedPrBlocked", equalField "oidcAudience"]
  | .artifact => all [context "signatureVerified",
      context "provenanceVerified", equalField "artifactDigest",
      equalField "builderIdentity"]

/-- Each stage owns one Cedar forbid policy. A separate grant must permit the
    action; Cedar combines permits and forbids after POO composes policy slots. -/
structure ReleaseBoundary where
  policyId : PolicyID
  actionScope : ActionScope
  resourceScope : ResourceScope
  stage : Stage
  principalScope : PrincipalScope := .principalScope .any

def ReleaseBoundary.veto (boundary : ReleaseBoundary) : Veto :=
  { policyId := boundary.policyId
    actionScope := boundary.actionScope
    resourceScope := boundary.resourceScope
    principalScope := boundary.principalScope
    denyWhen := .unaryApp .not boundary.stage.ready }

end CedarPooSpec.Cloud.Pipeline
