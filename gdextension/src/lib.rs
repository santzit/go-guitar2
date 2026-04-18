use godot::prelude::*;

// ── Domain modules (inlined from former workspace crates) ─────────────────────
mod rsapi;
mod audio_mixer;
mod audio_io;
mod audio_engine_core;
mod tone_engine;

// ── Q pitch-detection FFI (only when Q headers + q_bridge lib are present) ────
#[cfg(q_available)]
mod q_ffi;
#[cfg(q_available)]
mod pitch_detector;

// ── Godot GDExtension wrapper classes ─────────────────────────────────────────
mod audio_engine;
mod goguitar_bridge;
mod rt_engine;

struct GoGuitar2Extension;

#[gdextension]
unsafe impl ExtensionLibrary for GoGuitar2Extension {}
