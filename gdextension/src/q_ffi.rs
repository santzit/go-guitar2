/// q_ffi.rs — Raw unsafe Rust bindings to the C bridge over cycfi/q.
///
/// Only available when the Q headers are present (`extern/q/include` exists)
/// and the `q_bridge` static library was compiled by build.rs.
///
/// Do **not** use these symbols directly — prefer the safe wrapper in
/// `pitch_detector.rs`.

use std::os::raw::{c_float, c_uint};

/// Opaque handle to a heap-allocated `QPitchDetector` C++ object.
/// Ownership is exclusively managed by [`StringDetector`].
#[repr(C)]
pub struct QPitchDetector {
    _opaque: [u8; 0],
}

extern "C" {
    /// Create a pitch detector covering [min_freq, max_freq] Hz.
    pub fn q_pd_create(
        min_freq:      c_float,
        max_freq:      c_float,
        sample_rate:   c_uint,
        hysteresis_db: c_float,
    ) -> *mut QPitchDetector;

    /// Destroy a detector (frees C++ memory).
    pub fn q_pd_destroy(pd: *mut QPitchDetector);

    /// Feed one mono f32 sample; returns `true` when a pitch estimate is ready.
    pub fn q_pd_process(pd: *mut QPitchDetector, sample: c_float) -> bool;

    /// Most recent detected frequency in Hz (also updates cached periodicity).
    pub fn q_pd_get_frequency(pd: *mut QPitchDetector) -> c_float;

    /// Most recent periodicity / confidence in [0.0, 1.0].
    pub fn q_pd_get_periodicity(pd: *mut QPitchDetector) -> c_float;
}
