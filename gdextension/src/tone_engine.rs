/// tone-engine — Tone/amp-sim engine stub.
///
/// This crate is a placeholder for a future integration with `rustortion-core`
/// (or a similar guitar amp/effect simulation library).
///
/// API contract (stable — the GDExtension layer depends on this):
/// - `ToneEngine::new()` — create an instance.
/// - `ToneEngine::process_block(input, output)` — process one block of f32 samples.
/// - `ToneEngine::set_preset_name(name)` / `ToneEngine::preset_name()` — preset label.
///
/// Current implementation: **passthrough mock** — output equals input unmodified.
/// Replace the body of `process_block` when `rustortion-core` is integrated.

/// Tone/amp-sim engine (currently a passthrough mock).
pub struct ToneEngine {
    preset: String,
}

impl ToneEngine {
    /// Create a new (mock) tone engine instance.
    pub fn new() -> Self {
        Self {
            preset: "Passthrough (mock)".to_owned(),
        }
    }

    /// Process one block of mono f32 samples.
    ///
    /// `input`  — read-only input samples.
    /// `output` — write output samples (must be ≥ `input.len()` in length).
    ///
    /// **Mock implementation**: copies `input` into `output` unchanged.
    pub fn process_block(&mut self, input: &[f32], output: &mut [f32]) {
        let n = input.len().min(output.len());
        output[..n].copy_from_slice(&input[..n]);
    }

    /// Set the active preset display name.
    pub fn set_preset_name(&mut self, name: &str) {
        self.preset = name.to_owned();
    }

    /// Returns the active preset display name.
    pub fn preset_name(&self) -> &str {
        &self.preset
    }
}

impl Default for ToneEngine {
    fn default() -> Self {
        Self::new()
    }
}
