/// q_pitch_detector.rs — Godot GDExtension class for per-string guitar pitch detection.
///
/// Wraps the cycfi/Q `pitch_detector` (BACF algorithm) exposed through
/// the C FFI layer in `q_pitch_ffi.cpp`.
///
/// GDScript usage:
/// ```gdscript
/// var qpd := QPitchDetector.new()
///
/// # detect_strings() returns an Array of 6 Dictionaries:
/// #   { "string_idx": int,   – 0..5  (0 = low E, 5 = high e)
/// #     "active":     bool,  – true if a pitch was detected in this band
/// #     "hz":         float, – detected frequency in Hz (0.0 when inactive)
/// #     "midi":       int,   – MIDI note number (0 when inactive)
/// #     "note":       String,– e.g. "A3"  ("" when inactive)
/// #     "fret":       int }  – 0..24 (-1 when inactive)
/// var result := qpd.detect_strings(samples, 44100)
/// ```

use godot::prelude::*;

// ── C FFI ──────────────────────────────────────────────────────────────────────

/// Mirror of the `QStringResult` struct in `q_pitch_ffi.h`.
#[repr(C)]
struct QStringResult {
    active: i32,
    hz:     f32,
}

extern "C" {
    /// Process `n_samples` mono float32 samples through six per-string
    /// cycfi/Q pitch detectors and write results into `out[6]`.
    fn q_detect_strings(
        samples:     *const f32,
        n_samples:   i32,
        sample_rate: f32,
        out:         *mut QStringResult,
    );
}

// ── Pitch helper constants ────────────────────────────────────────────────────

/// Open-string MIDI note numbers in standard EADGBE tuning.
/// Index 0 = string 6 (low E2 = MIDI 40), index 5 = string 1 (high e4 = MIDI 64).
const OPEN_STRING_MIDI: [i32; 6] = [40, 45, 50, 55, 59, 64];

/// Chromatic note names, index 0 = C.
const NOTE_NAMES: [&str; 12] = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"];

const MAX_FRET: i32 = 24;

fn midi_note_name(midi: i32) -> GString {
    let name = NOTE_NAMES[((midi % 12) + 12) as usize % 12];
    let octave = midi / 12 - 1;
    let s = format!("{}{}", name, octave);
    GString::from(s.as_str())
}

// ── GDExtension class ─────────────────────────────────────────────────────────

/// **QPitchDetector** — Godot GDExtension class for per-string guitar pitch
/// detection using the cycfi/Q BACF pitch detector.
///
/// Call `detect_strings(samples, sample_rate)` with a mono float32 audio
/// buffer to obtain frequency, MIDI note, fret, and active state for each
/// of the six guitar strings simultaneously.
#[derive(GodotClass)]
#[class(base = Object)]
pub struct QPitchDetector {
    #[base]
    base: Base<Object>,
}

#[godot_api]
impl IObject for QPitchDetector {
    fn init(base: Base<Object>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl QPitchDetector {
    /// Detect the pitch on each of the six guitar strings simultaneously.
    ///
    /// `samples`     — mono PCM float32 audio buffer (`PackedFloat32Array`).
    /// `sample_rate` — sample rate in Hz (typically 44100).
    ///
    /// Returns an `Array` of exactly 6 `Dictionary` entries
    /// (index 0 = string 6 low E, index 5 = string 1 high e):
    /// ```
    /// {
    ///   "string_idx": int,    # 0..5
    ///   "active":     bool,   # true when a pitch is detected
    ///   "hz":         float,  # detected frequency in Hz (0.0 when inactive)
    ///   "midi":       int,    # MIDI note number (0 when inactive)
    ///   "note":       String, # e.g. "A3"  ("" when inactive)
    ///   "fret":       int,    # 0..24  (-1 when inactive)
    /// }
    /// ```
    #[func]
    pub fn detect_strings(
        &self,
        samples:     PackedFloat32Array,
        sample_rate: i32,
    ) -> Array<Variant> {
        let sr = sample_rate as f32;

        let mut raw: [QStringResult; 6] = [
            QStringResult { active: 0, hz: 0.0 },
            QStringResult { active: 0, hz: 0.0 },
            QStringResult { active: 0, hz: 0.0 },
            QStringResult { active: 0, hz: 0.0 },
            QStringResult { active: 0, hz: 0.0 },
            QStringResult { active: 0, hz: 0.0 },
        ];

        // Convert to a contiguous Vec<f32> so we can pass a stable raw pointer
        // to the C FFI function.  This avoids holding a borrow across the
        // unsafe boundary where Godot's internal layout is opaque.
        let vec: Vec<f32> = samples.to_vec();
        let n = vec.len() as i32;

        // SAFETY: `vec` is a valid, fully-owned Vec<f32> whose data lives for
        // the duration of this call.  `raw` is a properly-sized, aligned
        // stack buffer.  The C function is synchronous and retains no pointers.
        unsafe {
            q_detect_strings(
                vec.as_ptr(),
                n,
                sr,
                raw.as_mut_ptr(),
            );
        }

        let mut result: Array<Variant> = Array::new();
        for (s, r) in raw.iter().enumerate() {
            let mut dict: Dictionary<GString, Variant> = Dictionary::new();
            let active = r.active != 0;
            dict.set(&GString::from("string_idx"), s as i32);
            dict.set(&GString::from("active"),     active);
            if active {
                let hz   = r.hz;
                let midi = (69.0 + 12.0 * (hz / 440.0_f32).log2()).round() as i32;
                let fret = (midi - OPEN_STRING_MIDI[s]).clamp(0, MAX_FRET);
                let note = midi_note_name(midi);
                dict.set(&GString::from("hz"),   hz);
                dict.set(&GString::from("midi"), midi);
                dict.set(&GString::from("note"), &note.to_variant());
                dict.set(&GString::from("fret"), fret);
            } else {
                dict.set(&GString::from("hz"),   0.0_f32);
                dict.set(&GString::from("midi"), 0_i32);
                dict.set(&GString::from("note"), &GString::new().to_variant());
                dict.set(&GString::from("fret"), -1_i32);
            }
            result.push(&dict.to_variant());
        }
        result
    }
}
