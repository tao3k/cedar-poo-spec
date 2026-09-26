import Examples.Language.ScopeAndPattern

namespace CedarPooSpec.ScopeAndPatternExport

open CedarPooSpec.ScopeAndPatternExample

def manifest : Except String Lean.Json := do
  let exported ← cases.mapM fun (name, root, req, _) =>
    CedarPooSpec.PolicyJson.authorizationCase name root.toLower model root req entities
  return Lean.Json.mkObj [("cases", Lean.toJson exported)]

end CedarPooSpec.ScopeAndPatternExport

def main : IO Unit :=
  match CedarPooSpec.ScopeAndPatternExport.manifest with
  | .ok json => IO.println json.compress
  | .error message => throw (IO.userError message)
