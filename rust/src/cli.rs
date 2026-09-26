//! Stream a Lean manifest through the Rust Cedar conformance checker.

use crate::{Manifest, check_manifest};
use std::io::{self, Read};

/// Read one JSON manifest from standard input and check all cases.
pub fn run() -> Result<(), String> {
    let mut input = String::new();
    io::stdin()
        .read_to_string(&mut input)
        .map_err(|error| error.to_string())?;
    let manifest: Manifest =
        serde_json::from_str(&input).map_err(|error| format!("manifest JSON: {error}"))?;
    check_manifest(&manifest)?;
    println!("Cedar conformance: {} cases", manifest.cases.len());
    Ok(())
}
