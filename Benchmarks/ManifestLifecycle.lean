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

-- Use the exact production publication step and retained cross-entry source pools.
-- This attribution mode keeps the ordinary nine-measurement benchmark unchanged.
@[noinline] private def produceActualEntry (producer : CedarPooSpec.Transport.EntryProducer) :
    IO CedarPooSpec.Transport.Entry :=
  CedarPooSpec.Manifests.evaluate (fun _ => producer.run)

@[noinline] private def publishActualEntry (entry : CedarPooSpec.Transport.Entry)
    (pools : CedarPooSpec.Transport.SourcePools) :
    IO (CedarPooSpec.Transport.EncodedJson × CedarPooSpec.Transport.SourcePools) := do
  let (encoded, next) ← CedarPooSpec.Manifests.evaluate (fun _ => (entry.prepare).run pools)
  return (encoded.compact, next)

@[noinline] private def finishActualEntries (entries : List (String × CedarPooSpec.Transport.EncodedJson))
    (pools : CedarPooSpec.Transport.SourcePools) : IO CedarPooSpec.Transport.EncodedJson :=
  pure (pools.finish entries)

private def attributeActual (label : String) : IO String := do
  let mut pools : CedarPooSpec.Transport.SourcePools := {}
  let mut entries := #[]
  let mut observations : Array (String × Nat × Nat × Nat × Nat) := #[]
  for (name, producer) in CedarPooSpec.Manifests.entries do
    let begin ← IO.monoNanosNow
    let firstAlloc ← IO.getNumHeartbeats
    let entry ← produceActualEntry producer
    let producedAlloc ← IO.getNumHeartbeats
    let produced ← IO.monoNanosNow
    let (encoded, next) ← publishActualEntry entry pools
    let publishedAlloc ← IO.getNumHeartbeats
    let published ← IO.monoNanosNow
    pools := next
    entries := entries.push (name, encoded)
    observations := observations.push (name, produced-begin, published-produced,
      producedAlloc-firstAlloc, publishedAlloc-producedAlloc)
  let begin ← IO.monoNanosNow
  let firstAlloc ← IO.getNumHeartbeats
  let encoded ← finishActualEntries entries.toList pools
  let finishedAlloc ← IO.getNumHeartbeats
  let finished ← IO.monoNanosNow
  let wire ← renderActual encoded
  let renderedAlloc ← IO.getNumHeartbeats
  let rendered ← IO.monoNanosNow
  let stdout ← IO.getStdout
  for (name, produce, publish, produceAlloc, publishAlloc) in observations do
    stdout.putStrLn s!"measurement: cedar.catalog.stages.{label}.{name}.produce {produce} ns"
    stdout.putStrLn s!"measurement: cedar.catalog.stages.{label}.{name}.publish {publish} ns"
    stdout.putStrLn s!"measurement: cedar.catalog.stages.{label}.{name}.produce.small_allocations {produceAlloc} count"
    stdout.putStrLn s!"measurement: cedar.catalog.stages.{label}.{name}.publish.small_allocations {publishAlloc} count"
  stdout.putStrLn s!"measurement: cedar.catalog.stages.{label}.finish {finished-begin} ns"
  stdout.putStrLn s!"measurement: cedar.catalog.stages.{label}.serialize {rendered-finished} ns"
  stdout.putStrLn s!"measurement: cedar.catalog.stages.{label}.finish.small_allocations {finishedAlloc-firstAlloc} count"
  stdout.putStrLn s!"measurement: cedar.catalog.stages.{label}.serialize.small_allocations {renderedAlloc-finishedAlloc} count"
  return wire

private def stageBenchmark : IO Unit := do
  -- The first-use pass is separately visible, after native import initialization.
  let first ← attributeActual "first-use"
  for sample in [1, 2, 3] do
    let wire ← attributeActual s!"sample{sample}"
    unless wire == first do throw (IO.userError "stage catalog changed across samples")
  let reference ← renderActual (← prepareActual CedarPooSpec.Manifests.entries)
  unless first == reference do throw (IO.userError "attribution changed production catalog")
  (← IO.getStdout).putStrLn s!"CATALOG-STAGES-OK entries={CedarPooSpec.Manifests.entries.length} bytes={reference.utf8ByteSize} checksum={hash reference} first_use=1 samples=3 production_wire_equal=true"

def main (args : List String) : IO Unit := do
  let started ← IO.monoNanosNow
  let entry ← Std.Time.Timestamp.now
  let pid ← IO.Process.getPID
  let stderr ← IO.getStderr
  stderr.putStrLn (Lean.Json.mkObj [
    ("observation", Lean.toJson "native-main-entry"), ("pid", Lean.toJson pid.toNat),
    ("import_initialization_ns", Lean.toJson (started - CedarPooSpec.ManifestInitialization.started)),
    ("unix_ns", Lean.toJson entry.toNanosecondsSinceUnixEpoch.toInt)]).compress
  if args == ["benchmark"] then benchmark
  else if args == ["stages"] then stageBenchmark
  else CedarPooSpec.Manifests.run args true
  stderr.putStrLn (Lean.Json.mkObj [
    ("observation", Lean.toJson "native-main-return"), ("success", Lean.toJson true),
    ("unix_ns", Lean.toJson (← Std.Time.Timestamp.now).toNanosecondsSinceUnixEpoch.toInt),
    ("elapsed_ns", Lean.toJson ((← IO.monoNanosNow) - started))]).compress
