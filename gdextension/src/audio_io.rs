/// audio-io — Cross-platform audio I/O via CPAL.
///
/// Provides:
/// - Device enumeration (`list_input_devices`, `list_output_devices`).
/// - Stream creation (`open_streams`) — wires ring-buffer halves to CPAL callbacks.
///
/// The caller (usually the Godot `RtEngine` wrapper) is responsible for creating
/// the `rtrb` ring buffers and passing the appropriate half to `open_streams`.
///
/// ## Ring-buffer protocol
/// ```text
/// CPAL input  callback ──push f32──► input_producer  (given by caller)
/// CPAL output callback ◄──pop f32──  output_consumer (given by caller)
/// ```

use std::sync::{Arc, Mutex};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::StreamConfig;

/// Configuration for the CPAL streams.
pub struct AudioIoConfig {
    /// Number of output channels (usually 2 for stereo).
    pub channels:    u32,
    /// Sample rate in Hz (usually 48 000).
    pub sample_rate: u32,
}

/// Live CPAL streams.  Dropping this struct closes both hardware streams.
pub struct AudioIoStreams {
    _input_stream:  Option<cpal::Stream>,
    _output_stream: cpal::Stream,
}

// `cpal::Stream` is not `Send`, but streams are only created/dropped on one
// thread (the Godot main thread), so this is safe.
unsafe impl Send for AudioIoStreams {}

/// Return all available output device names.
pub fn list_output_devices() -> Vec<String> {
    let host = cpal::default_host();
    host.output_devices()
        .map(|it| {
            it.filter_map(|d| d.name().ok()).collect()
        })
        .unwrap_or_default()
}

/// Return all available input device names.
pub fn list_input_devices() -> Vec<String> {
    let host = cpal::default_host();
    host.input_devices()
        .map(|it| {
            it.filter_map(|d| d.name().ok()).collect()
        })
        .unwrap_or_default()
}

/// Open CPAL input and output streams, wiring them to the provided ring-buffer halves.
///
/// # Arguments
/// - `cfg`              — channels + sample rate for both streams.
/// - `input_name`       — device name, or `"default"` / `""` for the system default.
/// - `output_name`      — device name, or `"default"` / `""` for the system default.
/// - `input_producer`   — write end of the input ring buffer (CPAL pushes mic samples here).
/// - `output_consumer`  — read end of the output ring buffer (CPAL pops mixed samples here).
///
/// # Errors
/// Returns an error string if a required device or stream could not be opened.
pub fn open_streams(
    cfg:             &AudioIoConfig,
    input_name:      &str,
    output_name:     &str,
    input_producer:  Arc<Mutex<Option<rtrb::Producer<f32>>>>,
    output_consumer: Arc<Mutex<Option<rtrb::Consumer<f32>>>>,
) -> Result<AudioIoStreams, String> {
    let host = cpal::default_host();
    let ch   = cfg.channels;
    let sr   = cfg.sample_rate;

    // ── Select output device ─────────────────────────────────────────────────
    let output_device = if output_name == "default" || output_name.is_empty() {
        host.default_output_device()
            .ok_or_else(|| "no default output device".to_owned())?
    } else {
        host.output_devices()
            .map_err(|e| format!("enumerate output devices: {e}"))?
            .find(|d| d.name().map(|n| n == output_name).unwrap_or(false))
            .ok_or_else(|| format!("output device '{output_name}' not found"))?
    };

    // ── Select input device (optional) ──────────────────────────────────────
    let input_device = if input_name == "default" || input_name.is_empty() {
        host.default_input_device()
    } else {
        host.input_devices().ok().and_then(|mut it| {
            it.find(|d| d.name().map(|n| n == input_name).unwrap_or(false))
        })
    };

    // ── Stream configs ───────────────────────────────────────────────────────
    let out_config = StreamConfig {
        channels:    ch as cpal::ChannelCount,
        sample_rate: cpal::SampleRate(sr),
        buffer_size: cpal::BufferSize::Default,
    };
    let in_config = StreamConfig {
        channels:    1,   // mono mic / guitar DI
        sample_rate: cpal::SampleRate(sr),
        buffer_size: cpal::BufferSize::Default,
    };

    // ── Build output stream ──────────────────────────────────────────────────
    let out_ch = ch as usize;
    let out_rb = Arc::clone(&output_consumer);
    let output_stream = output_device
        .build_output_stream(
            &out_config,
            move |data: &mut [f32], _| {
                let mut guard = match out_rb.lock() {
                    Ok(g)  => g,
                    Err(_) => { data.fill(0.0); return; }
                };
                let consumer = match guard.as_mut() {
                    Some(c) => c,
                    None    => { data.fill(0.0); return; }
                };
                for frame in data.chunks_mut(out_ch) {
                    for s in frame.iter_mut() {
                        *s = consumer.pop().unwrap_or(0.0);
                    }
                }
            },
            |err| eprintln!("audio-io: CPAL output error: {err}"),
            None,
        )
        .map_err(|e| format!("build_output_stream: {e}"))?;

    // ── Build input stream (optional) ────────────────────────────────────────
    let input_stream_opt = input_device.and_then(|dev| {
        let in_rb = Arc::clone(&input_producer);
        dev.build_input_stream(
            &in_config,
            move |data: &[f32], _| {
                if let Ok(mut guard) = in_rb.lock() {
                    if let Some(producer) = guard.as_mut() {
                        for &s in data {
                            let _ = producer.push(s);
                        }
                    }
                }
            },
            |err| eprintln!("audio-io: CPAL input error: {err}"),
            None,
        ).ok()
    });

    // ── Start streams ────────────────────────────────────────────────────────
    output_stream
        .play()
        .map_err(|e| format!("play output stream: {e}"))?;

    if let Some(ref s) = input_stream_opt {
        // Non-fatal — input may not be available in headless / CI environments.
        if let Err(e) = s.play() {
            eprintln!("audio-io: play input stream (non-fatal): {e}");
        }
    }

    Ok(AudioIoStreams {
        _output_stream: output_stream,
        _input_stream:  input_stream_opt,
    })
}
