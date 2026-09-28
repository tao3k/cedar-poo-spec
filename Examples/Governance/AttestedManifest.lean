/-!
Fixed root and artifact-revision identities for the attested governance case.
Selecting a revision is explicit; constructing a query never advances it.
-/

namespace CedarPooSpec.AttestedManifest

structure Version where
  major : Nat
  minor : Nat
  deriving DecidableEq, Repr

def Version.label (version : Version) : String :=
  s!"{version.major}.{version.minor}"

inductive Root where
  | ownerOnly
  | baseline
  | strengthened
  | reordered
  | audit
  deriving DecidableEq, Repr

def Root.name : Root → String
  | .ownerOnly => "DataOwner"
  | .baseline => "Governed"
  | .strengthened => "FreshAttestation"
  | .reordered => "ComplianceFirst"
  | .audit => "AuditView"

def Root.version : Root → Version
  | .ownerOnly | .baseline => ⟨0, 1⟩
  | .strengthened | .reordered | .audit => ⟨0, 2⟩

def Root.artifactFamily : Root → String
  | .ownerOnly => "attested-dataowner"
  | .baseline | .strengthened => "attested-governed"
  | .reordered => "attested-compliance-first"
  | .audit => "attested-audit"

def Root.artifactRevision (root : Root) : String :=
  s!"{root.artifactFamily}-{root.version.label}"

theorem publishedRevisionsAreFixed :
    Root.baseline.artifactRevision = "attested-governed-0.1" ∧
    Root.strengthened.artifactRevision = "attested-governed-0.2" := by
  native_decide

end CedarPooSpec.AttestedManifest
