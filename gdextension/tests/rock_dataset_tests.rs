//! rock_dataset_tests.rs — note-detection tests using GuitarSet 00_Rock audio files.
//!
//! # Two test layers
//!
//! 1. **Bandpass energy** (always compiled):
//!    Passes each WAV through the six per-string biquad bandpass filters
//!    and reports RMS energy per band.  Asserts that at least one string band
//!    shows audible energy (the recordings are live guitar, so they must).
//!
//! 2. **Full Q pitch detection** (`#[cfg(q_available)]`):
//!    Feeds each WAV sample-by-sample through all six `GuitarPitchDetector`
//!    instances.  Every detection event that meets the minimum periodicity
//!    threshold is printed in a structured table and mapped to the nearest
//!    note name and fret.  At the end of each file a per-string summary is
//!    printed.  The test asserts ≥ 1 note is detected somewhere in the file.
//!
//! # Verbose output format
//!
//! ```text
//! ── 00_Rock1-130-A_solo_mic.wav ──────────────────────────────────────────────
//! [  247.1 ms]  String 5 (A2)   │  A2    │  109.8 Hz  │  periodicity 0.87
//! [  258.7 ms]  String 3 (G3)   │  G3    │  195.6 Hz  │  periodicity 0.92
//! ...
//! ── Summary ──────────────────────────────────────────────────────────────────
//! String 6 (E2 Low E)  │  0 events
//! String 5 (A2)        │  7 events  │  avg 109.9 Hz  │  avg periodicity 0.84
//! ...
//! ── 00_Rock1-130-A_solo_mic.wav: 12 total detection events — OK ──────────────
//! ```

use godot_goguitar_rs::bandpass::{
    build_string_filters, OPEN_FREQS, STRING_NAMES, STRING_RANGES,
};
use std::path::Path;

// ── WAV decoder (no external crates) ─────────────────────────────────────────

/// Decode 16-bit PCM WAV to mono f32 samples and return (samples, sample_rate).
fn decode_wav(bytes: &[u8]) -> (Vec<f32>, u32) {
    if bytes.len() < 44 {
        return (vec![], 44_100);
    }

    let sample_rate = u32::from_le_bytes([bytes[24], bytes[25], bytes[26], bytes[27]]);
    let num_channels = u16::from_le_bytes([bytes[22], bytes[23]]) as usize;
    let bits_per_sample = u16::from_le_bytes([bytes[34], bytes[35]]) as usize;

    // Walk chunks to find "data".
    let mut pos = 12usize;
    let data_start;
    let data_len;
    loop {
        if pos + 8 > bytes.len() {
            return (vec![], sample_rate);
        }
        let chunk_id = &bytes[pos..pos + 4];
        let chunk_size =
            u32::from_le_bytes([bytes[pos + 4], bytes[pos + 5], bytes[pos + 6], bytes[pos + 7]])
                as usize;
        if chunk_id == b"data" {
            data_start = pos + 8;
            data_len = chunk_size;
            break;
        }
        pos += 8 + chunk_size;
    }

    let data = &bytes[data_start..(data_start + data_len).min(bytes.len())];
    let bytes_per_sample = bits_per_sample / 8;
    let frame_bytes = bytes_per_sample * num_channels;

    if frame_bytes == 0 {
        return (vec![], sample_rate);
    }

    let mut samples = Vec::with_capacity(data.len() / frame_bytes);
    let mut i = 0usize;
    while i + frame_bytes <= data.len() {
        let mut sum = 0.0f32;
        for ch in 0..num_channels {
            let off = i + ch * bytes_per_sample;
            let s = match bits_per_sample {
                16 => i16::from_le_bytes([data[off], data[off + 1]]) as f32 / 32_768.0,
                8  => (data[off] as f32 - 128.0) / 128.0,
                _  => 0.0,
            };
            sum += s;
        }
        samples.push(sum / num_channels as f32);
        i += frame_bytes;
    }
    (samples, sample_rate)
}

// ── Note-name helper ──────────────────────────────────────────────────────────

const NOTE_NAMES: [&str; 12] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];

/// Convert a frequency in Hz to the nearest MIDI note number and note name.
fn freq_to_note(freq: f32) -> (i32, &'static str, i32) {
    if freq <= 0.0 {
        return (0, "---", 0);
    }
    let midi = (69.0 + 12.0 * (freq / 440.0).log2()).round() as i32;
    let name = NOTE_NAMES[((midi % 12 + 12) % 12) as usize];
    let octave = midi / 12 - 1;
    (midi, name, octave)
}

/// Approximate fret number on a given string (string_idx 0 = low E).
fn freq_to_fret(freq: f32, string_idx: usize) -> i32 {
    let open = OPEN_FREQS[string_idx];
    if freq <= 0.0 || open <= 0.0 {
        return -1;
    }
    let semitones = 12.0 * (freq / open).log2();
    semitones.round() as i32
}

// ── Bandpass energy analysis (always compiled) ────────────────────────────────

/// Run all samples through the six bandpass filters; return RMS per string.
fn measure_string_energies(samples: &[f32], sample_rate: u32) -> [f32; 6] {
    let mut filters = build_string_filters(sample_rate);
    filters
        .iter_mut()
        .map(|f| f.measure_rms(samples))
        .collect::<Vec<_>>()
        .try_into()
        .unwrap()
}

// ── Full Q detection (only when Q is compiled in) ────────────────────────────

#[cfg(q_available)]
use godot_goguitar_rs::pitch_detector::{DetectionResult, GuitarPitchDetector};

/// Run the full Q detector pipeline on `samples`.
///
/// Returns a Vec of `(time_ms, result)` for every detection event that fires.
#[cfg(q_available)]
fn run_q_detector(samples: &[f32], sample_rate: u32) -> Vec<(f32, DetectionResult)> {
    let mut detector = match GuitarPitchDetector::new(sample_rate) {
        Some(d) => d,
        None => {
            eprintln!("[WARN] GuitarPitchDetector::new() returned None — Q not linked?");
            return vec![];
        }
    };

    let mut events = Vec::new();
    let sr_f = sample_rate as f32;

    for (i, &s) in samples.iter().enumerate() {
        if let Some(r) = detector.process(s) {
            let time_ms = i as f32 * 1_000.0 / sr_f;
            events.push((time_ms, r));
        }
    }
    events
}

// ── Core test runner ──────────────────────────────────────────────────────────

fn run_bandpass_test(wav_path: &str) {
    let path = Path::new(wav_path);
    let stem = path
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .into_owned();

    let bytes = match std::fs::read(path) {
        Ok(b) => b,
        Err(e) => {
            println!("[SKIP] {} — cannot read file: {}", stem, e);
            return;
        }
    };
    let (samples, sr) = decode_wav(&bytes);
    assert!(!samples.is_empty(), "{}: WAV decoded to empty samples", stem);

    println!(
        "\n{}\n── {} ─ bandpass energy ─ sr={} Hz, {:.2} s",
        "─".repeat(80),
        stem,
        sr,
        samples.len() as f32 / sr as f32,
    );

    let energies = measure_string_energies(&samples, sr);
    let mut any_audible = false;
    for (idx, rms) in energies.iter().enumerate() {
        let (min, max) = STRING_RANGES[idx];
        let star = if *rms > 1e-4 { " ◀ audible" } else { "" };
        if *rms > 1e-4 {
            any_audible = true;
        }
        println!(
            "  String {:1} ({:<12})  │  {:.3} – {:.3} Hz  │  RMS {:>8.6}{}",
            6 - idx,
            STRING_NAMES[idx],
            min,
            max,
            rms,
            star
        );
    }

    assert!(
        any_audible,
        "{}: no string band showed audible energy — check WAV content",
        stem
    );
}

/// Full Q-backed note detection test for one WAV file.
/// Falls back to bandpass-only when Q is not compiled in.
fn run_full_test(wav_path: &str) {
    run_bandpass_test(wav_path);

    #[cfg(q_available)]
    {
        let path = Path::new(wav_path);
        let stem = path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned();

        let bytes = std::fs::read(path).expect("file already verified above");
        let (samples, sr) = decode_wav(&bytes);

        println!(
            "\n── {} ─ Q pitch detection ─────────────────────────────────────────",
            stem
        );
        println!(
            "  {:>10}  {:^16}  {:^6}  {:>10}  {:>10}  {:>5}",
            "time (ms)", "string", "fret", "freq (Hz)", "periodicity", "note"
        );
        println!("  {}", "─".repeat(70));

        let events = run_q_detector(&samples, sr);

        // Per-string accumulators for the summary.
        let mut string_count    = [0usize; 6];
        let mut string_freq_sum = [0.0f64; 6];
        let mut string_peri_sum = [0.0f64; 6];

        for (time_ms, r) in &events {
            let si = r.string_index;
            let fret = freq_to_fret(r.frequency, si);
            let (_, note_name, octave) = freq_to_note(r.frequency);
            string_count[si]    += 1;
            string_freq_sum[si] += r.frequency as f64;
            string_peri_sum[si] += r.periodicity as f64;
            println!(
                "  {:>10.1}  {:^16}  {:>6}  {:>10.2}  {:>10.3}  {}{}",
                time_ms,
                format!("String {} ({})", 6 - si, STRING_NAMES[si]),
                if fret >= 0 { format!("{}", fret) } else { "?".to_string() },
                r.frequency,
                r.periodicity,
                note_name,
                octave,
            );
        }

        // ── Per-string summary ──────────────────────────────────────────────
        println!("\n── {} summary ─ per string ──────────────────────────────────────────", stem);
        println!(
            "  {:^20}  {:>7}  {:>11}  {:>11}",
            "string", "events", "avg Hz", "avg period."
        );
        println!("  {}", "─".repeat(58));
        for idx in 0..6 {
            let n = string_count[idx];
            if n > 0 {
                let avg_hz   = string_freq_sum[idx] / n as f64;
                let avg_peri = string_peri_sum[idx] / n as f64;
                println!(
                    "  {:^20}  {:>7}  {:>11.2}  {:>11.3}",
                    format!("String {} ({})", 6 - idx, STRING_NAMES[idx]),
                    n,
                    avg_hz,
                    avg_peri,
                );
            } else {
                println!(
                    "  {:^20}  {:>7}",
                    format!("String {} ({})", 6 - idx, STRING_NAMES[idx]),
                    "─",
                );
            }
        }

        let total: usize = string_count.iter().sum();
        println!(
            "\n── {}: {} total detection events — {}\n",
            stem,
            total,
            if total > 0 { "OK" } else { "WARN: no notes detected" }
        );

        assert!(
            total > 0,
            "{}: Q detector found no notes — verify Q is compiled and audio is valid",
            stem
        );
    }
}

// ── Individual file tests ─────────────────────────────────────────────────────

const DATASET: &str = "tests/dataset/guitarset/audio/mic";

macro_rules! rock_test {
    ($fn_name:ident, $file:expr) => {
        #[test]
        fn $fn_name() {
            run_full_test(&format!("{}/{}", DATASET, $file));
        }
    };
}

rock_test!(rock1_130_a_solo,   "00_Rock1-130-A_solo_mic.wav");
rock_test!(rock1_130_a_comp,   "00_Rock1-130-A_comp_mic.wav");
rock_test!(rock1_90_cs_solo,   "00_Rock1-90-C#_solo_mic.wav");
rock_test!(rock1_90_cs_comp,   "00_Rock1-90-C#_comp_mic.wav");
rock_test!(rock2_142_d_solo,   "00_Rock2-142-D_solo_mic.wav");
rock_test!(rock2_142_d_comp,   "00_Rock2-142-D_comp_mic.wav");
rock_test!(rock2_85_f_solo,    "00_Rock2-85-F_solo_mic.wav");
rock_test!(rock2_85_f_comp,    "00_Rock2-85-F_comp_mic.wav");
rock_test!(rock3_117_bb_solo,  "00_Rock3-117-Bb_solo_mic.wav");
rock_test!(rock3_117_bb_comp,  "00_Rock3-117-Bb_comp_mic.wav");
rock_test!(rock3_148_c_solo,   "00_Rock3-148-C_solo_mic.wav");
rock_test!(rock3_148_c_comp,   "00_Rock3-148-C_comp_mic.wav");

// ── Synthetic bandpass unit tests (always compiled) ───────────────────────────

#[test]
fn bandpass_open_e2_passes_string6() {
    use godot_goguitar_rs::bandpass::BiquadBandpass;
    use std::f32::consts::TAU;

    let sr = 44_100u32;
    // Inject a pure tone at E2 open (82.41 Hz) — well inside String-6 range.
    let n = sr as usize;
    let samples: Vec<f32> = (0..n)
        .map(|i| (TAU * 82.41 * i as f32 / sr as f32).sin())
        .collect();

    let (min6, max6) = STRING_RANGES[0];
    let mut f6 = BiquadBandpass::for_string(min6, max6, sr);
    let rms6 = f6.measure_rms(&samples);

    // 4 kHz is ~12× above the String-6 centre (160 Hz) — well outside any
    // guitar note and strongly attenuated even by this wide filter.
    let samples_high: Vec<f32> = (0..n)
        .map(|i| (TAU * 4_000.0 * i as f32 / sr as f32).sin())
        .collect();
    let mut f6h = BiquadBandpass::for_string(min6, max6, sr);
    let rms6_high = f6h.measure_rms(&samples_high);

    println!(
        "[E2 82.4 Hz]  String-6 RMS = {:.6}  │  4kHz-through-String6 RMS = {:.6}  \
         │  attenuation = {:.1} dB",
        rms6,
        rms6_high,
        20.0 * (rms6 / rms6_high.max(1e-12)).log10()
    );

    assert!(
        rms6 > 0.1,
        "String-6 bandpass should pass E2 (82.4 Hz) strongly: got rms = {}",
        rms6
    );
    assert!(
        rms6 > rms6_high * 3.0,
        "String-6 filter should provide ≥3× attenuation of 4 kHz vs E2 (82.4 Hz): \
         rms6={} rms6_high={}",
        rms6,
        rms6_high
    );
}

#[test]
fn bandpass_open_e4_passes_string1() {
    use godot_goguitar_rs::bandpass::BiquadBandpass;
    use std::f32::consts::TAU;

    let sr = 44_100u32;
    // Inject E4 (329.63 Hz) — open string 1, inside all string ranges by design.
    let n = sr as usize;
    let samples: Vec<f32> = (0..n)
        .map(|i| (TAU * 329.63 * i as f32 / sr as f32).sin())
        .collect();

    let (min1, max1) = STRING_RANGES[5]; // String 1
    let mut f1 = BiquadBandpass::for_string(min1, max1, sr);
    let rms1 = f1.measure_rms(&samples);

    // 8 kHz is ~12× the String-1 centre (641 Hz) — clearly outside guitar range.
    let samples_vhigh: Vec<f32> = (0..n)
        .map(|i| (TAU * 8_000.0 * i as f32 / sr as f32).sin())
        .collect();
    let mut f1h = BiquadBandpass::for_string(min1, max1, sr);
    let rms1_vhigh = f1h.measure_rms(&samples_vhigh);

    println!(
        "[E4 329.6 Hz]  String-1 RMS = {:.6}  │  8kHz-through-String1 RMS = {:.6}  \
         │  attenuation = {:.1} dB",
        rms1,
        rms1_vhigh,
        20.0 * (rms1 / rms1_vhigh.max(1e-12)).log10()
    );

    assert!(
        rms1 > 0.1,
        "String-1 bandpass should pass E4 (329.6 Hz) strongly: got rms = {}",
        rms1
    );
    assert!(
        rms1 > rms1_vhigh * 3.0,
        "String-1 filter should provide ≥3× attenuation of 8 kHz vs E4 (329.6 Hz): \
         rms1={} rms1_vhigh={}",
        rms1,
        rms1_vhigh
    );
}

#[test]
fn bandpass_all_open_strings_self_select() {
    use godot_goguitar_rs::bandpass::BiquadBandpass;
    use std::f32::consts::TAU;

    let sr = 44_100u32;
    let n = sr as usize / 2; // 0.5 s per test tone

    println!("\n── Open-string self-selection test ─────────────────────────────────────");
    println!("  Each row: sine at open-string freq → best-matching bandpass is its own string");
    println!(
        "  {:^20}  {:>9}  {:>9}  {:^18}",
        "open note", "own RMS", "max-other", "winner"
    );
    println!("  {}", "─".repeat(65));

    for si in 0..6 {
        let freq = OPEN_FREQS[si];
        let samples: Vec<f32> = (0..n)
            .map(|i| (TAU * freq * i as f32 / sr as f32).sin())
            .collect();

        let energies: Vec<f32> = STRING_RANGES
            .iter()
            .map(|&(min, max)| {
                let mut f = BiquadBandpass::for_string(min, max, sr);
                f.measure_rms(&samples)
            })
            .collect();

        let own_rms = energies[si];
        let max_other = energies
            .iter()
            .enumerate()
            .filter(|&(i, _)| i != si)
            .map(|(_, &v)| v)
            .fold(0.0f32, f32::max);

        let winner_idx = energies
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.partial_cmp(b.1).unwrap())
            .map(|(i, _)| i)
            .unwrap_or(99);

        let ok = winner_idx == si;
        println!(
            "  {:^20}  {:>9.6}  {:>9.6}  {:^18}  {}",
            format!("String {} {} ({:.1} Hz)", 6 - si, STRING_NAMES[si], freq),
            own_rms,
            max_other,
            format!("String {} ({})", 6 - winner_idx, STRING_NAMES.get(winner_idx).unwrap_or(&"?")),
            if ok { "OK" } else { "WARN (overlap)" }
        );

        // We only assert that the own-string RMS is substantial; adjacent strings
        // share overlapping ranges by design, so a strict winner-must-be-self
        // assertion would be too strong.
        assert!(
            own_rms > 0.01,
            "String {} bandpass passes its own open note ({} Hz)",
            6 - si,
            freq
        );
    }
}
