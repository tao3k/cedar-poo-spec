import Examples.Cloud.Pipeline.ReplayExport

/-! Focused Cedar replay entry point for the pipeline scenario. -/

def main (_args : List String) : IO Unit := do
  match CedarPooSpec.Cloud.Pipeline.GoogleThreatCase.manifest with
  | .ok json => IO.println json.compress
  | .error message => throw (IO.userError message)
