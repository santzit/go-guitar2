use godot::prelude::*;

mod rocksmith_bridge;

struct GoGuitar2Extension;

#[gdextension]
unsafe impl ExtensionLibrary for GoGuitar2Extension {}
