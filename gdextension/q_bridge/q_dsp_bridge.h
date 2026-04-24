/// q_dsp_bridge.h — C API for the cycfi/q SPSC ring-buffer DSP bridge.
///
/// Owns two lock-free SPSC ring buffers (in → DSP thread → out) and an
/// optional C++ DSP thread that uses cycfi/q signal-conditioning on each block.
///
/// Plain-C interface so Rust FFI can call directly without C++ ABI mangling.
///
/// ## Pipeline
/// ```
/// push_input_f32()  →  [in_rb]  →  DSP thread (dc_block + lowpass)
/// push_input_i16()  ↗                         ↓
/// pop_output_f32()  ←  [out_rb] ←─────────────╯
/// ```

#ifndef Q_DSP_BRIDGE_H
#define Q_DSP_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to a C++ `QDspBridge` instance.
typedef struct QDspBridge QDspBridge;

/// Create a DSP bridge with SPSC ring buffers of `capacity` f32 samples each.
///
/// @param capacity          Number of f32 samples in each ring buffer (must be > 0;
///                          rounded up to the next power of two internally).
/// @param sample_rate       Audio sample rate in Hz (e.g. 48000), used by Q DSP.
/// @param block_size        Samples per DSP processing block (e.g. 128).
/// @param start_dsp_thread  When true, the internal DSP thread is started immediately.
/// @return                  Heap-allocated bridge, or NULL on failure.
QDspBridge* q_dsp_create(uint32_t capacity,
                          uint32_t sample_rate,
                          uint32_t block_size,
                          bool     start_dsp_thread);

/// Destroy a bridge created by q_dsp_create().  Stops the DSP thread if running.
void q_dsp_destroy(QDspBridge* bridge);

/// Start the internal DSP thread (no-op if already running).
void q_dsp_start(QDspBridge* bridge);

/// Stop the internal DSP thread and block until it exits.
void q_dsp_stop(QDspBridge* bridge);

/// Push PCM-16-LE mono samples into the input ring buffer.
///
/// @param data   Pointer to an array of `count` int16_t samples.
/// @param count  Number of samples to push.
/// @return       Number of samples actually written (< count if buffer full).
uint32_t q_dsp_push_input_i16(QDspBridge* bridge,
                               const int16_t* data,
                               uint32_t count);

/// Push f32 mono samples directly into the input ring buffer.
///
/// Preferred over q_dsp_push_input_i16 — avoids the f32→i16→f32 round-trip
/// that introduces unnecessary quantisation noise.
///
/// @param data   Pointer to an array of `count` float samples (any range,
///               though values in [-1, 1] are conventional).
/// @param count  Number of samples to push.
/// @return       Number of samples actually written (< count if buffer full).
uint32_t q_dsp_push_input_f32(QDspBridge* bridge,
                               const float* data,
                               uint32_t count);

/// Pop f32 samples from the output ring buffer.
///
/// @param out       Destination buffer (must hold at least `max_count` floats).
/// @param max_count Maximum number of samples to pop.
/// @return          Number of samples actually read.
uint32_t q_dsp_pop_output_f32(QDspBridge* bridge,
                               float*   out,
                               uint32_t max_count);

/// Number of free f32 slots in the input ring buffer.
uint32_t q_dsp_input_free(QDspBridge* bridge);

/// Number of f32 samples available in the output ring buffer.
uint32_t q_dsp_output_avail(QDspBridge* bridge);

#ifdef __cplusplus
}
#endif

#endif /* Q_DSP_BRIDGE_H */
