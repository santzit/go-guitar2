/// q_bridge.cpp — C wrapper around cycfi/q pitch_detector.
///
/// Exposes a plain-C API so Rust FFI can call into Q's C++ pitch-detection
/// without touching name-mangled symbols.
///
/// Build requirements:
///   C++20, include paths:
///     extern/q/q_lib/include  (or extern/q/include for older layout)
///     extern/infra/include

#include "q_bridge.h"

#include <q/pitch/pitch_detector.hpp>
#include <q/support/literals.hpp>

namespace q = cycfi::q;

// Build a cycfi::q::decibel from a runtime float value.
// The decibel(double) constructor is deleted in newer Q; use the
// unit base-class constructor that takes a (value, direct_unit_type) pair.
static inline q::decibel make_decibel(float db_val)
{
    return q::decibel{ static_cast<double>(db_val), q::direct_unit_type{} };
}

// Internal struct wrapping the Q pitch_detector.
struct QPitchDetector {
    q::pitch_detector pd;

    QPitchDetector(float min_hz, float max_hz,
                   uint32_t sps, float hysteresis_db)
        : pd(q::frequency(min_hz), q::frequency(max_hz),
             static_cast<float>(sps),
             make_decibel(hysteresis_db))
    {}
};

extern "C" {

QPitchDetector* q_pd_create(float min_freq, float max_freq,
                              uint32_t sample_rate, float hysteresis_db)
{
    try {
        return new QPitchDetector(min_freq, max_freq, sample_rate, hysteresis_db);
    } catch (...) {
        return nullptr;
    }
}

void q_pd_destroy(QPitchDetector* pd)
{
    delete pd;
}

bool q_pd_process(QPitchDetector* pd, float sample)
{
    if (!pd) return false;
    return pd->pd(sample);
}

float q_pd_get_frequency(QPitchDetector* pd)
{
    if (!pd) return 0.0f;
    return pd->pd.get_frequency();
}

float q_pd_get_periodicity(QPitchDetector* pd)
{
    if (!pd) return 0.0f;
    return pd->pd.periodicity();
}

} // extern "C"
