import Examples.Cloud.DataProtection.ReplayExport

def main : IO Unit := do
  match CedarPooSpec.Cloud.DataProtection.GoogleSdpRelease.manifest with
  | .ok value => IO.println value.compress
  | .error error => throw <| IO.userError error
