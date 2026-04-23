/// bandpass.rs — Per-string biquad bandpass pre-filters for guitar pitch detection.
///
/// This module is **always compiled** (no `q_available` gate) so that the
/// filter implementation can be used by integration tests even when the
/// cycfi/q submodules are not present.
///
/// # Standard E tuning — frequency ranges
///
/// Each string has a bandpass filter whose centre is the geometric mean of the
/// open-string fundamental and the 24th-fret fundamental, and whose bandwidth
/// equals `max_hz − min_hz`.  Overlapping ranges are intentional; the Q pitch
/// detector downstream resolves ambiguity.
///
/// | String | Open note | min Hz  | max Hz   | centre Hz |
/// |--------|-----------|---------|----------|-----------|
/// |   6    | E2 (low)  |  73.4   |   350.0  |  160.0    |
/// |   5    | A2        |  98.0   |   470.0  |  214.5    |
/// |   4    | D3        | 130.8   |   620.0  |  284.6    |
/// |   3    | G3        | 174.6   |   830.0  |  380.5    |
/// |   2    | B3        | 220.0   |  1050.0  |  480.4    |
/// |   1    | E4 (high) | 293.7   |  1400.0  |  641.2    |

// ── String frequency ranges (Standard E, frets 0–24) ─────────────────────────

/// `(min_hz, max_hz)` per string.
/// Index 0 = String 6 (low E2), index 5 = String 1 (high e4).
pub const STRING_RANGES: [(f32, f32); 6] = [
    ( 73.4,  350.0),  // String 6 — E2  (low E)  : 82.4 Hz open, safety margin below + above
    ( 98.0,  470.0),  // String 5 — A2            : 110.0 Hz open
    (130.8,  620.0),  // String 4 — D3            : 146.8 Hz open
    (174.6,  830.0),  // String 3 — G3            : 196.0 Hz open
    (220.0, 1050.0),  // String 2 — B3            : 246.9 Hz open
    (293.7, 1400.0),  // String 1 — E4  (high e)  : 329.6 Hz open
];

/// Open-string note names, index 0 = String 6.
pub const STRING_NAMES: [&str; 6] = ["E2 (Low E)", "A2", "D3", "G3", "B3", "E4 (High e)"];

/// Open-string fundamental frequencies in Hz, index 0 = String 6.
pub const OPEN_FREQS: [f32; 6] = [82.41, 110.00, 146.83, 196.00, 246.94, 329.63];

// ── Biquad bandpass filter ────────────────────────────────────────────────────

/// Second-order IIR bandpass filter (Audio EQ Cookbook — constant 0 dB peak gain).
///
/// Designed with:
///   `center_hz` = geometric mean of the string's min/max frequency
///   `bw_hz`     = max_hz − min_hz  (so Q = center / bandwidth)
///
/// Direct Form I recurrence:
/// ```text
///   y[n] = B0·x[n] + B2·x[n-2] − A1·y[n-1] − A2·y[n-2]
/// ```
/// (B1 = 0 for this bandpass topology)
pub struct BiquadBandpass {
    b0: f32,
    b2: f32,    // b1 is always 0 for this bandpass topology
    a1: f32,
    a2: f32,
    x1: f32,
    x2: f32,
    y1: f32,
    y2: f32,
}

impl BiquadBandpass {
    /// Design a bandpass biquad with centre `center_hz` and bandwidth `bw_hz`.
    ///
    /// From the Audio EQ Cookbook (R. Bristow-Johnson):
    /// ```text
    ///   w0    = 2π · center_hz / fs
    ///   alpha = sin(w0) / (2Q)        where Q = center / bw
    ///   b0    =  sin(w0)/2,  b1 = 0,  b2 = −sin(w0)/2
    ///   a0    =  1 + alpha,  a1 = −2·cos(w0),  a2 = 1 − alpha
    /// ```
    pub fn new(center_hz: f32, bw_hz: f32, sample_rate: u32) -> Self {
        use std::f32::consts::PI;
        let fs    = sample_rate as f32;
        let w0    = 2.0 * PI * center_hz / fs;
        let q     = (center_hz / bw_hz).max(0.1);   // guard against zero bandwidth
        let alpha = w0.sin() / (2.0 * q);

        let b0_raw =  w0.sin() * 0.5;
        let b2_raw = -w0.sin() * 0.5;
        let a0_raw =  1.0 + alpha;
        let a1_raw = -2.0 * w0.cos();
        let a2_raw =  1.0 - alpha;

        Self {
            b0: b0_raw / a0_raw,
            b2: b2_raw / a0_raw,
            a1: a1_raw / a0_raw,
            a2: a2_raw / a0_raw,
            x1: 0.0, x2: 0.0,
            y1: 0.0, y2: 0.0,
        }
    }

    /// Construct a filter from a `(min_hz, max_hz)` range for a guitar string.
    /// Centre is the geometric mean; bandwidth is `max − min`.
    pub fn for_string(min_hz: f32, max_hz: f32, sample_rate: u32) -> Self {
        let center = (min_hz * max_hz).sqrt();
        let bw     = max_hz - min_hz;
        Self::new(center, bw, sample_rate)
    }

    /// Process one sample through the filter.
    #[inline]
    pub fn process(&mut self, x: f32) -> f32 {
        let y = self.b0 * x
              + self.b2 * self.x2
              - self.a1 * self.y1
              - self.a2 * self.y2;
        self.x2 = self.x1;
        self.x1 = x;
        self.y2 = self.y1;
        self.y1 = y;
        y
    }

    /// Reset all filter state (delay-line taps) to zero.
    pub fn reset(&mut self) {
        self.x1 = 0.0;
        self.x2 = 0.0;
        self.y1 = 0.0;
        self.y2 = 0.0;
    }

    /// Compute the RMS energy of a signal after passing it through this filter.
    pub fn measure_rms(&mut self, samples: &[f32]) -> f32 {
        self.reset();
        let sum_sq: f64 = samples
            .iter()
            .map(|&s| {
                let y = self.process(s) as f64;
                y * y
            })
            .sum();
        ((sum_sq / samples.len().max(1) as f64) as f32).sqrt()
    }
}

/// Build one bandpass filter per string for the given sample rate.
///
/// Returns `[BiquadBandpass; 6]`, index 0 = String 6 (low E), index 5 = String 1.
pub fn build_string_filters(sample_rate: u32) -> [BiquadBandpass; 6] {
    STRING_RANGES.map(|(min, max)| BiquadBandpass::for_string(min, max, sample_rate))
}
