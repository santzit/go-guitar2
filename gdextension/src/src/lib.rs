use godot::prelude::*;

mod audio_engine;
mod psarc_parser;
mod rocksmith_bridge;
mod rt_engine;

struct GoGuitar2Extension;

#[gdextension]
unsafe impl ExtensionLibrary for GoGuitar2Extension {}
