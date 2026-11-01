import Benchmarks.ManifestInitialization
import Examples.ManifestCatalog
import Std.Time.DateTime.Timestamp

/- Real catalog lifecycle diagnostics; ordinary latency uses caseManifestsNative. -/
/-- The actual typed catalog, with one warmup and three fixed native samples.
Preparation and serialization stay inside their IO clock boundaries. -/
@[noinline] private def prepareActual (entries : List (String × CedarPooSpec.Transport.EntryProducer)) :
    IO CedarPooSpec.Transport.EncodedJson :=
  CedarPooSpec.Manifests.evaluate (fun _ =>
    CedarPooSpec.Transport.prepareCatalogFrom entries)

@[noinline] private def renderActual (encoded : CedarPooSpec.Transport.EncodedJson) : IO String :=
  pure encoded.wire

private def benchmark : IO Unit := do
  let reference ← renderActual (← prepareActual CedarPooSpec.Manifests.entries)
  let stdout ← IO.getStdout
  for sample in [1, 2, 3] do
    let started ← IO.monoNanosNow
    let encoded ← prepareActual CedarPooSpec.Manifests.entries
    let prepared ← IO.monoNanosNow
    let wire ← renderActual encoded
    let finished ← IO.monoNanosNow
    unless wire == reference do
      throw (IO.userError "complete native catalog changed across samples")
    stdout.putStrLn s!"measurement: cedar.catalog.sample{sample}.prepare {prepared - started} ns"
    stdout.putStrLn s!"measurement: cedar.catalog.sample{sample}.serialize {finished - prepared} ns"
    stdout.putStrLn s!"measurement: cedar.catalog.sample{sample}.total {finished - started} ns"
  stdout.putStrLn s!"CATALOG-NATIVE-OK entries={CedarPooSpec.Manifests.entries.length} bytes={reference.utf8ByteSize} checksum={hash reference} warmup=1 samples=3"

def main (args : List String) : IO Unit := do
  let started ← IO.monoNanosNow
  let entry ← Std.Time.Timestamp.now
  let pid ← IO.Process.getPID
  let stderr ← IO.getStderr
  stderr.putStrLn (Lean.Json.mkObj [
    ("observation", Lean.toJson "native-main-entry"), ("pid", Lean.toJson pid.toNat),
    ("import_initialization_ns", Lean.toJson (started - CedarPooSpec.ManifestInitialization.started)),
    ("unix_ns", Lean.toJson entry.toNanosecondsSinceUnixEpoch.toInt)]).compress
  if args == ["benchmark"] then benchmark else CedarPooSpec.Manifests.run args true
  stderr.putStrLn (Lean.Json.mkObj [
    ("observation", Lean.toJson "native-main-return"), ("success", Lean.toJson true),
    ("unix_ns", Lean.toJson (← Std.Time.Timestamp.now).toNanosecondsSinceUnixEpoch.toInt),
    ("elapsed_ns", Lean.toJson ((← IO.monoNanosNow) - started))]).compress
