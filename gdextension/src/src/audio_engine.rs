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
}

// ── vgmstream FFI (Linux and Windows) ────────────────────────────────────────

#[cfg(any(target_os = "linux", target_os = "windows"))]
mod ffi {
    use std::ffi::{c_int, c_void, CString};
    use std::sync::Arc;

    // ── C type bindings ──────────────────────────────────────────────────────

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

    /// Partial mirror of `libvgmstream_format_t` — only the first two fields
    /// are accessed; the rest of the struct is left as opaque padding.
    #[repr(C)]
    pub struct LibVgmstreamFormat {
        pub channels:    c_int,
        pub sample_rate: c_int,
        // rest of the 700+ byte struct is not accessed
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

    extern "C" {
        fn libvgmstream_init()        -> *mut LibVgmstream;
        fn libvgmstream_free(lib: *mut LibVgmstream);
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

            // 2. Create memory streamfile.
            let mut sf = make_mem_sf(Arc::clone(&shared));
            let sf_ptr = sf.as_mut() as *mut LibStreamFile;

            // 3. Open the stream (subsong 0 = auto/first).
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

            // 4. Read format.
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

            // 5. Decode loop.
            // libvgmstream_render() fills decoder->buf with one internal chunk
            // of PCM-16 samples and updates decoder->buf_samples / done.
            let mut all_pcm: Vec<u8> = Vec::with_capacity(
                // Pre-allocate ~10 s at stereo 48 kHz PCM16 as a guess.
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

            // 6. Clean up.
            libvgmstream_free(lib);

            Ok(DecodeResult {
                channels:    channels as i32,
                sample_rate: sample_rate as i32,
                pcm_bytes:   all_pcm,
            })
        }
    }
}
