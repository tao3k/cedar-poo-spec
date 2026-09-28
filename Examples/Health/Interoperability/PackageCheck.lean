import CedarPooSpec.Vertical.Health.Region.PackageMetadata

namespace CedarPooSpec.HealthExample.PackageCheck

open CedarPooSpec.Vertical.Health.Region.PackageMetadata

def check : IO Unit := do
  checkFile australia
    "CedarPooSpec/Vertical/Health/Region/Packages/au-core-2.0.0.json"
  checkFile unitedStates
    "CedarPooSpec/Vertical/Health/Region/Packages/us-core-9.0.0.json"
  IO.println "FHIR-PACKAGES-OK"

end CedarPooSpec.HealthExample.PackageCheck

def main : IO Unit := CedarPooSpec.HealthExample.PackageCheck.check
