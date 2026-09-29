import CedarPooSpec.SchemaJson
import Examples.Governance.AttestedDataAccessExport

namespace CedarPooSpec.AttestedViewsValidatedExport

def manifest : Except String Lean.Json := do
  let rows ← CedarPooSpec.AttestedDataAccessExport.rows
  CedarPooSpec.SchemaJson.validatedManifest
    CedarPooSpec.AttestedDataAccessExample.schema rows

end CedarPooSpec.AttestedViewsValidatedExport
