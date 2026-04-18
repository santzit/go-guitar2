/*
 * q_pitch_ffi.h — C FFI interface for per-string guitar pitch detection
 *                 using cycfi/Q's pitch_detector.
 *
 * Called from Rust via extern "C".  The library maintains no global state;
 * every call to q_detect_strings() is fully self-contained.
 */
#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Per-string result.
 *
 * active  – 1 if a pitch was detected in this string's frequency band, 0 otherwise
 * hz      – detected frequency in Hz (0.0 when inactive)
 */
typedef struct {
    int   active;
    float hz;
} QStringResult;

/*
 * Detect the pitch on each of the 6 guitar strings simultaneously.
 *
 * samples     – mono PCM float32 buffer
 * n_samples   – number of samples in the buffer
 * sample_rate – sample rate in Hz (typically 44100)
 * out         – caller-allocated array of exactly 6 QStringResult entries
 *               (index 0 = string 6 low E, index 5 = string 1 high e)
 */
void q_detect_strings(const float* samples,
                      int          n_samples,
                      float        sample_rate,
                      QStringResult out[6]);

#ifdef __cplusplus
}
#endif
