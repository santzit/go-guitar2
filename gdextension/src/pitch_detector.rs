/// pitch_detector.rs — 6-string guitar pitch detection via cycfi/q.
///
/// Maintains one `cycfi::q::pitch_detector` per guitar string, each tuned
/// to the frequency range that covers open-string to 24th-fret in Standard E
/// tuning.  Every input sample is fed to all six detectors; the one with the
/// highest periodicity (confidence) wins when multiple fire at once.
///
/// # Standard E tuning — open string → 24th fret fundamentals
///
/// | String | Open note | Open Hz  | 24th fret | 24th Hz  |
/// |--------|-----------|----------|-----------|----------|
/// |   6    | E2 (low)  |  82.4 Hz | E4        | 329.6 Hz |
/// |   5    | A2        | 110.0 Hz | A4        | 440.0 Hz |
/// |   4    | D3        | 146.8 Hz | D5        | 587.3 Hz |
/// |   3    | G3        | 196.0 Hz | G5        | 784.0 Hz |
/// |   2    | B3        | 246.9 Hz | B5        | 987.8 Hz |
/// |   1    | E4 (high) | 329.6 Hz | E6        |1318.5 Hz |
///
/// String index 0 in code = String 6 (low E) for memory layout convenience.
/// GDScript receives string numbers 1–6.
///
/// # Godot usage
/// ```gdscript
/// var pd := PitchDetector.new()
/// pd.start(48000)
/// pd.process_samples(pcm_i16_le_bytes)   # feed DI input
/// var r := pd.get_last_result()
/// # r["detected"], r["string"] (1-6), r["frequency"], r["periodicity"]
/// ```

use godot::prelude::*;
use crate::q_ffi;

// ── String frequency ranges (Standard E, frets 0–24) ─────────────────────────

/// `(min_hz, max_hz)` per string.  Index 0 = String 6 (low E2), index 5 = String 1 (high e4).
pub const STRING_RANGES: [(f32, f32); 6] = [
    ( 73.4,  350.0),  // String 6 — E2  (low E)  : 82.4 Hz open, safety margin below + above
    ( 98.0,  470.0),  // String 5 — A2            : 110.0 Hz open
    (130.8,  620.0),  // String 4 — D3            : 146.8 Hz open
    (174.6,  830.0),  // String 3 — G3            : 196.0 Hz open
    (220.0, 1050.0),  // String 2 — B3            : 246.9 Hz open
    (293.7, 1400.0),  // String 1 — E4  (high e)  : 329.6 Hz open
];

/// Standard open-string names, index 0 = String 6.
pub const STRING_NAMES: [&str; 6] = ["E2 (Low E)", "A2", "D3", "G3", "B3", "E4 (High e)"];

/// Minimum periodicity (confidence) required to report a detection.
const MIN_PERIODICITY: f32 = 0.6;

/// Q hysteresis threshold in dB (negative → silence gating).
const HYSTERESIS_DB: f32 = -40.0;

// ── Per-string detector ───────────────────────────────────────────────────────

/// Owns one `QPitchDetector` C++ handle (non-null invariant after construction).
struct StringDetector {
    raw: *mut q_ffi::QPitchDetector,
}

// SAFETY: `QPitchDetector` is accessed only from one thread at a time.
unsafe impl Send for StringDetector {}
unsafe impl Sync for StringDetector {}

impl StringDetector {
    fn new(min_hz: f32, max_hz: f32, sample_rate: u32) -> Option<Self> {
        let raw = unsafe {
            q_ffi::q_pd_create(min_hz, max_hz, sample_rate, HYSTERESIS_DB)
        };
        if raw.is_null() {
            None
        } else {
            Some(Self { raw })
        }
    }

    /// Feed one sample; returns `true` when a new pitch estimate is ready.
    #[inline]
    fn process(&self, sample: f32) -> bool {
        unsafe { q_ffi::q_pd_process(self.raw, sample) }
    }

    /// Most recent detected frequency in Hz (also refreshes cached periodicity).
    #[inline]
    fn frequency(&self) -> f32 {
        unsafe { q_ffi::q_pd_get_frequency(self.raw) }
    }

    /// Most recent periodicity / confidence in [0.0, 1.0].
    /// Must be called *after* `frequency()` to get the matching value.
    #[inline]
    fn periodicity(&self) -> f32 {
        unsafe { q_ffi::q_pd_get_periodicity(self.raw) }
    }
}

impl Drop for StringDetector {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe { q_ffi::q_pd_destroy(self.raw) };
            self.raw = std::ptr::null_mut();
        }
    }
}

// ── Detection result ──────────────────────────────────────────────────────────

/// Result of a pitch-detection event.
#[derive(Clone, Debug, Default)]
pub struct DetectionResult {
    /// `true` when a pitch was detected with sufficient confidence.
    pub detected:     bool,
    /// 0-based string index (0 = String 6 / low E, 5 = String 1 / high e).
    pub string_index: usize,
    /// Detected fundamental frequency in Hz.
    pub frequency:    f32,
    /// Periodicity / confidence score in [0.0, 1.0].
    pub periodicity:  f32,
}

// ── 6-string guitar pitch detector ───────────────────────────────────────────

/// Runs six independent Q pitch detectors, one per guitar string.
///
/// Call `process()` with each input sample.  When a pitch is detected the
/// method returns `Some(DetectionResult)` carrying the winning string,
/// frequency, and confidence.
pub struct GuitarPitchDetector {
    detectors:   Vec<StringDetector>,   // length == 6
    last_result: DetectionResult,
    sample_rate: u32,
}

impl GuitarPitchDetector {
    /// Allocate six Q pitch detectors (one per string) for `sample_rate` Hz.
    /// Returns `None` if any detector could not be created.
    pub fn new(sample_rate: u32) -> Option<Self> {
        let mut detectors = Vec::with_capacity(6);
        for (min, max) in &STRING_RANGES {
            match StringDetector::new(*min, *max, sample_rate) {
                Some(d) => detectors.push(d),
                None    => return None,
            }
        }
        Some(Self {
            detectors,
            last_result: DetectionResult::default(),
            sample_rate,
        })
    }

    /// Feed one f32 sample to all six detectors.
    ///
    /// Returns `Some(DetectionResult)` when at least one detector fires and
    /// the winning confidence meets `MIN_PERIODICITY`.
    pub fn process(&mut self, sample: f32) -> Option<DetectionResult> {
        let mut best: Option<DetectionResult> = None;

        for (idx, det) in self.detectors.iter().enumerate() {
            if det.process(sample) {
                let freq = det.frequency();
                let peri = det.periodicity();
                if freq > 0.0 && peri >= MIN_PERIODICITY {
                    let is_better = best.as_ref().map_or(true, |b| peri > b.periodicity);
                    if is_better {
                        best = Some(DetectionResult {
                            detected:     true,
                            string_index: idx,
                            frequency:    freq,
                            periodicity:  peri,
                        });
                    }
                }
            }
        }

        if let Some(ref r) = best {
            self.last_result = r.clone();
        }
        best
    }

    /// Most recent detection result (may be from a previous call).
    pub fn last_result(&self) -> &DetectionResult {
        &self.last_result
    }

    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }
}

/// Convert 0-based internal string index (0 = low E) to 1-based guitar string number (6 = low E).
#[inline]
fn to_string_number(idx: usize) -> i64 {
    (6 - idx) as i64
}

// ── Godot GDExtension class ───────────────────────────────────────────────────

/// **PitchDetector** — Godot class for 6-string guitar pitch detection.
///
/// Uses one `cycfi::q::pitch_detector` per string, configured with Standard E
/// tuning frequency ranges.  Feed PCM-16-LE bytes captured from the guitar DI
/// input (e.g. via `RtEngine`'s input ring buffer) and poll `get_last_result()`
/// every frame.
///
/// GDScript example:
/// ```gdscript
/// var pd := PitchDetector.new()
/// pd.start(48000)
///
/// func _process(_delta: float) -> void:
///     var bytes := rt_engine.pop_input_samples()   # your DI ring-buffer read
///     pd.process_samples(bytes)
///     var r := pd.get_last_result()
///     if r["detected"]:
///         print("String %d  %.1f Hz  (%.2f)" % [r["string"], r["frequency"], r["periodicity"]])
/// ```
#[derive(GodotClass)]
#[class(base = Object)]
pub struct PitchDetector {
    #[base]
    base:     Base<Object>,
    detector: Option<GuitarPitchDetector>,
}

#[godot_api]
impl IObject for PitchDetector {
    fn init(base: Base<Object>) -> Self {
        Self { base, detector: None }
    }
}

#[godot_api]
impl PitchDetector {
    // ── Lifecycle ─────────────────────────────────────────────────────────────

    /// Allocate all six Q pitch detectors for the given sample rate.
    /// Returns `true` on success.  Safe to call multiple times (restarts detector).
    #[func]
    pub fn start(&mut self, sample_rate: i32) -> bool {
        let sr = sample_rate.clamp(8_000, 192_000) as u32;
        match GuitarPitchDetector::new(sr) {
            Some(d) => {
                self.detector = Some(d);
                godot_print!("PitchDetector: started — 6 strings, Standard E, {} Hz", sr);
                true
            }
            None => {
                godot_error!("PitchDetector: failed to create Q pitch detectors \
                              (Q library may not be linked).");
                false
            }
        }
    }

    /// Stop and free all detectors.
    #[func]
    pub fn stop(&mut self) {
        self.detector = None;
        godot_print!("PitchDetector: stopped.");
    }

    /// Returns `true` if the detector is running.
    #[func]
    pub fn is_running(&self) -> bool {
        self.detector.is_some()
    }

    // ── Sample processing ─────────────────────────────────────────────────────

    /// Feed raw PCM-16-LE bytes (mono, matching the sample rate passed to `start()`).
    ///
    /// Returns an Array of Dictionaries — one entry per detection event that
    /// occurred while processing the provided block:
    /// ```gdscript
    /// { "string": int,       # 1-based guitar string (1 = high e, 6 = low E)
    ///   "frequency": float,  # detected fundamental in Hz
    ///   "periodicity": float # confidence [0.0, 1.0] }
    /// ```
    #[func]
    pub fn process_samples(&mut self, data: PackedByteArray) -> Array<Dictionary> {
        let mut events = Array::new();
        let det = match self.detector.as_mut() {
            Some(d) => d,
            None    => return events,
        };

        let raw: Vec<u8> = data.to_vec();
        for chunk in raw.chunks_exact(2) {
            let s = i16::from_le_bytes([chunk[0], chunk[1]]) as f32 / 32_768.0;
            if let Some(r) = det.process(s) {
                let mut d = Dictionary::new();
                d.set("string",      to_string_number(r.string_index));
                d.set("frequency",   r.frequency);
                d.set("periodicity", r.periodicity);
                events.push(&d);
            }
        }
        events
    }

    /// Returns the most recent detection result as a Dictionary.
    /// `"detected"` is `false` when no pitch has been found yet.
    ///
    /// Keys: `"detected"` (bool), `"string"` (int 1–6), `"frequency"` (float),
    ///       `"periodicity"` (float).
    #[func]
    pub fn get_last_result(&self) -> Dictionary {
        let mut d = Dictionary::new();
        let r = match self.detector.as_ref() {
            Some(det) => det.last_result(),
            None => {
                d.set("detected",    false);
                d.set("string",      0i64);
                d.set("frequency",   0.0f32);
                d.set("periodicity", 0.0f32);
                return d;
            }
        };
        d.set("detected",    r.detected);
        d.set("string",      to_string_number(r.string_index));
        d.set("frequency",   r.frequency);
        d.set("periodicity", r.periodicity);
        d
    }

    // ── Metadata ──────────────────────────────────────────────────────────────

    /// Returns the six string frequency ranges as an Array of Dictionaries.
    ///
    /// Each entry: `{ "string": int (1-6), "name": String, "min_hz": float, "max_hz": float }`.
    #[func]
    pub fn get_string_ranges() -> Array<Dictionary> {
        let mut out = Array::new();
        for (idx, ((min, max), name)) in STRING_RANGES.iter().zip(STRING_NAMES.iter()).enumerate() {
            let mut d = Dictionary::new();
            d.set("string",  to_string_number(idx));
            d.set("name",    GString::from(*name));
            d.set("min_hz",  *min);
            d.set("max_hz",  *max);
            out.push(&d);
        }
        out
    }

    /// Minimum periodicity threshold used to accept a detection.
    #[func]
    pub fn get_min_periodicity() -> f32 {
        MIN_PERIODICITY
    }
}
