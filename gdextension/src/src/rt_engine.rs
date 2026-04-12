/// rt_engine.rs — Godot GDExtension wrapper for the RT audio engine.
///
/// This thin wrapper exposes `RtEngine` as a Godot class.  All engine logic
/// (thread, ring buffers, command queue) lives in the `audio-engine` crate.
/// All CPAL I/O (device enumeration, stream creation) lives in the `audio-io` crate.
///
/// ```text
/// GDScript ──► RtEngine (Godot class, this file)
///                ├─► audio_engine::EngineCore (RT thread, ring buffers, mixer)
///                └─► audio_io::open_streams   (CPAL input/output streams)
/// ```
///
/// GDScript usage:
/// ```gdscript
/// var rt = RtEngine.new()
/// rt.start(2, 48000)                     # start engine thread + allocate ring buffers
/// rt.start_streams("default", "default") # open CPAL I/O streams
/// rt.push_music_pcm(audio_engine.decode_all())
/// # …gameplay loop…
/// rt.stop_streams()
/// rt.stop()
/// ```

use crate::audio_engine_core::{EngineCmd, EngineCore};
use crate::audio_io::{open_streams, AudioIoConfig};
use crate::audio_mixer::BUS_COUNT;
use godot::prelude::*;
use rtrb::RingBuffer;
use std::sync::{Arc, Mutex};

// ── GDExtension class ─────────────────────────────────────────────────────────

/// **RtEngine** — Godot GDExtension class managing the RT audio engine thread
/// and CPAL audio I/O streams.
///
/// Lifecycle:
/// 1. `start(channels, sample_rate)` — spawns the engine thread.
/// 2. `start_streams(input_name, output_name)` — open CPAL I/O.
/// 3. `push_music_pcm(pcm_bytes)` — feed decoded WEM/PCM into the music ring buffer.
/// 4. `set_bus_*` — adjust mixer buses from GDScript.
/// 5. `stop_streams()` — close CPAL streams.
/// 6. `stop()` — shut down the engine thread.
#[derive(GodotClass)]
#[class(base = Object)]
pub struct RtEngine {
    #[base]
    base:         Base<Object>,
    /// The core engine (engine thread + ring buffers).
    core:         Mutex<Option<EngineCore>>,
    /// Live CPAL streams; dropping closes the hardware.
    io_streams:   Mutex<Option<crate::audio_io::AudioIoStreams>>,
    /// Shared peak-meter values (readable from GDScript).
    meter_peaks:  Arc<Mutex<Vec<f32>>>,
    /// Mirror of per-bus gain_db set from GDScript (for readback without RT round-trip).
    gain_db_mirror: Mutex<[f32; BUS_COUNT]>,
}

#[godot_api]
impl IObject for RtEngine {
    fn init(base: Base<Object>) -> Self {
        Self {
            base,
            core:            Mutex::new(None),
            io_streams:      Mutex::new(None),
            meter_peaks:     Arc::new(Mutex::new(vec![0.0f32; BUS_COUNT])),
            gain_db_mirror:  Mutex::new([0.0; BUS_COUNT]),
        }
    }
}

#[godot_api]
impl RtEngine {
    /// Spawn the engine thread and allocate ring buffers.
    /// Returns `true` on success; calling `start()` when already running is a no-op.
    #[func]
    pub fn start(&self, channels: i32, sample_rate: i32) -> bool {
        let mut core_guard = match self.core.lock() {
            Ok(g)  => g,
            Err(_) => return false,
        };

        if core_guard.is_some() {
            godot_warn!("RtEngine: already running — call stop() first.");
            return false;
        }

        let ch = channels.max(1) as u32;
        let sr = sample_rate.max(8_000) as u32;

        let engine = EngineCore::start(ch, sr);

        // Mirror the shared meter-peaks Arc so GDScript can read it.
        if let Ok(mut mp) = self.meter_peaks.lock() {
            *mp = vec![0.0f32; BUS_COUNT];
        }

        godot_print!("RtEngine: started — {} ch  {} Hz", ch, sr);
        *core_guard = Some(engine);
        true
    }

    /// Signal the engine thread to exit and block until it finishes.
    #[func]
    pub fn stop(&self) {
        self.stop_streams();
        if let Ok(mut core_guard) = self.core.lock() {
            if let Some(mut engine) = core_guard.take() {
                engine.stop();
            }
        }
        godot_print!("RtEngine: stopped.");
    }

    /// Push interleaved PCM-16-LE bytes (from `AudioEngine.decode_all()`) into the
    /// music ring buffer.  Returns the number of f32 samples actually written.
    #[func]
    pub fn push_music_pcm(&self, data: PackedByteArray) -> i64 {
        let mut core_guard = match self.core.lock() {
            Ok(g) => g,
            Err(_) => return 0,
        };
        let engine = match core_guard.as_mut() {
            Some(e) => e,
            None => {
                godot_warn!("RtEngine: push_music_pcm() called before start().");
                return 0;
            }
        };

        let raw: Vec<u8> = data.to_vec();
        let mut written = 0i64;
        for chunk in raw.chunks_exact(2) {
            let s = i16::from_le_bytes([chunk[0], chunk[1]]) as f32 / 32_768.0;
            match engine.music_producer.push(s) {
                Ok(()) => written += 1,
                Err(_) => break,
            }
        }
        written
    }

    /// Set gain in dB for a mixer bus (0=Ui, 1=Music, …, 6=Master, …).
    #[func]
    pub fn set_bus_gain_db(&self, bus: i32, gain_db: f32) {
        if let Ok(mut m) = self.gain_db_mirror.lock() {
            if let Some(v) = m.get_mut(bus as usize) {
                *v = gain_db;
            }
        }
        self.send_cmd(EngineCmd::SetGainDb { bus: bus as usize, db: gain_db });
    }

    /// Mute or unmute a mixer bus.
    #[func]
    pub fn set_bus_mute(&self, bus: i32, mute: bool) {
        self.send_cmd(EngineCmd::SetMute { bus: bus as usize, mute });
    }

    /// Solo a mixer bus.
    #[func]
    pub fn set_bus_solo(&self, bus: i32, solo: bool) {
        self.send_cmd(EngineCmd::SetSolo { bus: bus as usize, solo });
    }

    /// Adjust stem-ducking amount (in dB).
    #[func]
    pub fn set_stem_ducking_db(&self, db: f32) {
        self.send_cmd(EngineCmd::SetStemDuckingDb { db });
    }

    /// Returns `true` if the engine thread is running.
    #[func]
    pub fn is_running(&self) -> bool {
        self.core.lock()
            .map(|g| g.is_some())
            .unwrap_or(false)
    }

    /// How many free f32 sample slots remain in the music ring buffer.
    #[func]
    pub fn music_rb_free_slots(&self) -> i64 {
        self.core.lock()
            .ok()
            .and_then(|g| g.as_ref().map(|e| e.music_producer.slots() as i64))
            .unwrap_or(0)
    }

    // ── Bus metadata ──────────────────────────────────────────────────────────

    /// Total number of mixer buses (always 9).
    #[func]
    pub fn get_bus_count(&self) -> i32 {
        BUS_COUNT as i32
    }

    /// Display name for a bus index.
    #[func]
    pub fn get_bus_name(&self, bus: i32) -> GString {
        GString::from(match bus {
            0 => "UI",
            1 => "Music",
            2 => "Lead Guitar",
            3 => "Rhythm Guitar",
            4 => "Bass",
            5 => "Player Instrument",
            6 => "Master",
            7 => "Metronome",
            8 => "Mic Room",
            _ => "Unknown",
        })
    }

    /// Read back the gain (dB) last set for a bus.
    #[func]
    pub fn get_bus_gain_db(&self, bus: i32) -> f32 {
        self.gain_db_mirror.lock()
            .ok()
            .and_then(|g| g.get(bus as usize).copied())
            .unwrap_or(0.0)
    }

    /// Current peak level for a bus (0.0 = silence, 1.0 = 0 dBFS).
    #[func]
    pub fn get_bus_meter_peak(&self, bus: i32) -> f32 {
        // Read from the engine core's shared meter_peaks.
        self.core.lock()
            .ok()
            .and_then(|g| {
                g.as_ref().and_then(|e| {
                    e.meter_peaks.lock()
                        .ok()
                        .and_then(|p| p.get(bus as usize).copied())
                })
            })
            .unwrap_or(0.0)
    }

    /// Reset the peak hold for a bus to 0.0.
    #[func]
    pub fn reset_bus_meter_peak(&self, bus: i32) {
        if let Ok(core_guard) = self.core.lock() {
            if let Some(engine) = core_guard.as_ref() {
                if let Ok(mut peaks) = engine.meter_peaks.lock() {
                    if let Some(p) = peaks.get_mut(bus as usize) {
                        *p = 0.0;
                    }
                }
            }
        }
    }

    // ── CPAL I/O streams ──────────────────────────────────────────────────────

    /// Open CPAL input and output streams.
    /// Must be called **after** `start()`.  Returns `true` on success.
    #[func]
    pub fn start_streams(
        &self,
        input_device_name:  GString,
        output_device_name: GString,
    ) -> bool {
        let (ch, sr, output_consumer, input_producer) = {
            let mut core_guard = match self.core.lock() {
                Ok(g)  => g,
                Err(_) => return false,
            };
            let engine = match core_guard.as_mut() {
                Some(e) => e,
                None    => {
                    godot_error!("RtEngine: call start() before start_streams().");
                    return false;
                }
            };
            let oc = match engine.output_consumer.take() {
                Some(c) => c,
                None    => {
                    godot_error!("RtEngine: output ring buffer already consumed. \
                                  Call stop() + start() to reset.");
                    return false;
                }
            };
            let ip = match engine.input_producer.take() {
                Some(p) => p,
                None    => {
                    godot_error!("RtEngine: input ring buffer already consumed. \
                                  Call stop() + start() to reset.");
                    return false;
                }
            };
            (engine.channels, engine.sample_rate, oc, ip)
        };

        let cfg = AudioIoConfig { channels: ch, sample_rate: sr };
        let input_rb  = Arc::new(Mutex::new(Some(input_producer)));
        let output_rb = Arc::new(Mutex::new(Some(output_consumer)));

        let in_name  = input_device_name.to_string();
        let out_name = output_device_name.to_string();

        match open_streams(&cfg, &in_name, &out_name, input_rb, output_rb) {
            Ok(streams) => {
                if let Ok(mut io) = self.io_streams.lock() {
                    *io = Some(streams);
                }
                godot_print!(
                    "RtEngine: CPAL streams started — out='{}' in='{}'",
                    output_device_name, input_device_name
                );
                true
            }
            Err(e) => {
                godot_error!("RtEngine: start_streams failed: {}", e);
                false
            }
        }
    }

    /// Close CPAL streams.  The engine thread keeps running.
    #[func]
    pub fn stop_streams(&self) {
        if let Ok(mut io) = self.io_streams.lock() {
            if io.take().is_some() {
                godot_print!("RtEngine: CPAL streams stopped.");
            }
        }
    }

    /// List available output device names.
    #[func]
    pub fn list_output_devices(&self) -> PackedStringArray {
        let mut out = PackedStringArray::new();
        for name in crate::audio_io::list_output_devices() {
            out.push(&GString::from(name.as_str()));
        }
        out
    }

    /// List available input device names.
    #[func]
    pub fn list_input_devices(&self) -> PackedStringArray {
        let mut out = PackedStringArray::new();
        for name in crate::audio_io::list_input_devices() {
            out.push(&GString::from(name.as_str()));
        }
        out
    }
}

// ── Private helpers ───────────────────────────────────────────────────────────

impl RtEngine {
    fn send_cmd(&self, cmd: EngineCmd) {
        if let Ok(mut core_guard) = self.core.lock() {
            if let Some(engine) = core_guard.as_mut() {
                let _ = engine.cmd_producer.push(cmd);
            }
        }
    }
}
