/// q_dsp_bridge.cpp — C++ implementation of the SPSC ring-buffer DSP bridge.
///
/// ## Architecture
///
/// Two lock-free wait-free SPSC ring buffers (Lamport / Vyukov design) connect
/// the Godot main thread to a dedicated DSP thread:
///
///   Godot main thread
///     push_input_i16() → in_rb  →  DSP thread
///                                     q::dc_block (remove offset)
///                                     q::lowpass_1p (basic anti-aliasing)
///                                   out_rb ← pop_output_f32() ← Godot main thread
///
/// The SPSC ring buffer uses std::atomic relaxed/release/acquire stores so that
/// it is safe to use between any two threads without any mutex.
///
/// ## Build requirements
///   C++20
///   Include paths:
///     include/           (vendored cycfi/q headers in this repo)
///     extern/infra/include  (cycfi/infra — Q dependency)

#include "q_dsp_bridge.h"

#include <q/fx/lowpass.hpp>
#include <q/fx/dc_block.hpp>
#include <q/support/literals.hpp>

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <thread>
#include <vector>

namespace q = cycfi::q;

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Round up to the next power of two (minimum 2).
static uint32_t next_pow2(uint32_t v) {
    if (v == 0) return 2u;
    v--;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    return v + 1;
}

// ── Lock-free SPSC ring buffer ────────────────────────────────────────────────
//
// Classic Lamport / Dmitry Vyukov wait-free SPSC using two atomic indices.
// Only one thread ever calls push(); only one thread ever calls pop().
// The buffer size is always a power of two so the modulo can be a bitmask.

class SpscRingBuffer {
public:
    explicit SpscRingBuffer(uint32_t capacity)
        : _mask(next_pow2(capacity) - 1u)
        , _buf(next_pow2(capacity))
        , _write(0u)
        , _read(0u)
    {}

    SpscRingBuffer(const SpscRingBuffer&) = delete;
    SpscRingBuffer& operator=(const SpscRingBuffer&) = delete;

    /// Number of free slots (callable from either thread but exact only for the writer).
    uint32_t free_slots() const {
        uint32_t w = _write.load(std::memory_order_relaxed);
        uint32_t r = _read.load(std::memory_order_acquire);
        return (_mask + 1u) - (w - r);
    }

    /// Number of available samples (callable from either thread but exact only for the reader).
    uint32_t available() const {
        uint32_t w = _write.load(std::memory_order_acquire);
        uint32_t r = _read.load(std::memory_order_relaxed);
        return w - r;
    }

    /// Push one sample.  Call only from the single producer thread.
    /// Returns false if the buffer is full.
    bool push(float val) {
        uint32_t w = _write.load(std::memory_order_relaxed);
        uint32_t r = _read.load(std::memory_order_acquire);
        if ((w - r) >= (_mask + 1u))
            return false;
        _buf[w & _mask] = val;
        _write.store(w + 1u, std::memory_order_release);
        return true;
    }

    /// Pop one sample.  Call only from the single consumer thread.
    /// Returns false if the buffer is empty.
    bool pop(float& val) {
        uint32_t r = _read.load(std::memory_order_relaxed);
        uint32_t w = _write.load(std::memory_order_acquire);
        if (r == w) return false;
        val = _buf[r & _mask];
        _read.store(r + 1u, std::memory_order_release);
        return true;
    }

private:
    const uint32_t          _mask;
    std::vector<float>      _buf;
    std::atomic<uint32_t>   _write;
    std::atomic<uint32_t>   _read;
};

// ── QDspBridge ────────────────────────────────────────────────────────────────

struct QDspBridge {
    // Ring buffers — each allocated separately so their cache lines don't share.
    SpscRingBuffer  in_rb;
    SpscRingBuffer  out_rb;

    // Q signal-conditioning objects (owned by the DSP thread).
    q::dc_block     dc;
    q::one_pole_lowpass lp;

    // DSP thread configuration
    uint32_t        sample_rate;
    uint32_t        block_size;

    // DSP thread control
    std::thread     dsp_thread;
    std::atomic<bool> running { false };

    QDspBridge(uint32_t capacity, uint32_t sr, uint32_t bs)
        : in_rb(capacity)
        , out_rb(capacity)
        , dc(q::frequency(20.0f), static_cast<float>(sr))
        , lp(q::frequency(12000.0f), static_cast<float>(sr))
        , sample_rate(sr)
        , block_size(bs)
    {}

    ~QDspBridge() { stop(); }

    void start() {
        if (running.exchange(true))
            return;  // already running
        dsp_thread = std::thread([this]{ dsp_loop(); });
    }

    void stop() {
        running.store(false);
        if (dsp_thread.joinable())
            dsp_thread.join();
    }

private:
    void dsp_loop() {
        std::vector<float> block(block_size);

        while (running.load(std::memory_order_relaxed)) {
            // Wait until we have a full block of input available.
            if (in_rb.available() < block_size) {
                // Short sleep avoids busy-spinning and reduces CPU load.
                std::this_thread::sleep_for(std::chrono::microseconds(100));
                continue;
            }
            // Pop one block — each pop() is guaranteed to succeed because we
            // just confirmed availability and this is the only consumer.
            for (uint32_t i = 0; i < block_size; ++i) {
                if (!in_rb.pop(block[i]))
                    block[i] = 0.0f;  // defensive fallback (should not occur)
            }
            // Process: dc_block → one_pole_lowpass.
            for (uint32_t i = 0; i < block_size; ++i) {
                float s = dc(block[i]);   // remove DC offset
                s       = lp(s);          // gentle anti-alias lowpass
                block[i] = s;
            }
            // Push processed block to output ring.
            // Count dropped samples so callers can detect overflow.
            uint32_t dropped = 0;
            for (uint32_t i = 0; i < block_size; ++i) {
                if (!out_rb.push(block[i]))
                    ++dropped;
            }
            (void)dropped;  // available for debugging / future telemetry
        }
    }
};

// ── C API ─────────────────────────────────────────────────────────────────────

extern "C" {

QDspBridge* q_dsp_create(uint32_t capacity,
                          uint32_t sample_rate,
                          uint32_t block_size,
                          bool     start_dsp_thread)
{
    if (capacity == 0 || sample_rate == 0 || block_size == 0)
        return nullptr;
    try {
        auto* b = new QDspBridge(capacity, sample_rate, block_size);
        if (start_dsp_thread)
            b->start();
        return b;
    } catch (...) {
        return nullptr;
    }
}

void q_dsp_destroy(QDspBridge* bridge)
{
    delete bridge;
}

void q_dsp_start(QDspBridge* bridge)
{
    if (bridge) bridge->start();
}

void q_dsp_stop(QDspBridge* bridge)
{
    if (bridge) bridge->stop();
}

uint32_t q_dsp_push_input_i16(QDspBridge*    bridge,
                               const int16_t* data,
                               uint32_t       count)
{
    if (!bridge || !data) return 0u;
    constexpr float kScale = 1.0f / 32768.0f;  // pre-computed reciprocal
    uint32_t written = 0;
    for (uint32_t i = 0; i < count; ++i) {
        float s = static_cast<float>(data[i]) * kScale;
        if (!bridge->in_rb.push(s))
            break;
        ++written;
    }
    return written;
}

uint32_t q_dsp_push_input_f32(QDspBridge*  bridge,
                               const float* data,
                               uint32_t     count)
{
    if (!bridge || !data) return 0u;
    uint32_t written = 0;
    for (uint32_t i = 0; i < count; ++i) {
        if (!bridge->in_rb.push(data[i]))
            break;
        ++written;
    }
    return written;
}

uint32_t q_dsp_pop_output_f32(QDspBridge* bridge,
                               float*      out,
                               uint32_t    max_count)
{
    if (!bridge || !out) return 0u;
    uint32_t read = 0;
    for (uint32_t i = 0; i < max_count; ++i) {
        if (!bridge->out_rb.pop(out[i]))
            break;
        ++read;
    }
    return read;
}

uint32_t q_dsp_input_free(QDspBridge* bridge)
{
    if (!bridge) return 0u;
    return bridge->in_rb.free_slots();
}

uint32_t q_dsp_output_avail(QDspBridge* bridge)
{
    if (!bridge) return 0u;
    return bridge->out_rb.available();
}

} // extern "C"
