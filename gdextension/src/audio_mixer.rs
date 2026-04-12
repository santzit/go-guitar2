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
    if channels > 2 {
        // Multi-channel MAIN WEMs can contain stems per channel.
        // Route channels to stem buses, then downmix to stereo PCM-16.
        let in_channels = channels;
        let frame_bytes = in_channels * 2;
        let frames      = pcm.len() / frame_bytes;
        let mut out     = Vec::with_capacity(frames * 2 * 2);

        for frame in pcm.chunks_exact(frame_bytes) {
            let sample_for = |idx: usize| -> f32 {
                if idx >= in_channels {
                    return 0.0;
                }
                let off = idx * 2;
                if off + 1 >= frame.len() {
                    return 0.0;
                }
                let s_i16 = i16::from_le_bytes([frame[off], frame[off + 1]]);
                s_i16 as f32 / 32_768.0
            };

            let mut music = sample_for(0);
            if in_channels > 4 {
                // Extra channels are folded into the "music/other" stem.
                for ch in 4..in_channels {
                    music += sample_for(ch);
                }
            }

            let mixed = mixer.mix_sample(MixInput {
                music,
                lead_guitar_stem:   sample_for(1),
                rhythm_guitar_stem: sample_for(2),
                bass_stem:          sample_for(3),
                ..Default::default()
            });
            let out_i16 = (mixed.clamp(-1.0, 1.0) * 32_767.0) as i16;
            let out_b   = out_i16.to_le_bytes();
            // AudioStreamWAV supports mono/stereo. Keep stereo output.
            out.extend_from_slice(&out_b);
            out.extend_from_slice(&out_b);
        }

        *pcm = out;
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

#[cfg(test)]
mod tests {
    use super::*;

    fn pcm_frame_i16(samples: &[i16]) -> Vec<u8> {
        let mut out = Vec::with_capacity(samples.len() * 2);
        for s in samples {
            out.extend_from_slice(&s.to_le_bytes());
        }
        out
    }

    fn first_sample_i16(pcm: &[u8]) -> i16 {
        i16::from_le_bytes([pcm[0], pcm[1]])
    }

    #[test]
    fn multi_channel_routing_maps_lead_stem_to_lead_bus() {
        let mut mixer = Mixer::new();
        mixer.set_mute(BusId::Music, true);
        mixer.set_mute(BusId::RhythmGuitarStem, true);
        mixer.set_mute(BusId::BassStem, true);

        let mut pcm = pcm_frame_i16(&[0, 10_000, 0, 0]); // 4ch: music, lead, rhythm, bass
        mix_pcm_buffer(&mut pcm, 4, &mut mixer);

        assert_eq!(pcm.len(), 4); // downmixed stereo (1 frame x 2ch x 2 bytes)
        assert!(first_sample_i16(&pcm).abs() > 0);
    }

    #[test]
    fn multi_channel_routing_maps_music_stem_to_music_bus() {
        let mut mixer = Mixer::new();
        mixer.set_mute(BusId::LeadGuitarStem, true);
        mixer.set_mute(BusId::RhythmGuitarStem, true);
        mixer.set_mute(BusId::BassStem, true);

        let mut pcm = pcm_frame_i16(&[10_000, 0, 0, 0]); // 4ch: music, lead, rhythm, bass
        mix_pcm_buffer(&mut pcm, 4, &mut mixer);
        assert!(first_sample_i16(&pcm).abs() > 0);

        let mut muted = Mixer::new();
        muted.set_mute(BusId::Music, true);
        muted.set_mute(BusId::LeadGuitarStem, true);
        muted.set_mute(BusId::RhythmGuitarStem, true);
        muted.set_mute(BusId::BassStem, true);
        let mut pcm_muted = pcm_frame_i16(&[10_000, 0, 0, 0]);
        mix_pcm_buffer(&mut pcm_muted, 4, &mut muted);
        assert_eq!(first_sample_i16(&pcm_muted), 0);
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
