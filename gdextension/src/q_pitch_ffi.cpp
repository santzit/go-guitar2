/*
 * q_pitch_ffi.cpp — C FFI implementation for per-string guitar pitch detection.
 *
 * Uses cycfi/Q pitch_detector (BACF-based) to detect the fundamental frequency
 * on each of the 6 guitar strings independently.  Six detectors are created
 * with per-string frequency bands matching standard EADGBE tuning.
 *
 * Frequency bands (open string Hz .. fret-24 Hz):
 *   String 6  E2   82.41 – 329.63 Hz
 *   String 5  A2  110.00 – 440.00 Hz
 *   String 4  D3  146.83 – 587.33 Hz
 *   String 3  G3  196.00 – 784.00 Hz
 *   String 2  B3  246.94 – 987.77 Hz
 *   String 1  e4  329.63 – 1318.51 Hz
 */

#include "q_pitch_ffi.h"
#include <q/pitch/pitch_detector.hpp>
#include <q/support/literals.hpp>
#include <cmath>

namespace q = cycfi::q;
using namespace q::literals;

// ── Per-string tuning constants ──────────────────────────────────────────────

static const float OPEN_HZ[6] = {
     82.41f,   // str 6  E2
    110.00f,   // str 5  A2
    146.83f,   // str 4  D3
    196.00f,   // str 3  G3
    246.94f,   // str 2  B3
    329.63f,   // str 1  e4
};

static const float MAX_HZ[6] = {
    329.63f,   // str 6  fret 24
    440.00f,   // str 5  fret 24
    587.33f,   // str 4  fret 24
    784.00f,   // str 3  fret 24
    987.77f,   // str 2  fret 24
   1318.51f,   // str 1  fret 24
};

// Minimum RMS amplitude — buffers quieter than this are treated as silence.
static const float MIN_RMS = 0.01f;

// ── Helpers ───────────────────────────────────────────────────────────────────

static float rms(const float* samples, int n)
{
    double sum = 0.0;
    for (int i = 0; i < n; ++i)
        sum += (double)samples[i] * (double)samples[i];
    return (float)std::sqrt(sum / (double)n);
}

// ── Public API ────────────────────────────────────────────────────────────────

extern "C"
void q_detect_strings(const float*  samples,
                      int           n_samples,
                      float         sample_rate,
                      QStringResult out[6])
{
    // Initialise all outputs to inactive.
    for (int s = 0; s < 6; ++s) {
        out[s].active = 0;
        out[s].hz     = 0.0f;
    }

    if (n_samples < 256 || rms(samples, n_samples) < MIN_RMS)
        return;

    // Create one pitch_detector per string.
    // Hysteresis of -45 dB is Q's recommended starting point — it prevents
    // the detector from latching onto noise between notes.
    q::pitch_detector pd0{ q::frequency{OPEN_HZ[0]}, q::frequency{MAX_HZ[0]}, sample_rate, -45_dB };
    q::pitch_detector pd1{ q::frequency{OPEN_HZ[1]}, q::frequency{MAX_HZ[1]}, sample_rate, -45_dB };
    q::pitch_detector pd2{ q::frequency{OPEN_HZ[2]}, q::frequency{MAX_HZ[2]}, sample_rate, -45_dB };
    q::pitch_detector pd3{ q::frequency{OPEN_HZ[3]}, q::frequency{MAX_HZ[3]}, sample_rate, -45_dB };
    q::pitch_detector pd4{ q::frequency{OPEN_HZ[4]}, q::frequency{MAX_HZ[4]}, sample_rate, -45_dB };
    q::pitch_detector pd5{ q::frequency{OPEN_HZ[5]}, q::frequency{MAX_HZ[5]}, sample_rate, -45_dB };

    q::pitch_detector* pds[6] = { &pd0, &pd1, &pd2, &pd3, &pd4, &pd5 };

    // Feed every sample through all six detectors.
    for (int i = 0; i < n_samples; ++i) {
        float s = samples[i];
        for (int d = 0; d < 6; ++d)
            (*pds[d])(s);
    }

    // Collect results.
    for (int d = 0; d < 6; ++d) {
        float hz = pds[d]->get_frequency();
        if (hz > 0.0f) {
            out[d].active = 1;
            out[d].hz     = hz;
        }
    }
}
