import CedarPooSpec.SchemaJson
import Examples.Governance.TrustedNetworkDataAccessExport

namespace CedarPooSpec.TrustedNetworkValidatedExport

def manifest : Except String Lean.Json := do
  let rows ← CedarPooSpec.TrustedNetworkDataAccessExport.rows
  CedarPooSpec.SchemaJson.validatedManifest
    CedarPooSpec.TrustedNetworkDataAccessExample.networkSchema rows

end CedarPooSpec.TrustedNetworkValidatedExport
