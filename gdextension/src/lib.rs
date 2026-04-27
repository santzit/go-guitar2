use godot::prelude::*;

// ── Domain modules (inlined from former workspace crates) ─────────────────────
mod rsapi;

// ── Godot GDExtension wrapper classes ─────────────────────────────────────────
mod audio_engine;
mod goguitar_bridge;

struct GoGuitar2Extension;

#[gdextension]
unsafe impl ExtensionLibrary for GoGuitar2Extension {}
