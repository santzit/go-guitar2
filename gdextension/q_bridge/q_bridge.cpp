/// q_bridge.cpp — C wrapper around cycfi/q pitch_detector.
///
/// Exposes a plain-C API so Rust FFI can call into Q's C++ pitch-detection
/// without touching name-mangled symbols.
///
/// Build requirements:
///   C++17, include paths:
///     extern/q/include
///     extern/infra/include

#include "q_bridge.h"

#include <q/fx/pitch_detector.hpp>

namespace q = cycfi::q;

// Internal struct that pairs the Q pitch_detector with its cached periodicity.
struct QPitchDetector {
    q::pitch_detector pd;
    float             cached_periodicity;

    QPitchDetector(float min_hz, float max_hz,
                   uint32_t sps, float hysteresis_db)
        : pd(q::frequency(min_hz), q::frequency(max_hz),
             sps, q::decibel(hysteresis_db))
        , cached_periodicity(0.0f)
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
    float periodicity = 0.0f;
    q::frequency freq = pd->pd.get_frequency(periodicity);
    pd->cached_periodicity = periodicity;
    return static_cast<float>(double(freq));
}

float q_pd_get_periodicity(QPitchDetector* pd)
{
    if (!pd) return 0.0f;
    return pd->cached_periodicity;
}

} // extern "C"
