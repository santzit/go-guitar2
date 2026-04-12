/// audio-mixer — Audio bus mixer: gains, mutes, solos, ducking, limiter.
///
/// Wraps `gg-mixer` and exposes a stable API used by both the one-shot
/// `AudioEngine` (offline decode + apply) and the RT `audio-engine` thread.
///
/// Utilities provided:
/// - Re-exports of core `gg-mixer` types (`BusId`, `BUS_COUNT`, `Mixer`, `MixInput`).
/// - `mix_pcm_buffer` — applies the mixer state to an already-decoded PCM-16 buffer.
/// - `bus_id_from_index` — converts a `usize` bus index to the typed `BusId` enum.

pub use gg_mixer::{BusId, BUS_COUNT, MixInput, Mixer};

/// Apply the current mixer state to a PCM-16 LE buffer in place.
///
/// `pcm`      — interleaved signed-16-LE samples (modified in place).
/// `channels` — number of interleaved channels (usually 2 for stereo).
/// `mixer`    — the `gg_mixer::Mixer` instance whose gains/mutes to apply.
pub fn mix_pcm_buffer(pcm: &mut Vec<u8>, channels: usize, mixer: &mut Mixer) {
    if pcm.is_empty() {
        return;
    }
    let frame_bytes = channels.max(1) * 2;
    for frame in pcm.chunks_exact_mut(frame_bytes) {
        for sample_bytes in frame.chunks_exact_mut(2) {
            let s_i16 = i16::from_le_bytes([sample_bytes[0], sample_bytes[1]]);
            let s_f32 = s_i16 as f32 / 32_768.0;
            let mixed = mixer.mix_sample(MixInput {
                music: s_f32,
                ..Default::default()
            });
            let out = (mixed.clamp(-1.0, 1.0) * 32_767.0) as i16;
            let out_bytes = out.to_le_bytes();
            sample_bytes[0] = out_bytes[0];
            sample_bytes[1] = out_bytes[1];
        }
    }
}

/// Convert a `usize` bus index to the typed `BusId` enum.
/// Returns `None` for out-of-range indices.
pub fn bus_id_from_index(idx: usize) -> Option<BusId> {
    use BusId::*;
    match idx {
        0 => Some(Ui),
        1 => Some(Music),
        2 => Some(LeadGuitarStem),
        3 => Some(RhythmGuitarStem),
        4 => Some(BassStem),
        5 => Some(PlayerInstrument),
        6 => Some(Master),
        7 => Some(Metronome),
        8 => Some(MicRoom),
        _ => None,
    }
}
