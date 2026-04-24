/// q_dsp_ffi.rs — Rust unsafe bindings to the C++ SPSC DSP bridge (q_dsp_bridge.cpp).
///
/// The bridge owns two lock-free SPSC ring buffers and an optional C++ DSP
/// thread that applies cycfi/q signal conditioning (dc_block + one_pole_lowpass)
/// to each block of guitar DI samples.
///
/// Use the safe helpers in `rt_engine.rs` instead of calling these directly.
///
/// Only available when Q headers / the prebuilt Q bridge are present
/// (i.e. when the `q_available` cfg flag is set by build.rs).

use std::os::raw::{c_float, c_uint};

/// Opaque handle to a heap-allocated `QDspBridge` C++ object.
#[repr(C)]
pub struct QDspBridge {
    _opaque: [u8; 0],
}

extern "C" {
    /// Create a DSP bridge with SPSC ring buffers of `capacity` f32 samples.
    pub fn q_dsp_create(
        capacity:         c_uint,
        sample_rate:      c_uint,
        block_size:       c_uint,
        start_dsp_thread: bool,
    ) -> *mut QDspBridge;

    /// Destroy a bridge (stops DSP thread, frees memory).
    pub fn q_dsp_destroy(bridge: *mut QDspBridge);

    /// Start the internal DSP thread.
    pub fn q_dsp_start(bridge: *mut QDspBridge);

    /// Stop the internal DSP thread (blocks until the thread exits).
    pub fn q_dsp_stop(bridge: *mut QDspBridge);

    /// Push PCM-16-LE samples into the input ring buffer.
    /// Returns the number of samples actually written.
    pub fn q_dsp_push_input_i16(
        bridge: *mut QDspBridge,
        data:   *const i16,
        count:  c_uint,
    ) -> c_uint;

    /// Pop f32 samples from the output ring buffer.
    /// Returns the number of samples actually read.
    pub fn q_dsp_pop_output_f32(
        bridge:    *mut QDspBridge,
        out:       *mut c_float,
        max_count: c_uint,
    ) -> c_uint;

    /// Number of free f32 slots in the input ring buffer.
    pub fn q_dsp_input_free(bridge: *mut QDspBridge) -> c_uint;

    /// Number of f32 samples available in the output ring buffer.
    pub fn q_dsp_output_avail(bridge: *mut QDspBridge) -> c_uint;
}
