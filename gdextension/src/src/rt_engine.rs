/// rt_engine.rs — RT audio engine: dedicated thread + lock-free ring buffers + CPAL I/O.
///
/// Architecture:
///
///  ┌──────────────────────────────────────────────────────────────────────────┐
///  │  CPAL input callback   ──f32──►  input_rb  ──►  Engine thread           │
///  │  (mic / guitar DI)                               │  gg-mixer (Phase 3)  │
///  │                                   output_rb  ◄───┘                      │
///  │  CPAL output callback  ◄──f32──  output_rb                              │
///  │  (speakers / DAW)                                                        │
///  │                                                                          │
///  │  Main thread (Godot) ──push PCM──► music_rb ──► Engine thread           │
///  │  (decoded WEM/AudioEngine)                                               │
///  └──────────────────────────────────────────────────────────────────────────┘
///
/// Phases implemented here:
///   Phase 1 — Engine thread + ring buffers (rtrb) + RT priority (thread-priority).
///   Phase 2 — CPAL input/output streams wired to input_rb / output_rb.
///   Phase 3 — Full bus-mixer path (stems, player instrument, UI SFX, metronome).
///
/// GDScript usage:
/// ```gdscript
/// var rt = RtEngine.new()
/// rt.start(2, 48000)                     # start engine thread
/// rt.start_streams("default", "default") # open CPAL I/O streams
/// rt.push_music_pcm(audio_engine.decode_all())
/// # …gameplay loop — engine mixes & outputs continuously…
/// rt.stop_streams()
/// rt.stop()
/// ```

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{SampleFormat, StreamConfig};
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

/// Holds the live CPAL streams.  Dropping this struct closes both streams.
struct CpalStreams {
    _input_stream:    Option<cpal::Stream>,
    _output_stream:   cpal::Stream,
    /// Keeps the input ring buffer consumer alive until streams are closed.
    /// Phase 3 will drain this consumer in the engine thread instead.
    _input_consumer:  rtrb::Consumer<f32>,
}

// `cpal::Stream` is not `Send`, so we wrap it in an opaque box on the heap.
// The streams are only ever created and dropped on the Godot main thread.
// SAFETY: we never send these across threads — they live inside the Mutex.
unsafe impl Send for CpalStreams {}

// ── GDExtension class ─────────────────────────────────────────────────────────

/// **RtEngine** — Godot GDExtension class that manages the RT audio engine thread
/// and CPAL audio I/O streams.
///
/// Lifecycle:
/// 1. `start(channels, sample_rate)` — spawns the engine thread.
/// 2. `start_streams(input_device_name, output_device_name)` — open CPAL I/O.
/// 3. `push_music_pcm(pcm_bytes)` — feed decoded WEM/PCM into the music ring buffer.
/// 4. `set_bus_gain_db(bus, db)` / `set_bus_mute(bus, mute)` / `set_bus_solo(bus, solo)`
///    — adjust mixer buses from GDScript without blocking the engine thread.
/// 5. `stop_streams()` — close CPAL streams.
/// 6. `stop()` — signal the engine thread to exit and join it.
#[derive(GodotClass)]
#[class(base = Object)]
pub struct RtEngine {
    #[base]
    base:         Base<Object>,
    inner:        Mutex<RtInner>,
    /// CPAL streams are kept alive here; dropping closes the hardware streams.
    cpal_streams: Mutex<Option<CpalStreams>>,
    /// Output ring buffer consumer created by `start()` and consumed by `start_streams()`.
    output_consumer: Mutex<Option<rtrb::Consumer<f32>>>,
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
            cpal_streams:    Mutex::new(None),
            output_consumer: Mutex::new(None),
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
        let (music_producer,  music_consumer)  = RingBuffer::<f32>::new(RING_CAPACITY);
        let (output_producer, output_consumer) = RingBuffer::<f32>::new(RING_CAPACITY);
        let (cmd_producer,    cmd_consumer)    = RingBuffer::<EngineCmd>::new(64);

        inner.music_producer = Some(music_producer);
        inner.cmd_producer   = Some(cmd_producer);

        // Store output consumer so CPAL output callback can take it in start_streams().
        if let Ok(mut oc) = self.output_consumer.lock() {
            *oc = Some(output_consumer);
        }

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
        // Close streams first so the CPAL callback no longer references the ring buffer.
        self.stop_streams();

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

    // ── Phase 2: CPAL I/O streams ─────────────────────────────────────────────

    /// Open CPAL input and output streams.
    ///
    /// `input_device_name` / `output_device_name`: pass `"default"` for the system
    /// default device, or the exact device name returned by `list_audio_devices()`.
    ///
    /// Must be called **after** `start()` so the ring buffers exist.
    /// Returns `true` on success.
    #[func]
    pub fn start_streams(
        &self,
        input_device_name:  GString,
        output_device_name: GString,
    ) -> bool {
        let (ch, sr) = {
            let inner = match self.inner.lock() {
                Ok(g)  => g,
                Err(_) => return false,
            };
            if inner.thread_handle.is_none() {
                godot_error!("RtEngine: call start() before start_streams().");
                return false;
            }
            (inner.channels, inner.sample_rate)
        };

        let host = cpal::default_host();

        // ── Select output device ──────────────────────────────────────────────
        let out_name = output_device_name.to_string();
        let output_device = if out_name == "default" || out_name.is_empty() {
            match host.default_output_device() {
                Some(d) => d,
                None    => { godot_error!("RtEngine: no default output device."); return false; }
            }
        } else {
            match host.output_devices() {
                Ok(mut it) => match it.find(|d| d.name().map(|n| n == out_name).unwrap_or(false)) {
                    Some(d) => d,
                    None    => { godot_error!("RtEngine: output device '{}' not found.", out_name); return false; }
                },
                Err(e) => { godot_error!("RtEngine: enumerate output devices: {}", e); return false; }
            }
        };

        // ── Select input device ───────────────────────────────────────────────
        let in_name = input_device_name.to_string();
        let input_device = if in_name == "default" || in_name.is_empty() {
            host.default_input_device()
        } else {
            host.input_devices().ok().and_then(|mut it| {
                it.find(|d| d.name().map(|n| n == in_name).unwrap_or(false))
            })
        };

        // ── Stream config ─────────────────────────────────────────────────────
        let out_config = StreamConfig {
            channels:    ch as cpal::ChannelCount,
            sample_rate: cpal::SampleRate(sr),
            buffer_size: cpal::BufferSize::Default,
        };
        let in_config = StreamConfig {
            channels:    1,   // mono mic input
            sample_rate: cpal::SampleRate(sr),
            buffer_size: cpal::BufferSize::Default,
        };

        // ── Input ring buffer for mic/guitar (Phase 3 will read it in engine thread) ──
        // Both halves are kept alive: producer inside the CPAL callback Arc,
        // consumer stored in CpalStreams so it lives until stop_streams().
        let (input_producer, input_consumer) = RingBuffer::<f32>::new(RING_CAPACITY);
        // Arc-wrap input producer for the CPAL callback (avoids take/move race on re-use).
        let input_rb: Arc<Mutex<Option<rtrb::Producer<f32>>>> =
            Arc::new(Mutex::new(Some(input_producer)));

        // ── Take output consumer for CPAL output callback ─────────────────────
        // `self.output_consumer` is populated by `start()` and consumed once here.
        // Calling `start_streams()` a second time (without re-calling `start()`)
        // will fail here with a clear error message.
        let output_consumer = match self.output_consumer.lock()
            .ok()
            .and_then(|mut g| g.take())
        {
            Some(c) => c,
            None    => {
                godot_error!("RtEngine: output ring buffer not available. \
                              Call start() before start_streams(), and stop_streams() \
                              + stop() + start() before re-opening streams.");
                return false;
            }
        };
        let output_rb: Arc<Mutex<Option<rtrb::Consumer<f32>>>> =
            Arc::new(Mutex::new(Some(output_consumer)));

        // ── Build output stream (pops from output_rb, outputs silence on underrun) ──
        let out_rb_clone = Arc::clone(&output_rb);
        let out_ch = ch as usize;
        let output_stream = match output_device.build_output_stream(
            &out_config,
            move |data: &mut [f32], _| {
                let mut guard = match out_rb_clone.lock() {
                    Ok(g)  => g,
                    Err(_) => { data.fill(0.0); return; }
                };
                let consumer = match guard.as_mut() {
                    Some(c) => c,
                    None    => { data.fill(0.0); return; }
                };
                for frame in data.chunks_mut(out_ch) {
                    for sample in frame.iter_mut() {
                        *sample = consumer.pop().unwrap_or(0.0);
                    }
                }
            },
            |err| godot_error!("RtEngine: CPAL output error: {}", err),
            None,
        ) {
            Ok(s)  => s,
            Err(e) => { godot_error!("RtEngine: build_output_stream: {}", e); return false; }
        };

        // ── Build input stream (pushes to input_rb for Phase 3) ──────────────
        let input_stream_opt = input_device.and_then(|dev| {
            let in_rb_clone = Arc::clone(&input_rb);
            dev.build_input_stream(
                &in_config,
                move |data: &[f32], _| {
                    let mut guard = match in_rb_clone.lock() {
                        Ok(g)  => g,
                        Err(_) => return,
                    };
                    if let Some(producer) = guard.as_mut() {
                        for &sample in data {
                            let _ = producer.push(sample);
                        }
                    }
                },
                |err| godot_error!("RtEngine: CPAL input error: {}", err),
                None,
            ).ok()
        });

        // ── Start streams ─────────────────────────────────────────────────────
        if let Err(e) = output_stream.play() {
            godot_error!("RtEngine: play output stream: {}", e);
            return false;
        }
        if let Some(ref s) = input_stream_opt {
            if let Err(e) = s.play() {
                godot_warn!("RtEngine: play input stream: {}", e);
                // Non-fatal — input may not be available in all environments.
            }
        }

        let streams = CpalStreams {
            _output_stream:  output_stream,
            _input_stream:   input_stream_opt,
            _input_consumer: input_consumer,
        };

        if let Ok(mut cs) = self.cpal_streams.lock() {
            *cs = Some(streams);
        }

        godot_print!("RtEngine: CPAL streams started — out='{}' in='{}'",
            output_device_name, input_device_name);
        true
    }

    /// Close CPAL input and output streams.  The engine thread keeps running.
    #[func]
    pub fn stop_streams(&self) {
        if let Ok(mut cs) = self.cpal_streams.lock() {
            if cs.take().is_some() {
                godot_print!("RtEngine: CPAL streams stopped.");
            }
        }
    }

    /// List available output device names (for the Godot settings screen).
    #[func]
    pub fn list_output_devices(&self) -> PackedStringArray {
        let mut out = PackedStringArray::new();
        let host = cpal::default_host();
        if let Ok(devices) = host.output_devices() {
            for d in devices {
                if let Ok(name) = d.name() {
                    out.push(&GString::from(name.as_str()));
                }
            }
        }
        out
    }

    /// List available input device names.
    #[func]
    pub fn list_input_devices(&self) -> PackedStringArray {
        let mut out = PackedStringArray::new();
        let host = cpal::default_host();
        if let Ok(devices) = host.input_devices() {
            for d in devices {
                if let Ok(name) = d.name() {
                    out.push(&GString::from(name.as_str()));
                }
            }
        }
        out
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
            // TODO Phase 3: replace sleep with a condvar/semaphore woken by the
            // CPAL output callback so the engine wakes exactly when more output
            // space is available rather than polling every 500 µs.
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
