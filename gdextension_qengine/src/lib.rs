use godot::prelude::*;

#[path = "../../gdextension/src/bandpass.rs"]
pub mod bandpass;

#[cfg(q_available)]
#[path = "../../gdextension/src/q_ffi.rs"]
mod q_ffi;

#[cfg(q_available)]
#[path = "../../gdextension/src/pitch_detector.rs"]
pub mod pitch_detector;

#[cfg(q_available)]
#[path = "../../gdextension/src/q_engine.rs"]
mod q_engine;

struct QEngineExtension;

#[gdextension]
unsafe impl ExtensionLibrary for QEngineExtension {}
