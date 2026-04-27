use godot::prelude::*;

// ── Domain modules (inlined from former workspace crates) ─────────────────────
mod rsapi;
pub mod bandpass;

// ── Q pitch-detection FFI (only when Q headers + q_bridge lib are present) ────
#[cfg(q_available)]
mod q_ffi;
#[cfg(q_available)]
pub mod pitch_detector;
#[cfg(q_available)]
mod q_engine;

// ── Godot GDExtension wrapper classes ─────────────────────────────────────────
mod audio_engine;
mod goguitar_bridge;

struct GoGuitar2Extension;

#[gdextension]
unsafe impl ExtensionLibrary for GoGuitar2Extension {}
