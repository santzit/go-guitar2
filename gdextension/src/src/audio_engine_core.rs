/// audio-engine — RT audio engine thread, transport clock, and command queue.
///
/// Architecture:
/// ```text
/// Main thread             Engine thread (RT priority)
///   push_music_pcm ──►  music_consumer  ──►  Mixer ──► output_producer ──► CPAL output
///   send_cmd       ──►  cmd_consumer    ──►  param updates
///                        input_consumer ◄──  CPAL input (mic / guitar DI)
/// ```
///
/// ## Lifecycle
/// ```rust
/// let engine = EngineCore::start(2, 48_000);
/// // … hand engine.output_consumer and engine.input_producer to audio-io …
/// engine.stop();
/// ```

use crate::audio_mixer::{bus_id_from_index, BUS_COUNT, MixInput, Mixer};
use rtrb::RingBuffer;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

// ── Constants ─────────────────────────────────────────────────────────────────

/// Samples per processing block (per channel).  128 @ 48 kHz ≈ 2.67 ms.
pub const BLOCK_SIZE: usize = 128;

/// Ring buffer capacity in f32 samples (~0.5 s of stereo 48 kHz).
pub const RING_CAPACITY: usize = 48_000 * 2;

/// Ring buffer capacity for the command queue.
pub const CMD_CAPACITY: usize = 64;

// ── Commands ──────────────────────────────────────────────────────────────────

/// Commands sent from the main thread to the engine thread via a lock-free SPSC queue.
#[derive(Clone, Debug)]
pub enum EngineCmd {
    /// Set gain in dB for a mixer bus (index matches `BusId` ordering).
    SetGainDb { bus: usize, db: f32 },
    /// Mute or unmute a mixer bus.
    SetMute { bus: usize, mute: bool },
    /// Solo a mixer bus.
    SetSolo { bus: usize, solo: bool },
    /// Adjust stem-ducking amount in dB.
    SetStemDuckingDb { db: f32 },
}

// ── EngineCore ────────────────────────────────────────────────────────────────

/// Owns the engine thread and all ring-buffer handles shared with it.
///
/// The caller is expected to transfer `output_consumer` and `input_producer`
/// to the audio-io layer immediately after `start()`.
pub struct EngineCore {
    /// Push interleaved f32 music samples into this producer.
    pub music_producer:  rtrb::Producer<f32>,
    /// Send mixer-parameter commands here (non-blocking, RT-safe).
    pub cmd_producer:    rtrb::Producer<EngineCmd>,
    /// Engine-thread output — hand this to the CPAL output callback.
    pub output_consumer: Option<rtrb::Consumer<f32>>,
    /// Engine-thread mic/DI input — hand this to the CPAL input callback.
    pub input_producer:  Option<rtrb::Producer<f32>>,
    /// Shared peak-meter values per bus, written by the engine thread each block.
    pub meter_peaks:     Arc<Mutex<Vec<f32>>>,
    /// Mirror of per-bus gain_db set from the main thread (for readback).
    pub gain_db:         [f32; BUS_COUNT],
    /// Set to `false` to signal the engine thread to exit.
    running:             Arc<AtomicBool>,
    handle:              Option<std::thread::JoinHandle<()>>,
    /// Cached config for informational purposes.
    pub channels:        u32,
    pub sample_rate:     u32,
}

impl EngineCore {
    /// Spawn the engine thread and allocate all ring buffers.
    pub fn start(channels: u32, sample_rate: u32) -> Self {
        let ch = channels.max(1);
        let sr = sample_rate.max(8_000);

        let (music_producer,  music_consumer)  = RingBuffer::<f32>::new(RING_CAPACITY);
        let (output_producer, output_consumer) = RingBuffer::<f32>::new(RING_CAPACITY);
        let (cmd_producer,    cmd_consumer)    = RingBuffer::<EngineCmd>::new(CMD_CAPACITY);
        let (input_producer,  input_consumer)  = RingBuffer::<f32>::new(RING_CAPACITY);

        let running      = Arc::new(AtomicBool::new(true));
        let meter_peaks  = Arc::new(Mutex::new(vec![0.0f32; BUS_COUNT]));

        let running_clone      = Arc::clone(&running);
        let meter_peaks_clone  = Arc::clone(&meter_peaks);

        let handle = std::thread::Builder::new()
            .name("rt-audio-engine".into())
            .spawn(move || {
                engine_thread(
                    ch, sr,
                    music_consumer,
                    input_consumer,
                    output_producer,
                    cmd_consumer,
                    running_clone,
                    meter_peaks_clone,
                );
            })
            .expect("audio-engine: failed to spawn engine thread");

        Self {
            music_producer,
            cmd_producer,
            output_consumer: Some(output_consumer),
            input_producer:  Some(input_producer),
            meter_peaks,
            gain_db:         [0.0; BUS_COUNT],
            running,
            handle:          Some(handle),
            channels:        ch,
            sample_rate:     sr,
        }
    }

    /// Signal the engine thread to stop and block until it has exited.
    pub fn stop(&mut self) {
        self.running.store(false, Ordering::SeqCst);
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
    }

    /// Returns `true` if the engine thread is alive.
    pub fn is_running(&self) -> bool {
        self.handle.is_some()
    }
}

impl Drop for EngineCore {
    fn drop(&mut self) {
        self.stop();
    }
}

// ── Engine thread ─────────────────────────────────────────────────────────────

fn engine_thread(
    channels:       u32,
    _sample_rate:   u32,
    mut music_in:   rtrb::Consumer<f32>,
    mut input_in:   rtrb::Consumer<f32>,
    mut output_out: rtrb::Producer<f32>,
    mut cmd_in:     rtrb::Consumer<EngineCmd>,
    running:        Arc<AtomicBool>,
    meter_peaks:    Arc<Mutex<Vec<f32>>>,
) {
    use thread_priority::{set_current_thread_priority, ThreadPriority};
    // Failure is silently ignored — the thread still works at normal priority.
    let _ = set_current_thread_priority(ThreadPriority::Max);

    let ch           = channels as usize;
    let block_samples = BLOCK_SIZE * ch;
    let mut mixer    = Mixer::new();

    loop {
        if !running.load(Ordering::Relaxed) {
            break;
        }

        // ── Drain command queue ───────────────────────────────────────────────
        while let Ok(cmd) = cmd_in.pop() {
            match cmd {
                EngineCmd::SetGainDb { bus, db } => {
                    if let Some(id) = bus_id_from_index(bus) {
                        mixer.set_gain_db(id, db);
                    }
                }
                EngineCmd::SetMute { bus, mute } => {
                    if let Some(id) = bus_id_from_index(bus) {
                        mixer.set_mute(id, mute);
                    }
                }
                EngineCmd::SetSolo { bus, solo } => {
                    if let Some(id) = bus_id_from_index(bus) {
                        mixer.set_solo(id, solo);
                    }
                }
                EngineCmd::SetStemDuckingDb { db } => {
                    mixer.set_stem_ducking_db(db);
                }
            }
        }

        // ── Process one block if output ring has space ────────────────────────
        if output_out.slots() >= block_samples {
            for _ in 0..BLOCK_SIZE {
                // Downmix all music channels to mono.
                let mut music_sum = 0.0f32;
                for _ in 0..ch {
                    music_sum += music_in.pop().unwrap_or(0.0);
                }
                let music_mono = music_sum / ch as f32;

                // Mono mic / guitar DI.
                let player = input_in.pop().unwrap_or(0.0);

                let mixed = mixer.mix_sample(MixInput {
                    music:             music_mono,
                    player_instrument: player,
                    ..Default::default()
                });

                // Re-interleave the mixed signal to all output channels.
                for _ in 0..ch {
                    let _ = output_out.push(mixed);
                }
            }

            // ── Update shared peak meters ─────────────────────────────────────
            use crate::audio_mixer::BusId;
            if let Ok(mut peaks) = meter_peaks.lock() {
                for bus in BusId::ALL {
                    if let Some(p) = peaks.get_mut(bus as usize) {
                        *p = mixer.meter(bus).peak;
                    }
                }
            }
        } else {
            // Output ring full — yield briefly.
            std::thread::sleep(Duration::from_micros(500));
        }
    }
}
