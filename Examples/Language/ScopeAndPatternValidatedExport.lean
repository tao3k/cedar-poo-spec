import CedarPooSpec.SchemaJson
import Examples.Language.ScopeAndPatternExport

namespace CedarPooSpec.ScopeAndPatternValidatedExport

def manifest : Except String Lean.Json := do
  let rows ← CedarPooSpec.ScopeAndPatternExport.manifest
  let cases ← (rows.getObjValAs? (List Lean.Json) "cases").mapError toString
  CedarPooSpec.SchemaJson.validatedManifest
    CedarPooSpec.ScopeAndPatternExample.schema cases

end CedarPooSpec.ScopeAndPatternValidatedExport
