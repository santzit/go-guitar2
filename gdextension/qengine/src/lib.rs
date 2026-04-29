use godot::prelude::*;

pub mod bandpass;

#[cfg(q_available)]
mod q_ffi;

#[cfg(q_available)]
pub mod pitch_detector;

#[cfg(q_available)]
mod q_engine;

struct QEngineExtension;

#[gdextension]
unsafe impl ExtensionLibrary for QEngineExtension {}
