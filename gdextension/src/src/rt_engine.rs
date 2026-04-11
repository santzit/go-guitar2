/// rt_engine.rs — Phase 1: Dedicated RT audio engine thread + lock-free ring buffers.
///
/// Architecture (three-layer, implemented incrementally):
///
///  ┌─────────────────────────────────────────────────────────────────────────┐
///  │ Phase 1 (this file)                                                     │
///  │   Main thread  ──push PCM──►  music_rb ──►  Engine thread              │
///  │                                               │  gg-mixer               │
///  │                             output_rb  ◄──────┘                        │
///  │                             (consumed by CPAL output callback, Phase 2) │
///  │                                                                         │
///  │ Phase 2 (TODO)  Add cpal streams: input_rb ← mic, output_rb → speakers  │
///  │ Phase 3 (TODO)  Full bus-mixer path: stems, UI SFX, metronome buses      │
///  └─────────────────────────────────────────────────────────────────────────┘
///
/// GDScript usage (Phase 1):
/// ```gdscript
/// var rt = RtEngine.new()
/// rt.start(2, 48000)          # 2 channels, 48 kHz
/// rt.push_music_pcm(pcm_bytes) # feed decoded WEM PCM into the ring buffer
/// # …later…
/// rt.stop()
/// ```

use godot::prelude::*;
use gg_mixer::{BusId, MixInput, Mixer};
use rtrb::RingBuffer;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

// ── Constants ──────────────────────────────────────────────────────────────────

/// Samples per processing block (per channel).
/// 128 samples @ 48 kHz ≈ 2.67 ms latency — a good starting point.
const BLOCK_SIZE: usize = 128;

/// Ring buffer capacity in f32 samples (covers ~170 ms of stereo 48 kHz audio).
const RING_CAPACITY: usize = 48_000 * 2;  // 2 channels × 48 000 samples/s × ~0.5 s

// ── Commands sent from main thread → engine thread (RT-safe SPSC) ─────────────

#[derive(Clone, Debug)]
enum EngineCmd {
    /// Set gain in dB for a given bus index (matches BusId ordering).
    SetGainDb { bus: usize, db: f32 },
    SetMute    { bus: usize, mute: bool },
    SetSolo    { bus: usize, solo: bool },
    SetStemDuckingDb { db: f32 },
}

// ── Main-thread inner state (behind Mutex) ─────────────────────────────────────

struct RtInner {
    /// Push music PCM frames (f32, interleaved) from the main thread.
    music_producer:   Option<rtrb::Producer<f32>>,
    /// Send mixer-parameter commands without blocking the engine thread.
    cmd_producer:     Option<rtrb::Producer<EngineCmd>>,
    /// Thread handle — joined on stop().
    thread_handle:    Option<std::thread::JoinHandle<()>>,
    /// Set to false to signal the engine thread to exit cleanly.
    running:          Arc<AtomicBool>,
    channels:         u32,
    sample_rate:      u32,
}

// ── GDExtension class ─────────────────────────────────────────────────────────

/// **RtEngine** — Godot GDExtension class that manages the RT audio engine thread.
///
/// Lifecycle:
/// 1. `start(channels, sample_rate)` — spawns the engine thread.
/// 2. `push_music_pcm(pcm_bytes)` — feed decoded WEM/PCM into the music ring buffer.
/// 3. `set_bus_gain_db(bus, db)` / `set_bus_mute(bus, mute)` / `set_bus_solo(bus, solo)`
///    — adjust mixer buses from GDScript without blocking the engine thread.
/// 4. `stop()` — signal the thread to exit and join it.
#[derive(GodotClass)]
#[class(base = Object)]
pub struct RtEngine {
    #[base]
    base:  Base<Object>,
    inner: Mutex<RtInner>,
}

#[godot_api]
impl IObject for RtEngine {
    fn init(base: Base<Object>) -> Self {
        Self {
            base,
            inner: Mutex::new(RtInner {
                music_producer: None,
                cmd_producer:   None,
                thread_handle:  None,
                running:        Arc::new(AtomicBool::new(false)),
                channels:       2,
                sample_rate:    48_000,
            }),
        }
    }
}

#[godot_api]
impl RtEngine {
    /// Spawn the engine thread and allocate ring buffers.
    /// Returns `true` on success; calling `start()` when already running is a no-op.
    #[func]
    pub fn start(&self, channels: i32, sample_rate: i32) -> bool {
        let mut inner = match self.inner.lock() {
            Ok(g)  => g,
            Err(_) => return false,
        };

        if inner.thread_handle.is_some() {
            godot_warn!("RtEngine: already running — call stop() first.");
            return false;
        }

        let ch = channels.max(1) as u32;
        let sr = sample_rate.max(8_000) as u32;
        inner.channels    = ch;
        inner.sample_rate = sr;

        // ── Ring buffers ──────────────────────────────────────────────────────
        let (music_producer,   music_consumer)   = RingBuffer::<f32>::new(RING_CAPACITY);
        let (output_producer,  _output_consumer) = RingBuffer::<f32>::new(RING_CAPACITY);
        let (cmd_producer,     cmd_consumer)     = RingBuffer::<EngineCmd>::new(64);

        inner.music_producer = Some(music_producer);
        inner.cmd_producer   = Some(cmd_producer);

        // ── Engine thread ─────────────────────────────────────────────────────
        let running = Arc::clone(&inner.running);
        running.store(true, Ordering::SeqCst);

        let handle = std::thread::Builder::new()
            .name("rt-audio-engine".into())
            .spawn(move || {
                engine_thread(
                    ch, sr,
                    music_consumer,
                    output_producer,
                    cmd_consumer,
                    running,
                )
            })
            .expect("RtEngine: failed to spawn engine thread");

        inner.thread_handle = Some(handle);
        godot_print!("RtEngine: started — {} ch  {} Hz  block={} smp", ch, sr, BLOCK_SIZE);
        true
    }

    /// Signal the engine thread to exit and block until it has finished.
    #[func]
    pub fn stop(&self) {
        let mut inner = match self.inner.lock() {
            Ok(g)  => g,
            Err(_) => return,
        };

        inner.running.store(false, Ordering::SeqCst);
        inner.music_producer = None;
        inner.cmd_producer   = None;

        if let Some(handle) = inner.thread_handle.take() {
            let _ = handle.join();
        }
        godot_print!("RtEngine: stopped.");
    }

    /// Push interleaved PCM-16-LE bytes (from `AudioEngine.decode_all()`) into the
    /// music ring buffer so the engine thread can mix them.
    ///
    /// Returns the number of f32 samples actually written (may be less than requested
    /// if the ring buffer is full — the caller can back off and retry).
    #[func]
    pub fn push_music_pcm(&self, data: PackedByteArray) -> i64 {
        let mut inner = match self.inner.lock() {
            Ok(g)  => g,
            Err(_) => return 0,
        };

        let producer = match inner.music_producer.as_mut() {
            Some(p) => p,
            None    => {
                godot_warn!("RtEngine: push_music_pcm() called before start().");
                return 0;
            }
        };

        let raw: Vec<u8> = data.to_vec();
        let samples: Vec<f32> = raw
            .chunks_exact(2)
            .map(|b| i16::from_le_bytes([b[0], b[1]]) as f32 / 32768.0)
            .collect();

        let mut written = 0i64;
        for s in &samples {
            match producer.push(*s) {
                Ok(()) => written += 1,
                Err(_) => break,  // ring buffer full
            }
        }
        written
    }

    /// Set gain in dB for a mixer bus (uses `BusId` index: 0=Ui, 1=Music, …, 6=Master, …).
    /// See `BusId` enum in gg-mixer for full list.
    #[func]
    pub fn set_bus_gain_db(&self, bus: i32, gain_db: f32) {
        self.send_cmd(EngineCmd::SetGainDb { bus: bus as usize, db: gain_db });
    }

    /// Mute or unmute a mixer bus.
    #[func]
    pub fn set_bus_mute(&self, bus: i32, mute: bool) {
        self.send_cmd(EngineCmd::SetMute { bus: bus as usize, mute });
    }

    /// Solo a mixer bus (all non-soloed buses are silenced while any solo is active).
    #[func]
    pub fn set_bus_solo(&self, bus: i32, solo: bool) {
        self.send_cmd(EngineCmd::SetSolo { bus: bus as usize, solo });
    }

    /// Adjust how much stems are ducked (in dB) when the player's instrument is active.
    #[func]
    pub fn set_stem_ducking_db(&self, db: f32) {
        self.send_cmd(EngineCmd::SetStemDuckingDb { db });
    }

    /// Returns `true` if the engine thread is currently running.
    #[func]
    pub fn is_running(&self) -> bool {
        self.inner.lock()
            .map(|g| g.thread_handle.is_some())
            .unwrap_or(false)
    }

    /// How many free slots remain in the music ring buffer (in f32 samples).
    #[func]
    pub fn music_rb_free_slots(&self) -> i64 {
        self.inner.lock()
            .ok()
            .and_then(|g| g.music_producer.as_ref().map(|p| p.slots() as i64))
            .unwrap_or(0)
    }
}

// ── Private helpers ───────────────────────────────────────────────────────────

impl RtEngine {
    fn send_cmd(&self, cmd: EngineCmd) {
        if let Ok(mut inner) = self.inner.lock() {
            if let Some(p) = inner.cmd_producer.as_mut() {
                let _ = p.push(cmd);
            }
        }
    }
}

// ── Engine thread function ────────────────────────────────────────────────────

/// Runs on the dedicated audio engine thread with (attempted) real-time priority.
fn engine_thread(
    channels:        u32,
    _sample_rate:    u32,
    mut music_in:    rtrb::Consumer<f32>,
    mut output_out:  rtrb::Producer<f32>,
    mut cmd_in:      rtrb::Consumer<EngineCmd>,
    running:         Arc<AtomicBool>,
) {
    // Request real-time / time-critical priority where the OS allows it.
    // Failure is silently ignored — the thread still functions, just at normal priority.
    use thread_priority::{set_current_thread_priority, ThreadPriority};
    if set_current_thread_priority(ThreadPriority::Max).is_ok() {
        // Note: on Linux this requires `CAP_SYS_NICE` or an appropriate rlimit.
        // On Windows it maps to THREAD_PRIORITY_TIME_CRITICAL.
    }

    let ch = channels as usize;
    let block_samples = BLOCK_SIZE * ch;  // total f32 samples per block

    let mut mixer = Mixer::new();

    loop {
        if !running.load(Ordering::Relaxed) {
            break;
        }

        // ── Drain command ring buffer (non-RT: param updates only) ────────────
        while let Ok(cmd) = cmd_in.pop() {
            match cmd {
                EngineCmd::SetGainDb { bus, db } => {
                    if let Some(bus_id) = bus_id_from_usize(bus) {
                        mixer.set_gain_db(bus_id, db);
                    }
                }
                EngineCmd::SetMute { bus, mute } => {
                    if let Some(bus_id) = bus_id_from_usize(bus) {
                        mixer.set_mute(bus_id, mute);
                    }
                }
                EngineCmd::SetSolo { bus, solo } => {
                    if let Some(bus_id) = bus_id_from_usize(bus) {
                        mixer.set_solo(bus_id, solo);
                    }
                }
                EngineCmd::SetStemDuckingDb { db } => {
                    mixer.set_stem_ducking_db(db);
                }
            }
        }

        // ── Process one block ─────────────────────────────────────────────────
        if music_in.slots() >= block_samples {
            for _ in 0..BLOCK_SIZE {
                // Read one interleaved frame and downmix to mono for the mixer input.
                let mut sum = 0.0f32;
                for _ in 0..ch {
                    sum += music_in.pop().unwrap_or(0.0);
                }
                let mono = sum / ch as f32;

                let mixed = mixer.mix_sample(MixInput {
                    music: mono,
                    ..Default::default()
                });

                // Write one output frame (re-interleave to the original channel count).
                for _ in 0..ch {
                    let _ = output_out.push(mixed);
                }
            }
        } else {
            // Underrun: output silence and yield to avoid spinning the CPU.
            // Phase 2 will replace this sleep with a condvar/semaphore woken by CPAL.
            for _ in 0..(block_samples) {
                let _ = output_out.push(0.0f32);
            }
            std::thread::sleep(Duration::from_micros(500));
        }
    }
}

/// Map a usize index to a `BusId`.  Returns `None` for out-of-range values.
fn bus_id_from_usize(idx: usize) -> Option<BusId> {
    use BusId::*;
    match idx {
        0 => Some(Ui),
        1 => Some(Music),
        2 => Some(LeadGuitarStem),
        3 => Some(RhythmGuitarStem),
        4 => Some(BassStem),
        5 => Some(PlayerInstrument),
        6 => Some(Master),
        7 => Some(Metronome),
        8 => Some(MicRoom),
        _ => None,
    }
}
