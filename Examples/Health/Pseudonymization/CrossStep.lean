import Examples.Health.Pseudonymization.Lifecycle
import Examples.Health.Pseudonymization.AgentDisclosure

/-!
One synthetic hospital trajectory. The receipts are typed handoffs between
separately authorized steps. A real Host must authenticate their fields against
provider, query, and output evidence before admitting the next step.
-/

namespace CedarPooSpec.PseudonymizationExample.CrossStep

open Cedar.Spec
open CedarPooSpec.PseudonymizationExample

structure TokenReceipt where
  source : EntityUID
  sourceDigest : String
  tokenDigest : String
  keyVersion : String
  policyRevision : Nat
  approvalRevision : Nat
  deriving DecidableEq

structure JoinReceipt where
  token : TokenReceipt
  purpose : String
  queryDigest : String
  deriving DecidableEq

structure DerivedReceipt where
  hospitalJoin : JoinReceipt
  researchJoin : JoinReceipt
  outputDigest : String
  sources : List CedarPooSpec.Data.SourceLabel
  deriving DecidableEq

/-- The synthetic token digest stands for an authenticated provider receipt. -/
def ingest (state : Lifecycle.State) (effect : Lifecycle.Effect)
    (tokenDigest : String) : Option (Lifecycle.State × TokenReceipt) := do
  if effect.step != .ingest || tokenDigest.isEmpty then none
  let next ← Lifecycle.step state effect
  let receipt : TokenReceipt :=
    { source := effect.source, sourceDigest := effect.payloadDigest, tokenDigest, keyVersion := effect.keyVersion, policyRevision := state.policyRevision, approvalRevision := state.approvalRevision }
  some (next, receipt)

def join (state : Lifecycle.State) (token : TokenReceipt)
    (effect : Lifecycle.Effect) : Option (Lifecycle.State × JoinReceipt) := do
  if effect.step != .join || token.sourceDigest.isEmpty ||
      token.tokenDigest.isEmpty || effect.source != token.source ||
      effect.keyVersion != token.keyVersion ||
      state.policyRevision != token.policyRevision ||
      state.approvalRevision != token.approvalRevision then none
  else
    let next ← Lifecycle.step state effect
    some (next, { token, purpose := effect.purpose, queryDigest := effect.payloadDigest })

def derive (hospitalJoin researchJoin : JoinReceipt)
    (observedDigest : String) : Option DerivedReceipt :=
  if hospitalJoin.token.source != hospital || researchJoin.token.source != research ||
      hospitalJoin.purpose != "study-one" ||
      researchJoin.purpose != hospitalJoin.purpose ||
      hospitalJoin.queryDigest.isEmpty || researchJoin.queryDigest.isEmpty ||
      hospitalJoin.token.keyVersion != researchJoin.token.keyVersion ||
      hospitalJoin.token.policyRevision != researchJoin.token.policyRevision ||
      hospitalJoin.token.approvalRevision != researchJoin.token.approvalRevision ||
      observedDigest != AgentDisclosure.joinedResult.digest then none
  else some { hospitalJoin, researchJoin, outputDigest := observedDigest, sources := AgentDisclosure.joinedResult.sources }

def publish (state : AgentDisclosure.State) (derived : DerivedReceipt)
    (effect : AgentDisclosure.Effect) : Option AgentDisclosure.State := do
  if effect.purpose != derived.hospitalJoin.purpose ||
      effect.artifact.sources != derived.sources ||
      effect.payloadDigest != derived.outputDigest ||
      state.policyRevision != derived.hospitalJoin.token.policyRevision ||
      state.approvalRevision != derived.hospitalJoin.token.approvalRevision then none
  else AgentDisclosure.release .governed state effect

/-- Re-identification is a separate approved clinical branch. It can reuse
    token provenance but cannot inherit the research publication grant. -/
def reidentify (state : Lifecycle.State) (token : TokenReceipt)
    (effect : Lifecycle.Effect) : Option Lifecycle.State :=
  if effect.step != .reidentify || effect.source != token.source ||
      effect.keyVersion != token.keyVersion ||
      state.policyRevision != token.policyRevision ||
      state.approvalRevision != token.approvalRevision then none
  else Lifecycle.step state effect

def trajectory : Option (AgentDisclosure.State × Lifecycle.State) := do
  let researchGrant := Lifecycle.grant agent CedarPooSpec.PseudonymizationExample.join
    "study-one" research research
  let state : Lifecycle.State :=
    { Lifecycle.initial with approvals := researchGrant :: Lifecycle.initial.approvals }
  let (firstIngest, hospitalToken) ← ingest state Lifecycle.ingestEffect "hospital-token"
  let researchIngest : Lifecycle.Effect :=
    { Lifecycle.ingestEffect with source := research, target := research, payloadDigest := "research-record" }
  let (secondIngest, researchToken) ← ingest firstIngest researchIngest "research-token"
  let (firstJoin, hospitalRead) ← join secondIngest hospitalToken Lifecycle.joinEffect
  let researchRead : Lifecycle.Effect :=
    { Lifecycle.joinEffect with source := research, target := research, payloadDigest := "research-query" }
  let (secondJoin, researchEvidence) ← join firstJoin researchToken researchRead
  let derived ← derive hospitalRead researchEvidence AgentDisclosure.joinedResult.digest
  let released ← publish AgentDisclosure.initial derived AgentDisclosure.workspaceEffect
  let recovered ← reidentify secondJoin hospitalToken Lifecycle.revealEffect
  some (released, recovered)

theorem syntheticTrajectoryAdmits : trajectory.isSome = true := by native_decide

def hospitalTokenFixture : TokenReceipt :=
  { source := hospital, sourceDigest := "record-1", tokenDigest := "hospital-token", keyVersion := "dek-v1", policyRevision := 0, approvalRevision := 0 }

def researchTokenFixture : TokenReceipt :=
  { source := research, sourceDigest := "research-record", tokenDigest := "research-token", keyVersion := "dek-v1", policyRevision := 0, approvalRevision := 0 }

theorem staleTokenAndChangedPurposeFail :
    ((ingest Lifecycle.initial Lifecycle.ingestEffect "hospital-token").bind fun (next, token) =>
      join { next with policyRevision := 1 } token Lifecycle.joinEffect) = none ∧
    (derive
      { token := hospitalTokenFixture, purpose := "study-one", queryDigest := "query-1" }
      { token := researchTokenFixture, purpose := "other-study", queryDigest := "research-query" }
      AgentDisclosure.joinedResult.digest) = none := by
  native_decide

theorem researchGrantCannotReidentify :
    ((ingest Lifecycle.initial Lifecycle.ingestEffect "hospital-token").bind fun (next, token) =>
      reidentify { next with approvals := [] } token Lifecycle.revealEffect) = none := by
  native_decide

theorem missingResearchReceiptCannotDerive :
    derive
      { token := hospitalTokenFixture, purpose := "study-one", queryDigest := "query-1" }
      { token := hospitalTokenFixture, purpose := "study-one", queryDigest := "query-2" }
      AgentDisclosure.joinedResult.digest = none := by
  native_decide

end CedarPooSpec.PseudonymizationExample.CrossStep
