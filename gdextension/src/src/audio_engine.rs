/// audio_engine.rs — WEM audio decoder exposed as a Godot GDExtension class.
///
/// Uses **vgmstream** (linked as `libvgmstream.a` on Linux via `build.rs`) to
/// decode Wwise `.wem` audio from an in-memory byte buffer into raw PCM-16 LE,
/// which GDScript then wraps in an `AudioStreamWAV` for playback.
///
/// GDScript usage:
/// ```gdscript
/// var eng = AudioEngine.new()
/// if eng.open(wem_bytes):
///     var stream = AudioStreamWAV.new()
///     stream.format   = AudioStreamWAV.FORMAT_16_BITS
///     stream.stereo   = (eng.get_channels() == 2)
///     stream.mix_rate = eng.get_sample_rate()
///     stream.data     = eng.decode_all()
/// ```
use godot::prelude::*;
use gg_mixer::{BusId, MixInput, Mixer};

// ── Godot class ──────────────────────────────────────────────────────────────

#[derive(GodotClass)]
#[class(base = Object)]
pub struct AudioEngine {
    #[base]
    base:        Base<Object>,
    channels:    i32,
    sample_rate: i32,
    pcm_ready:   bool,
    // Decoded PCM-16 bytes (interleaved channels, little-endian).
    pcm_buf:     Vec<u8>,
    mixer:       Mixer,
}

#[godot_api]
impl IObject for AudioEngine {
    fn init(base: Base<Object>) -> Self {
        Self {
            base,
            channels:    0,
            sample_rate: 0,
            pcm_ready:   false,
            pcm_buf:     Vec::new(),
            mixer:       Mixer::new(),
        }
    }
}

#[godot_api]
impl AudioEngine {
    /// Decode WEM bytes into the internal PCM buffer.
    /// Returns `true` on success; subsequent calls replace any previous data.
    #[func]
    pub fn open(&mut self, data: PackedByteArray) -> bool {
        self.pcm_ready  = false;
        self.pcm_buf    = Vec::new();
        self.channels   = 0;
        self.sample_rate = 0;

        let raw: Vec<u8> = data.to_vec();
        if raw.is_empty() {
            godot_error!("AudioEngine: empty data passed to open()");
            return false;
        }

        // vgmstream decoding is available on Linux and Windows (static lib linked via build.rs).
        #[cfg(any(target_os = "linux", target_os = "windows"))]
        {
            match ffi::decode_wem(raw) {
                Ok(result) => {
                    self.channels    = result.channels;
                    self.sample_rate = result.sample_rate;
                    self.pcm_buf     = result.pcm_bytes;
                    self.apply_mixer_to_pcm();
                    self.pcm_ready   = true;
                    godot_print!(
                        "AudioEngine: decoded {} WEM bytes → {} PCM bytes \
                         ({} ch, {} Hz)",
                        data.len(),
                        self.pcm_buf.len(),
                        self.channels,
                        self.sample_rate
                    );
                    true
                }
                Err(e) => {
                    godot_error!("AudioEngine: decode failed: {}", e);
                    false
                }
            }
        }

        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
        {
            godot_warn!(
                "AudioEngine: vgmstream WEM decoding is not supported on this platform."
            );
            false
        }
    }

    /// Returns raw PCM-16 LE bytes (interleaved channels).
    /// Returns an empty array if `open()` has not been called or failed.
    #[func]
    pub fn decode_all(&self) -> PackedByteArray {
        if !self.pcm_ready {
            return PackedByteArray::new();
        }
        PackedByteArray::from(self.pcm_buf.as_slice())
    }

    /// Number of audio channels (0 if not opened).
    #[func]
    pub fn get_channels(&self) -> i32 {
        self.channels
    }

    /// Sample rate in Hz (0 if not opened).
    #[func]
    pub fn get_sample_rate(&self) -> i32 {
        self.sample_rate
    }

    /// True if `open()` succeeded and PCM data is ready.
    #[func]
    pub fn is_ready(&self) -> bool {
        self.pcm_ready
    }

    /// Set gain (dB) for the Music bus in gg-mixer.
    #[func]
    pub fn set_music_gain_db(&mut self, gain_db: f32) {
        self.mixer.set_gain_db(BusId::Music, gain_db);
    }

    /// Set gain (dB) for the Master bus in gg-mixer.
    #[func]
    pub fn set_master_gain_db(&mut self, gain_db: f32) {
        self.mixer.set_gain_db(BusId::Master, gain_db);
    }

    /// Mute/unmute the Music bus in gg-mixer.
    #[func]
    pub fn set_music_mute(&mut self, mute: bool) {
        self.mixer.set_mute(BusId::Music, mute);
    }

    /// Mute/unmute the Master bus in gg-mixer.
    #[func]
    pub fn set_master_mute(&mut self, mute: bool) {
        self.mixer.set_mute(BusId::Master, mute);
    }
}

impl AudioEngine {
    fn apply_mixer_to_pcm(&mut self) {
        if self.pcm_buf.is_empty() {
            return;
        }

        for chunk in self.pcm_buf.chunks_exact_mut(2) {
            let sample_i16 = i16::from_le_bytes([chunk[0], chunk[1]]);
            let sample_f32 = (sample_i16 as f32) / 32768.0;
            let mixed_f32 = self.mixer.mix_sample(MixInput {
                music: sample_f32,
                ..Default::default()
            });
            let mixed_i16 = (mixed_f32.clamp(-1.0, 1.0) * 32767.0) as i16;
            let bytes = mixed_i16.to_le_bytes();
            chunk[0] = bytes[0];
            chunk[1] = bytes[1];
        }
    }
}

// ── vgmstream FFI (Linux and Windows) ────────────────────────────────────────

#[cfg(any(target_os = "linux", target_os = "windows"))]
mod ffi {
    use std::ffi::{c_int, c_void, CString};
    use std::sync::Arc;

    // ── C type bindings ──────────────────────────────────────────────────────

    /// `LIBVGMSTREAM_SFMT_PCM16` — 2-byte signed little-endian samples.
    /// Used in `LibVgmstreamConfig::force_sfmt` to request PCM16 output.
    const LIBVGMSTREAM_SFMT_PCM16: c_int = 1;

    /// Mirrors `libstreamfile_t` from libvgmstream_streamfile.h
    #[repr(C)]
    pub struct LibStreamFile {
        pub user_data: *mut c_void,
        pub read:      Option<unsafe extern "C" fn(*mut c_void, *mut u8, i64, c_int) -> c_int>,
        pub get_size:  Option<unsafe extern "C" fn(*mut c_void) -> i64>,
        pub get_name:  Option<unsafe extern "C" fn(*mut c_void) -> *const i8>,
        pub open:      Option<unsafe extern "C" fn(*mut c_void, *const i8) -> *mut LibStreamFile>,
        pub close:     Option<unsafe extern "C" fn(*mut LibStreamFile)>,
    }

    /// Mirrors `libvgmstream_format_t` — first four fields used; rest is opaque.
    /// Layout from libvgmstream.h: channels(+0), sample_rate(+4),
    /// sample_format(+8), sample_size(+12).
    #[repr(C)]
    pub struct LibVgmstreamFormat {
        pub channels:      c_int,  // +0
        pub sample_rate:   c_int,  // +4
        pub sample_format: c_int,  // +8  (libvgmstream_sfmt_t: 1=PCM16, 4=float)
        pub sample_size:   c_int,  // +12 (bytes per sample: 2 for PCM16, 4 for float)
        // rest of the struct is not accessed
    }

    /// Mirrors `libvgmstream_decoder_t`
    #[repr(C)]
    pub struct LibVgmstreamDecoder {
        pub buf:         *mut c_void,
        pub buf_samples: c_int,
        pub buf_bytes:   c_int,
        pub done:        bool,
    }

    /// Mirrors `libvgmstream_t`
    #[repr(C)]
    pub struct LibVgmstream {
        pub priv_:   *mut c_void,
        pub format:  *const LibVgmstreamFormat,
        pub decoder: *mut LibVgmstreamDecoder,
    }

    /// Mirrors `libvgmstream_config_t` (x86_64 System V ABI layout).
    /// Layout from libvgmstream.h:
    ///   bools  +0..+6  (7 × bool),  pad +7,
    ///   f64s   +8..+31 (loop_count, fade_time, fade_delay),
    ///   ints   +32..+43 (stereo_track, auto_downmix_channels, force_sfmt),
    ///   pad    +44..+47 → total 48 bytes.
    #[repr(C)]
    struct LibVgmstreamConfig {
        disable_config_override:  bool,     // +0
        allow_play_forever:       bool,     // +1
        play_forever:             bool,     // +2
        ignore_loop:              bool,     // +3
        force_loop:               bool,     // +4
        really_force_loop:        bool,     // +5
        ignore_fade:              bool,     // +6
        _pad0:                    u8,       // +7  (align f64 to 8)
        loop_count:               f64,      // +8
        fade_time:                f64,      // +16
        fade_delay:               f64,      // +24
        stereo_track:             c_int,    // +32
        auto_downmix_channels:    c_int,    // +36
        force_sfmt:               c_int,    // +40 (1 = LIBVGMSTREAM_SFMT_PCM16)
        _pad1:                    [u8; 4],  // +44 (pad to 48)
    }

    extern "C" {
        fn libvgmstream_init() -> *mut LibVgmstream;
        fn libvgmstream_free(lib: *mut LibVgmstream);
        fn libvgmstream_setup(lib: *mut LibVgmstream, cfg: *const LibVgmstreamConfig);
        fn libvgmstream_open_stream(
            lib:     *mut LibVgmstream,
            libsf:   *mut LibStreamFile,
            subsong: c_int,
        ) -> c_int;
        fn libvgmstream_render(lib: *mut LibVgmstream) -> c_int;
        fn libstreamfile_close(libsf: *mut LibStreamFile);
    }

    // ── Memory-backed streamfile ─────────────────────────────────────────────

    /// State stored at `user_data` in `LibStreamFile`.
    struct MemSfState {
        data: Arc<Vec<u8>>,
        name: CString,
    }

    unsafe extern "C" fn msf_read(
        ud:     *mut c_void,
        dst:    *mut u8,
        offset: i64,
        length: c_int,
    ) -> c_int {
        let state  = &*(ud as *const MemSfState);
        let data   = &*state.data;
        let offset = offset as usize;
        let length = length as usize;
        if offset >= data.len() {
            return 0;
        }
        let available = data.len() - offset;
        let to_copy   = available.min(length);
        std::ptr::copy_nonoverlapping(data[offset..].as_ptr(), dst, to_copy);
        to_copy as c_int
    }

    unsafe extern "C" fn msf_get_size(ud: *mut c_void) -> i64 {
        let state = &*(ud as *const MemSfState);
        state.data.len() as i64
    }

    unsafe extern "C" fn msf_get_name(ud: *mut c_void) -> *const i8 {
        let state = &*(ud as *const MemSfState);
        state.name.as_ptr()
    }

    unsafe extern "C" fn msf_open(
        ud:       *mut c_void,
        _filename: *const i8,
    ) -> *mut LibStreamFile {
        // vgmstream may call open() to "reopen" the same stream or companion files.
        // We always return a new SF backed by the same Arc<Vec<u8>>.
        let state    = &*(ud as *const MemSfState);
        let new_state = Box::new(MemSfState {
            data: Arc::clone(&state.data),
            name: state.name.clone(),
        });
        let sf = Box::new(LibStreamFile {
            user_data: Box::into_raw(new_state) as *mut c_void,
            read:      Some(msf_read),
            get_size:  Some(msf_get_size),
            get_name:  Some(msf_get_name),
            open:      Some(msf_open),
            close:     Some(msf_close),
        });
        Box::into_raw(sf)
    }

    unsafe extern "C" fn msf_close(libsf: *mut LibStreamFile) {
        if libsf.is_null() {
            return;
        }
        let sf = Box::from_raw(libsf);
        if !sf.user_data.is_null() {
            let _: Box<MemSfState> = Box::from_raw(sf.user_data as *mut MemSfState);
        }
        // `sf` dropped here
    }

    /// Construct a heap-allocated `LibStreamFile` backed by the given bytes.
    fn make_mem_sf(data: Arc<Vec<u8>>) -> Box<LibStreamFile> {
        let state = Box::new(MemSfState {
            data,
            name: CString::new("audio.wem").unwrap_or_default(),
        });
        Box::new(LibStreamFile {
            user_data: Box::into_raw(state) as *mut c_void,
            read:      Some(msf_read),
            get_size:  Some(msf_get_size),
            get_name:  Some(msf_get_name),
            open:      Some(msf_open),
            close:     Some(msf_close),
        })
    }

    // ── Decode ───────────────────────────────────────────────────────────────

    pub struct DecodeResult {
        pub channels:    i32,
        pub sample_rate: i32,
        pub pcm_bytes:   Vec<u8>,
    }

    /// Decode WEM bytes to interleaved PCM-16 LE.
    pub fn decode_wem(data: Vec<u8>) -> Result<DecodeResult, String> {
        let shared = Arc::new(data);

        unsafe {
            // 1. Create libvgmstream context.
            let lib = libvgmstream_init();
            if lib.is_null() {
                return Err("libvgmstream_init() returned NULL".into());
            }

            // 2. Configure PCM16 output before opening the stream.
            //    Wwise Vorbis defaults to float output internally; force_sfmt=PCM16
            //    tells vgmstream to convert to signed 16-bit LE before filling the
            //    decode buffer — no game-side conversion needed.
            let cfg = LibVgmstreamConfig {
                disable_config_override:  false,
                allow_play_forever:       false,
                play_forever:             false,
                ignore_loop:              true,  // play through without looping
                force_loop:               false,
                really_force_loop:        false,
                ignore_fade:              true,  // no fade-out at loop end
                _pad0:                    0,
                loop_count:               0.0,
                fade_time:                0.0,
                fade_delay:               0.0,
                stereo_track:             0,
                auto_downmix_channels:    0,
                force_sfmt:               LIBVGMSTREAM_SFMT_PCM16,
                _pad1:                    [0u8; 4],
            };
            libvgmstream_setup(lib, &cfg as *const LibVgmstreamConfig);

            // 3. Create memory streamfile.
            let mut sf = make_mem_sf(Arc::clone(&shared));
            let sf_ptr = sf.as_mut() as *mut LibStreamFile;

            // 4. Open the stream (subsong 0 = auto/first).
            let rc = libvgmstream_open_stream(lib, sf_ptr, 0);
            // Close the SF now — vgmstream made its own copy via open() callbacks.
            libstreamfile_close(sf_ptr);
            // Prevent double-free: sf no longer owns a live C allocation.
            std::mem::forget(sf);

            if rc != 0 {
                libvgmstream_free(lib);
                return Err(format!(
                    "libvgmstream_open_stream() failed (rc={}); \
                     file may not be a supported WEM variant",
                    rc
                ));
            }

            // 5. Read format — vgmstream guarantees PCM16 after setup above.
            if (*lib).format.is_null() || (*lib).decoder.is_null() {
                libvgmstream_free(lib);
                return Err("libvgmstream format/decoder pointer is NULL after open".into());
            }
            let channels    = (*(*lib).format).channels;
            let sample_rate = (*(*lib).format).sample_rate;
            if channels <= 0 || sample_rate <= 0 {
                libvgmstream_free(lib);
                return Err(format!(
                    "invalid stream info: channels={}, sample_rate={}",
                    channels, sample_rate
                ));
            }

            // 6. Decode loop — buffer is guaranteed PCM16 LE by libvgmstream_setup.
            let mut all_pcm: Vec<u8> = Vec::with_capacity(
                // Pre-allocate ~10 s at stereo 48 kHz PCM16.
                (sample_rate * channels * 2 * 10) as usize,
            );
            const MAX_ITERS: usize = 200_000;
            for _ in 0..MAX_ITERS {
                let rc = libvgmstream_render(lib);
                if rc < 0 {
                    break; // decode error
                }
                let dec = &*(*lib).decoder;
                if dec.buf_samples > 0 && !dec.buf.is_null() {
                    let bytes = dec.buf_bytes as usize;
                    let slice = std::slice::from_raw_parts(dec.buf as *const u8, bytes);
                    all_pcm.extend_from_slice(slice);
                }
                if dec.done {
                    break;
                }
            }

            // 7. Clean up.
            libvgmstream_free(lib);

            Ok(DecodeResult {
                channels:    channels as i32,
                sample_rate: sample_rate as i32,
                pcm_bytes:   all_pcm,
            })
        }
    }
}
