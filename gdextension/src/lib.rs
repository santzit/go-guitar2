use godot::prelude::*;

// ── Domain modules (inlined from former workspace crates) ─────────────────────
mod rsapi;
mod audio_mixer;
mod audio_io;
mod audio_engine_core;
mod tone_engine;

// ── Godot GDExtension wrapper classes ─────────────────────────────────────────
mod audio_engine;
mod goguitar_bridge;
mod rt_engine;
mod q_pitch_detector;

struct GoGuitar2Extension;

#[gdextension]
unsafe impl ExtensionLibrary for GoGuitar2Extension {}
