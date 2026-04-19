/// q_bridge.h — C interface wrapping cycfi/q pitch_detector for Rust FFI.
///
/// Each QPitchDetector handle is an opaque C++ object.
/// Use q_pd_create() / q_pd_destroy() to manage lifetime.
/// Feed samples one at a time with q_pd_process(); when it returns `true`
/// a new pitch estimate is ready — read it with q_pd_get_frequency() and
/// q_pd_get_periodicity().

#ifndef Q_BRIDGE_H
#define Q_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to a C++ `cycfi::q::pitch_detector` instance.
typedef struct QPitchDetector QPitchDetector;

/// Create a pitch-detector configured for the frequency band [min_freq, max_freq] Hz.
///
/// @param min_freq      Lowest expected fundamental in Hz.
/// @param max_freq      Highest expected fundamental in Hz.
/// @param sample_rate   Audio sample rate in Hz (e.g. 48000).
/// @param hysteresis_db Hysteresis threshold in dB (negative, e.g. -40.0).
/// @return              Heap-allocated detector, or NULL on failure.
QPitchDetector* q_pd_create(float min_freq, float max_freq,
                             uint32_t sample_rate, float hysteresis_db);

/// Destroy a detector previously created by q_pd_create().
void q_pd_destroy(QPitchDetector* pd);

/// Feed one mono f32 sample to the detector.
///
/// @return true when a new pitch estimate is ready (call q_pd_get_frequency /
///         q_pd_get_periodicity to retrieve it).
bool q_pd_process(QPitchDetector* pd, float sample);

/// Most recent detected frequency in Hz (0.0 if none detected yet).
/// Also updates the cached periodicity — call this before q_pd_get_periodicity.
float q_pd_get_frequency(QPitchDetector* pd);

/// Most recent periodicity / confidence score in [0.0, 1.0].
/// Valid after the most recent call to q_pd_get_frequency.
float q_pd_get_periodicity(QPitchDetector* pd);

#ifdef __cplusplus
}
#endif

#endif /* Q_BRIDGE_H */
