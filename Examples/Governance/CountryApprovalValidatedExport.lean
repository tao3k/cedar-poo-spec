import CedarPooSpec.SchemaJson
import Examples.Governance.CountryApprovalExport

namespace CedarPooSpec.CountryApprovalValidatedExport

def manifest : Except String Lean.Json := do
  let rows ← CedarPooSpec.CountryApprovalExport.rows
  CedarPooSpec.SchemaJson.validatedManifest
    CedarPooSpec.CountryApprovalExample.schema rows

end CedarPooSpec.CountryApprovalValidatedExport
