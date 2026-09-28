//! Measure steady-state Cedar artifact admission and rendering in one process.

use cedar_poo_bridge::{
    CompiledPolicyJson, Manifest, check_manifest, load_policy_set, render_artifacts,
    render_loaded_policy_set, render_policy_source, replay_manifest,
};
use std::hint::black_box;
use std::time::{Duration, Instant};

const WARMUP: usize = 100;
const DEFAULT_SAMPLES: usize = 2_000;

fn measure(samples: usize, mut operation: impl FnMut()) -> Vec<Duration> {
    for _ in 0..WARMUP {
        operation();
    }
    let mut timings = Vec::with_capacity(samples);
    for _ in 0..samples {
        let start = Instant::now();
        operation();
        timings.push(start.elapsed());
    }
    timings.sort_unstable();
    timings
}

fn report(name: &str, samples: &[Duration]) {
    let total: Duration = samples.iter().copied().sum();
    let mean_us = total.as_secs_f64() * 1_000_000.0 / samples.len() as f64;
    let p50_us = samples[samples.len() / 2].as_secs_f64() * 1_000_000.0;
    let p95_us = samples[samples.len() * 95 / 100].as_secs_f64() * 1_000_000.0;
    println!("{name}: mean={mean_us:.1}us p50={p50_us:.1}us p95={p95_us:.1}us");
}

fn main() -> Result<(), String> {
    let mut args = std::env::args().skip(1);
    let path = args.next().ok_or(
        "usage: export_latency POLICY_SET_JSON [POLICIES] [SAMPLES] | --manifest PATH [SAMPLES]",
    )?;
    if path == "--manifest" {
        let manifest_path = args.next().ok_or("missing manifest path")?;
        let samples = args
            .next()
            .map(|value| value.parse::<usize>().map_err(|error| error.to_string()))
            .transpose()?
            .unwrap_or(DEFAULT_SAMPLES);
        if samples == 0 {
            return Err("sample count must be positive".into());
        }
        let source = std::fs::read_to_string(&manifest_path).map_err(|error| error.to_string())?;
        let manifest: Manifest =
            serde_json::from_str(&source).map_err(|error| error.to_string())?;
        println!(
            "manifest={manifest_path} bytes={} cases={} warmup={WARMUP} samples={samples}",
            source.len(),
            manifest.cases.len()
        );
        report(
            "render-artifacts",
            &measure(samples, || {
                black_box(render_artifacts(black_box(&manifest)).expect("valid manifest"));
            }),
        );
        report(
            "check-manifest",
            &measure(samples, || {
                check_manifest(black_box(&manifest)).expect("valid manifest");
            }),
        );
        report(
            "replay-receipts",
            &measure(samples, || {
                black_box(replay_manifest(black_box(&manifest)).expect("valid manifest"));
            }),
        );
        return Ok(());
    }
    let requested_policies = args
        .next()
        .map(|value| value.parse::<usize>().map_err(|error| error.to_string()))
        .transpose()?;
    let samples = args
        .next()
        .map(|value| value.parse::<usize>().map_err(|error| error.to_string()))
        .transpose()?
        .unwrap_or(DEFAULT_SAMPLES);
    if samples == 0 || requested_policies == Some(0) {
        return Err("policy count and sample count must be positive".into());
    }
    let mut source = std::fs::read_to_string(&path).map_err(|error| error.to_string())?;
    if let Some(count) = requested_policies {
        let mut value: serde_json::Value =
            serde_json::from_str(&source).map_err(|error| error.to_string())?;
        let policies = value
            .get_mut("staticPolicies")
            .and_then(serde_json::Value::as_object_mut)
            .ok_or("missing staticPolicies")?;
        let originals = policies
            .iter()
            .map(|(id, policy)| (id.clone(), policy.clone()))
            .collect::<Vec<_>>();
        if originals.is_empty() {
            return Err("cannot scale an empty policy set".into());
        }
        policies.clear();
        for index in 0..count {
            let (id, policy) = &originals[index % originals.len()];
            policies.insert(format!("{id}-{index}"), policy.clone());
        }
        source = serde_json::to_string(&value).map_err(|error| error.to_string())?;
    }
    let artifact: CompiledPolicyJson = source.parse().map_err(|error| format!("{error}"))?;
    let loaded = load_policy_set(&artifact)?;
    let policy_count = loaded.policies().count();
    println!(
        "artifact={path} bytes={} policies={policy_count} warmup={WARMUP} samples={samples}",
        source.len()
    );
    report(
        "admit",
        &measure(samples, || {
            black_box(load_policy_set(black_box(&artifact)).expect("valid policy artifact"));
        }),
    );
    report(
        "render-loaded",
        &measure(samples, || {
            black_box(render_loaded_policy_set(black_box(&loaded)).expect("renderable policy set"));
        }),
    );
    report(
        "admit+render",
        &measure(samples, || {
            black_box(
                render_policy_source(black_box(&artifact)).expect("renderable policy artifact"),
            );
        }),
    );
    report(
        "decode+admit+render",
        &measure(samples, || {
            let decoded: CompiledPolicyJson = black_box(&source).parse().expect("valid JSON");
            black_box(render_policy_source(&decoded).expect("renderable policy artifact"));
        }),
    );
    Ok(())
}
