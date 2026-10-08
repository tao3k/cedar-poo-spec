import Productions.Data.ProtectedStorageFixture

def main : IO Unit :=
  IO.println CedarPooSpec.Data.ProtectedStorageFixture.fixture.compress
