/// psarc_parser.rs — Pure-Rust PSARC/SNG parsing using santzit/Rocksmith2014.rs.
///
/// Uses `rocksmith2014-psarc` and `rocksmith2014-sng` Rust crates directly —
/// no .NET runtime, no NativeAOT shim, no CLR hosting required.
use std::collections::{HashMap, HashSet};
use std::fs::File;

use godot::prelude::godot_print;
use godot::prelude::godot_warn;
use rocksmith2014_sng::{BeatMask, NoteMask};
pub use rocksmith2014_sng::Platform;
use serde_json::Value;

/// A parsed note extracted from the SNG arrangement.
#[derive(Clone, Debug)]
pub struct NoteEntry {
    pub time: f32,
    pub fret: i8,
    pub string_index: i8,
    pub sustain: f32,
    pub hand_shape_id: i32,
    pub hand_shape_chord_id: i32,
    pub hand_shape_min_fret: i8,
    pub hand_shape_max_fret: i8,
    pub hand_shape_min_string: i8,
    pub hand_shape_max_string: i8,
}

#[derive(Clone, Debug)]
pub struct BeatEntry {
    pub time: f32,
    pub measure: i16,
    pub beat: i16,
    pub is_bar: bool,
}

#[derive(Clone, Debug)]
pub struct ChordTemplateEntry {
    pub id: i32,
    pub name: String,
    pub frets: [i8; 6],
    pub fingers: [i8; 6],
}

#[derive(Clone, Debug)]
pub struct HandShapeEntry {
    pub level_difficulty: i32,
    pub chord_id: i32,
    pub start_time: f32,
    pub end_time: f32,
    pub first_note_time: f32,
    pub last_note_time: f32,
    pub min_fret: i8,
    pub max_fret: i8,
    pub min_string: i8,
    pub max_string: i8,
}

#[derive(Clone, Debug)]
pub struct PhraseEntry {
    pub id: i32,
    pub name: String,
    pub max_difficulty: i32,
    pub iteration_count: i32,
    pub solo: i8,
}

#[derive(Clone, Debug)]
pub struct PhraseIterationEntry {
    pub phrase_id: i32,
    pub start_time: f32,
    pub end_time: f32,
    pub easy: i32,
    pub medium: i32,
    pub hard: i32,
}

#[derive(Clone, Debug)]
pub struct LevelEntry {
    pub difficulty: i32,
    pub notes_count: i32,
    pub hand_shapes_count: i32,
    pub anchors_count: i32,
}

/// Parsed PSARC contents: notes from the lead (or highest-difficulty) arrangement,
/// the full-length MAIN WEM for gameplay, and the short PREVIEW WEM for the song list.
pub struct PsarcData {
    pub notes: Vec<NoteEntry>,
    pub beats: Vec<BeatEntry>,
    pub chord_templates: Vec<ChordTemplateEntry>,
    pub hand_shapes: Vec<HandShapeEntry>,
    pub phrases: Vec<PhraseEntry>,
    pub phrase_iterations: Vec<PhraseIterationEntry>,
    pub levels: Vec<LevelEntry>,
    /// Full-length backing track (MAIN role) used in the gameplay scene.
    pub wem_bytes: Option<Vec<u8>>,
    /// Short preview clip (PREVIEW role) used in the song-list scene.
    pub preview_wem_bytes: Option<Vec<u8>>,
    /// SNG arrangement start time (seconds from WEM position 0).
    /// Note times are already absolute from WEM position 0, so this is
    /// informational only — no offset needs to be applied during playback.
    pub sng_start_time: f32,
    /// SNG difficulty index of the selected level (== metadata.max_difficulty).
    pub sng_difficulty: i32,
    /// Raw capo_fret_id from SNG metadata.  Rocksmith 2014 has no capo feature;
    /// this field is unreliable in CDLCs (-1 = unset, 0 = no capo, >0 = frets
    /// already physical/baked).  It is exposed for diagnostics only — fret values
    /// in `notes` are always physical and must be used as-is with no offset.
    pub sng_capo: i8,
    /// Per-string tuning offsets in semitones from standard E-A-D-G-B-e tuning.
    /// An all-zero (or empty) vector means standard tuning.
    pub sng_tuning: Vec<i16>,
    /// Count of linked difficulty levels referenced by phrase iterations.
    /// `> 1` means Dynamic Difficulty is present.
    pub sng_difficulty_count: i32,
    /// True when the arrangement uses Dynamic Difficulty progression.
    pub sng_is_dynamic_difficulty: bool,
    /// SNG-reported song length in seconds (fallback metadata).
    pub sng_song_length: f32,
    /// Song title extracted from PSARC metadata when available.
    pub song_title: String,
    /// Artist name extracted from PSARC metadata when available.
    pub song_artist: String,
    /// Album/song year extracted from PSARC metadata when available.
    pub song_year: i32,
    /// Arrangement presence flags from SNG entries inside PSARC.
    pub has_lead: bool,
    pub has_rhythm: bool,
    pub has_bass: bool,
}

impl PsarcData {
    /// Open and fully parse a `.psarc` file.
    ///
    /// 1. Finds the lead SNG arrangement (or any non-vocals SNG if no lead exists).
    /// 2. Decrypts and parses the SNG to extract notes from the highest difficulty level.
    /// 3. Parses every `.bnk` (Wwise SoundBank) to build a WEM-ID → role map
    ///    (MAIN vs PREVIEW).  Banks whose name contains `_preview` reference preview
    ///    WEM IDs; all other banks reference main WEM IDs.  MAIN takes priority when
    ///    the same ID appears in both.
    /// 4. Classifies every `.wem` entry using the role map and returns the largest
    ///    MAIN WEM as `wem_bytes` and the largest PREVIEW WEM as `preview_wem_bytes`.
    /// `difficulty_band` selects which of the three DDC difficulty bands to play:
    ///   0 = Easy, 1 = Medium, 2 = Hard / 100% (default).
    /// Each SNG `PhraseIteration` carries `difficulty[3]` = [easy_level, medium_level, hard_level].
    /// Notes are assembled per-phrase using the level index at `difficulty[difficulty_band]`.
    pub fn open(path: &str, difficulty_band: usize) -> Result<Self, Box<dyn std::error::Error>> {
        let file = File::open(path).map_err(|e| format!("Failed to open '{}': {}", path, e))?;

        let mut psarc = rocksmith2014_psarc::Psarc::read(file)
            .map_err(|e| format!("Failed to parse PSARC '{}': {}", path, e))?;

        let manifest = psarc.manifest().to_vec();
        let manifest_lc: Vec<String> = manifest.iter().map(|m| m.to_ascii_lowercase()).collect();
        let has_lead = manifest_lc
            .iter()
            .any(|n| n.ends_with(".sng") && n.contains("lead") && !n.contains("vocals"));
        let has_rhythm = manifest_lc
            .iter()
            .any(|n| n.ends_with(".sng") && n.contains("rhythm") && !n.contains("vocals"));
        let has_bass = manifest_lc
            .iter()
            .any(|n| n.ends_with(".sng") && n.contains("bass") && !n.contains("vocals"));

        let (song_title, song_artist, song_year) = extract_hsan_metadata(&mut psarc, &manifest);

        // ── Find SNG arrangement ──────────────────────────────────────────────
        // Preference: lead > rhythm > bass > any non-vocals SNG
        let sng_name = manifest
            .iter()
            .filter(|n| n.ends_with(".sng") && !n.contains("vocals"))
            .max_by_key(|n| {
                let lc = n.to_ascii_lowercase();
                if lc.ends_with("_lead.sng") {
                    4
                } else if lc.contains("lead") {
                    3
                } else if lc.contains("rhythm") {
                    2
                } else if lc.contains("bass") {
                    1
                } else {
                    0
                }
            })
            .cloned();

        let (
            notes,
            beats,
            chord_templates,
            hand_shapes,
            phrases,
            phrase_iterations,
            levels,
            sng_start_time,
            sng_difficulty,
            sng_capo,
            sng_tuning,
            sng_difficulty_count,
            sng_is_dynamic_difficulty,
            sng_song_length,
        ) = if let Some(ref name) = sng_name {
            let encrypted = psarc
                .inflate_file(name)
                .map_err(|e| format!("Failed to inflate SNG '{}': {}", name, e))?;

            let sng = rocksmith2014_sng::Sng::from_encrypted(&encrypted, Platform::Pc)
                // Platform::Pc is correct for all official Rocksmith 2014 PC/Windows DLC.
                // Mac DLC uses Platform::Mac (different AES key) and is not supported here.
                .map_err(|e| format!("Failed to decrypt SNG '{}': {}", name, e))?;

            let max_diff = sng.metadata.max_difficulty;
            let start_time = sng.metadata.start_time;
            // capo_fret_id is diagnostic only — Rocksmith 2014 has no capo support.
            // The field is typically 0 or -1.  Frets in the SNG are physical (absolute).
            let capo = sng.metadata.capo_fret_id;
            let tuning = sng.metadata.tuning.clone();
            let song_length = sng.metadata.song_length;
            let beats: Vec<BeatEntry> = sng
                .beats
                .iter()
                .map(|b| BeatEntry {
                    time: b.time,
                    measure: b.measure,
                    beat: b.beat,
                    is_bar: b.mask.contains(BeatMask::FIRST_BEAT_OF_MEASURE) || b.measure >= 0,
                })
                .collect();

            let cstr = |bytes: &[u8]| -> String {
                let end = bytes.iter().position(|b| *b == 0).unwrap_or(bytes.len());
                String::from_utf8_lossy(&bytes[..end]).trim().to_string()
            };

            let chord_templates: Vec<ChordTemplateEntry> = sng
                .chords
                .iter()
                .enumerate()
                .map(|(idx, c)| ChordTemplateEntry {
                    id: idx as i32,
                    name: cstr(&c.name),
                    frets: c.frets,
                    fingers: c.fingers,
                })
                .collect();

            let phrases: Vec<PhraseEntry> = sng
                .phrases
                .iter()
                .enumerate()
                .map(|(idx, p)| PhraseEntry {
                    id: idx as i32,
                    name: cstr(&p.name),
                    max_difficulty: p.max_difficulty,
                    iteration_count: p.iteration_count,
                    solo: p.solo,
                })
                .collect();

            let phrase_iterations: Vec<PhraseIterationEntry> = sng
                .phrase_iterations
                .iter()
                .map(|pi| PhraseIterationEntry {
                    phrase_id: pi.phrase_id,
                    start_time: pi.start_time,
                    end_time: pi.end_time,
                    easy: pi.difficulty[0],
                    medium: pi.difficulty[1],
                    hard: pi.difficulty[2],
                })
                .collect();

            let levels: Vec<LevelEntry> = sng
                .levels
                .iter()
                .map(|lvl| LevelEntry {
                    difficulty: lvl.difficulty,
                    notes_count: lvl.notes.len() as i32,
                    hand_shapes_count: lvl.hand_shapes.len() as i32,
                    anchors_count: lvl.anchors.len() as i32,
                })
                .collect();

            // ── Assemble notes via phrase-iteration difficulty bands ──────────────
            //
            // Rocksmith DDC (Dynamic Difficulty Creator) stores each difficulty
            // level as a SELF-CONTAINED, non-additive snapshot.  Levels must NEVER
            // be summed.  The "100% / master" arrangement is NOT a single flat level;
            // it is assembled phrase-by-phrase:
            //
            //   Each PhraseIteration carries  difficulty[3] = [easy, medium, hard].
            //   For the requested difficulty_band (0=Easy, 1=Medium, 2=Hard/100%),
            //   we look up the corresponding level index and extract only the notes
            //   whose timestamps fall within that phrase iteration's [start, end).
            //
            // This correctly reproduces Rocksmith's own behaviour: different song
            // sections can live at different SNG levels even at "maximum difficulty",
            // which is why a flat "level with most notes" strategy always under-counts.
            //
            // Examples with difficulty_band=2 (Hard/100%):
            //   Love Is a Long Road  – flat level 15 gives 729 notes,
            //                          phrase assembly gives 1046 (all correct).
            //   Runnin' Down a Dream – flat level 4 gives 582,
            //                          phrase assembly gives 1214.
            let total_levels = sng.levels.len();
            let total_phrase_iters = sng.phrase_iterations.len();
            let diff_band = difficulty_band.min(2); // clamp to valid band index

            let (difficulty_count, is_dynamic_difficulty) = if !sng.phrase_iterations.is_empty() {
                let mut linked_levels: HashSet<i32> = HashSet::new();
                for pi in &sng.phrase_iterations {
                    for &linked in &pi.difficulty {
                        if linked >= 0 {
                            linked_levels.insert(linked);
                        }
                    }
                }
                let count = linked_levels.len() as i32;
                let count = if count > 0 { count } else { 1 };
                (count, count > 1)
            } else {
                (1, false)
            };

            godot_print!(
                "rsapi: SNG levels={} phrase_iters={} difficulty_band={} max_difficulty_meta={} difficulty_count={} is_dynamic_difficulty={}",
                total_levels,
                total_phrase_iters,
                diff_band,
                max_diff,
                difficulty_count,
                is_dynamic_difficulty
            );

            // Helper closure: push one SNG note event into `entries`.
            // Skips IGNORE notes.  Expands chord events into per-string NoteEntries.
            // SNG frets are always physical (absolute) — no capo offset is applied.
            let mut entries: Vec<NoteEntry> = Vec::new();

            let hand_shape_fret_span = |chord_id: i32| -> Option<(i8, i8, i8, i8)> {
                if chord_id < 0 {
                    return None;
                }
                let chord = sng.chords.get(chord_id as usize)?;
                let mut min_fret: i8 = i8::MAX;
                let mut max_fret: i8 = i8::MIN;
                let mut min_string: i8 = i8::MAX;
                let mut max_string: i8 = i8::MIN;
                for s in 0i8..6 {
                    let fret = chord.frets[s as usize];
                    if fret < 0 {
                        continue;
                    }
                    min_fret = min_fret.min(fret);
                    max_fret = max_fret.max(fret);
                    min_string = min_string.min(s);
                    max_string = max_string.max(s);
                }
                if min_fret == i8::MAX {
                    None
                } else {
                    Some((min_fret, max_fret, min_string, max_string))
                }
            };

            let hand_shapes: Vec<HandShapeEntry> = sng
                .levels
                .iter()
                .flat_map(|lvl| {
                    lvl.hand_shapes.iter().map(|fp| {
                        let (min_fret, max_fret, min_string, max_string) =
                            hand_shape_fret_span(fp.chord_id).unwrap_or((-1, -1, -1, -1));
                        HandShapeEntry {
                            level_difficulty: lvl.difficulty,
                            chord_id: fp.chord_id,
                            start_time: fp.start_time,
                            end_time: fp.end_time,
                            first_note_time: fp.first_note_time,
                            last_note_time: fp.last_note_time,
                            min_fret,
                            max_fret,
                            min_string,
                            max_string,
                        }
                    })
                })
                .collect();

            let find_hand_shape = |hand_shapes: &[rocksmith2014_sng::FingerPrint],
                                   note_time: f32|
             -> Option<(i32, i32, i8, i8, i8, i8)> {
                let hs = hand_shapes
                    .iter()
                    .enumerate()
                    .find(|(_, fp)| note_time >= fp.start_time && note_time <= fp.end_time)?;
                let hand_shape_id = hs.0 as i32;
                let hand_shape_chord_id = hs.1.chord_id;
                let (min_fret, max_fret, min_string, max_string) =
                    hand_shape_fret_span(hand_shape_chord_id).unwrap_or((-1, -1, -1, -1));
                Some((
                    hand_shape_id,
                    hand_shape_chord_id,
                    min_fret,
                    max_fret,
                    min_string,
                    max_string,
                ))
            };

            let push_note =
                |entries: &mut Vec<NoteEntry>,
                 n: &rocksmith2014_sng::Note,
                 chords: &[rocksmith2014_sng::Chord],
                 hand_shapes: &[rocksmith2014_sng::FingerPrint]| {
                    // Skip notes flagged as IGNORE — never scored or displayed.
                    // HIGH_DENSITY notes must NOT be skipped: they are genuine playable
                    // notes required at higher difficulties.
                    if n.mask.contains(NoteMask::IGNORE) {
                        return;
                    }
                    let hand_shape_meta =
                        find_hand_shape(hand_shapes, n.time).unwrap_or((-1, -1, -1, -1, -1, -1));
                    if n.chord_id >= 0 {
                        // Chord event: expand per-string frets from the chord template.
                        // chord_id is authoritative (sng_to_xml reference confirms this).
                        if let Some(chord) = chords.get(n.chord_id as usize) {
                            for s in 0i8..6 {
                                let raw_fret = chord.frets[s as usize];
                                if raw_fret < 0 {
                                    continue;
                                } // -1 = string not played
                                entries.push(NoteEntry {
                                    time: n.time,
                                    fret: raw_fret,
                                    string_index: s,
                                    sustain: n.sustain,
                                    hand_shape_id: hand_shape_meta.0,
                                    hand_shape_chord_id: hand_shape_meta.1,
                                    hand_shape_min_fret: hand_shape_meta.2,
                                    hand_shape_max_fret: hand_shape_meta.3,
                                    hand_shape_min_string: hand_shape_meta.4,
                                    hand_shape_max_string: hand_shape_meta.5,
                                });
                            }
                        }
                    } else {
                        // Single note: use fret/string directly from the note record.
                        entries.push(NoteEntry {
                            time: n.time,
                            fret: n.fret,
                            string_index: n.string_index,
                            sustain: n.sustain,
                            hand_shape_id: hand_shape_meta.0,
                            hand_shape_chord_id: hand_shape_meta.1,
                            hand_shape_min_fret: hand_shape_meta.2,
                            hand_shape_max_fret: hand_shape_meta.3,
                            hand_shape_min_string: hand_shape_meta.4,
                            hand_shape_max_string: hand_shape_meta.5,
                        });
                    }
                };

            if !sng.phrase_iterations.is_empty() && is_dynamic_difficulty {
                // ── Phrase-iteration assembly (primary path) ─────────────────────
                let mut selected_difficulty = 0i32;
                for pi in &sng.phrase_iterations {
                    let t_start = pi.start_time;
                    let t_end = pi.end_time;
                    let band_d = pi.difficulty[diff_band]; // level index for this phrase at the requested band
                    if band_d > selected_difficulty {
                        selected_difficulty = band_d;
                    }

                    let lvl = match sng.levels.iter().find(|l| l.difficulty == band_d) {
                        Some(l) => l,
                        None => continue,
                    };
                    for n in &lvl.notes {
                        if n.time < t_start || n.time >= t_end {
                            continue;
                        }
                        push_note(&mut entries, n, &sng.chords, &lvl.hand_shapes);
                    }
                }
                godot_print!(
                    "rsapi: phrase-assembly complete — {} note_events (max band_d={})",
                    entries.len(),
                    selected_difficulty
                );
                (
                    entries,
                    beats,
                    chord_templates,
                    hand_shapes,
                    phrases,
                    phrase_iterations,
                    levels,
                    start_time,
                    selected_difficulty,
                    capo,
                    tuning,
                    difficulty_count,
                    is_dynamic_difficulty,
                    song_length,
                )
            } else if !sng.phrase_iterations.is_empty() {
                // ── Static arrangement with phraseIterations ─────────────────────
                // Some "normal" files keep phrase iterations but link every phrase
                // to the same difficulty. Building phrase-by-phrase can over-count
                // when phrase windows overlap, so load the linked level once.
                let selected_difficulty = sng
                    .phrase_iterations
                    .iter()
                    .map(|pi| pi.difficulty[diff_band])
                    .filter(|d| *d >= 0)
                    .max()
                    .unwrap_or(max_diff);

                let linked_level = sng
                    .levels
                    .iter()
                    .find(|l| l.difficulty == selected_difficulty)
                    .or_else(|| sng.levels.iter().max_by_key(|l| l.notes.len()));

                match linked_level {
                    Some(lvl) => {
                        for n in &lvl.notes {
                            push_note(&mut entries, n, &sng.chords, &lvl.hand_shapes);
                        }
                        godot_print!(
                            "rsapi: static arrangement level {} — {} note_events",
                            lvl.difficulty,
                            entries.len()
                        );
                        (
                            entries,
                            beats,
                            chord_templates,
                            hand_shapes,
                            phrases,
                            phrase_iterations,
                            levels,
                            start_time,
                            lvl.difficulty,
                            capo,
                            tuning,
                            difficulty_count,
                            is_dynamic_difficulty,
                            song_length,
                        )
                    }
                    None => {
                        godot_warn!("rsapi: static SNG has no levels at all");
                        (
                            Vec::new(),
                            beats,
                            chord_templates,
                            hand_shapes,
                            phrases,
                            phrase_iterations,
                            levels,
                            start_time,
                            max_diff,
                            capo,
                            tuning,
                            difficulty_count,
                            is_dynamic_difficulty,
                            song_length,
                        )
                    }
                }
            } else {
                // ── No phraseIterations: pick a level by difficulty index ────────
                // Avoid "max-note" heuristics: they can inflate note/chord counts.
                // We instead select the level closest to the requested difficulty band.
                let desired_difficulty = match diff_band {
                    0 => 0,
                    1 => (max_diff / 2).max(0),
                    _ => max_diff,
                };
                let selected = sng
                    .levels
                    .iter()
                    .min_by_key(|lvl| {
                        let dist = (lvl.difficulty - desired_difficulty).abs();
                        (dist, -lvl.difficulty)
                    });
                match selected {
                    Some(lvl) => {
                        for n in &lvl.notes {
                            push_note(&mut entries, n, &sng.chords, &lvl.hand_shapes);
                        }
                        godot_warn!(
                            "rsapi: no phraseIterations — using difficulty-indexed level {} (target={})",
                            lvl.difficulty,
                            desired_difficulty
                        );
                        (
                            entries,
                            beats,
                            chord_templates,
                            hand_shapes,
                            phrases,
                            phrase_iterations,
                            levels,
                            start_time,
                            lvl.difficulty,
                            capo,
                            tuning,
                            difficulty_count,
                            is_dynamic_difficulty,
                            song_length,
                        )
                    }
                    None => {
                        godot_warn!("rsapi: SNG has no levels at all");
                        (
                            Vec::new(),
                            beats,
                            chord_templates,
                            hand_shapes,
                            phrases,
                            phrase_iterations,
                            levels,
                            start_time,
                            max_diff,
                            capo,
                            tuning,
                            difficulty_count,
                            is_dynamic_difficulty,
                            song_length,
                        )
                    }
                }
            }
        } else {
            (
                Vec::new(),
                Vec::new(),
                Vec::new(),
                Vec::new(),
                Vec::new(),
                Vec::new(),
                Vec::new(),
                0.0f32,
                -1i32,
                0i8,
                vec![],
                1i32,
                false,
                0.0f32,
            )
        };

        // ── Build WEM ID → role map from Wwise SoundBank (.bnk) files ─────────
        // Each BNK's DIDX section lists the WEM IDs it references.
        // Banks with `_preview` in their path/name are preview banks; others are main.
        // MAIN takes priority: if a WEM ID appears in both, it is treated as MAIN.
        let bnk_names: Vec<String> = manifest
            .iter()
            .filter(|n| n.ends_with(".bnk"))
            .cloned()
            .collect();

        let (main_bnks, preview_bnks): (Vec<_>, Vec<_>) = bnk_names
            .into_iter()
            .partition(|name| !name.to_ascii_lowercase().contains("_preview"));

        // true = MAIN, false = PREVIEW
        let mut wem_role: HashMap<u32, bool> = HashMap::new();

        // Insert MAIN roles first so they always win.
        for bnk_name in &main_bnks {
            if let Ok(data) = psarc.inflate_file(bnk_name) {
                for id in wem_ids_from_bnk(&data) {
                    wem_role.insert(id, true);
                }
            }
        }
        // Insert PREVIEW roles only for IDs not already marked MAIN.
        for bnk_name in &preview_bnks {
            if let Ok(data) = psarc.inflate_file(bnk_name) {
                for id in wem_ids_from_bnk(&data) {
                    wem_role.entry(id).or_insert(false);
                }
            }
        }

        let has_bnk_roles = !wem_role.is_empty();

        // ── Classify and extract WEM files ────────────────────────────────────
        // For each .wem entry: determine its role, then keep the largest per role.
        let wem_entries: Vec<String> = manifest
            .iter()
            .filter(|n| n.ends_with(".wem"))
            .cloned()
            .collect();

        let mut best_main: Option<(usize, Vec<u8>)> = None;
        let mut best_preview: Option<(usize, Vec<u8>)> = None;

        for entry in &wem_entries {
            let bytes = match psarc.inflate_file(entry) {
                Ok(b) => b,
                Err(_) => continue,
            };

            // Extract the numeric WEM ID from the filename (e.g. "Audio/Windows/12345678.wem").
            let stem = std::path::Path::new(entry.as_str())
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("");
            let wem_id: Option<u32> = stem.parse().ok();

            // Determine role: BNK map takes priority; fall back to filename heuristic.
            let is_main = if has_bnk_roles {
                wem_id
                    .and_then(|id| wem_role.get(&id).copied())
                    .unwrap_or(true) // unknown IDs are assumed MAIN
            } else {
                !is_preview_wem_name(entry)
            };

            let size = bytes.len();
            if is_main {
                if best_main.as_ref().map_or(true, |(s, _)| size > *s) {
                    best_main = Some((size, bytes));
                }
            } else if best_preview.as_ref().map_or(true, |(s, _)| size > *s) {
                best_preview = Some((size, bytes));
            }
        }

        // If no dedicated MAIN WEM was found, fall back to using the preview WEM for
        // gameplay audio.  This handles CDLCs and DLCs that package a single WEM file
        // which the BNK classification marks as PREVIEW.
        let preview_wem_bytes = best_preview.map(|(_, b)| b);
        let wem_bytes = match best_main {
            Some((_, b)) => Some(b),
            None => preview_wem_bytes.clone(), // use preview as MAIN fallback
        };

        Ok(PsarcData {
            notes,
            beats,
            chord_templates,
            hand_shapes,
            phrases,
            phrase_iterations,
            levels,
            wem_bytes,
            preview_wem_bytes,
            sng_start_time,
            sng_difficulty,
            sng_capo,
            sng_tuning,
            sng_difficulty_count,
            sng_is_dynamic_difficulty,
            sng_song_length,
            song_title,
            song_artist,
            song_year,
            has_lead,
            has_rhythm,
            has_bass,
        })
    }
}

// ── BNK helpers ──────────────────────────────────────────────────────────────

/// Extract all external WEM IDs listed in a Wwise SoundBank's DIDX section.
///
/// BNK format: a sequence of chunks `[tag: 4 B][size: u32 LE][data: size B]`.
/// The DIDX chunk contains 12-byte entries: `[wem_id: u32 LE][offset: u32 LE][len: u32 LE]`.
fn wem_ids_from_bnk(data: &[u8]) -> Vec<u32> {
    let mut ids = Vec::new();
    let mut i = 0usize;

    while i + 8 <= data.len() {
        let tag = &data[i..i + 4];
        let size = u32::from_le_bytes(data[i + 4..i + 8].try_into().unwrap_or([0; 4])) as usize;

        if tag == b"DIDX" {
            let mut j = i + 8;
            while j + 12 <= i + 8 + size {
                let wem_id = u32::from_le_bytes(data[j..j + 4].try_into().unwrap_or([0; 4]));
                ids.push(wem_id);
                j += 12;
            }
            break; // only one DIDX section per bank
        }

        if size == 0 {
            break;
        } // guard against malformed banks with zero-size chunks
        i += 8 + size;
    }

    ids
}

fn is_preview_wem_name(name: &str) -> bool {
    name.contains("PREVIEW")
}

fn extract_hsan_metadata(
    psarc: &mut rocksmith2014_psarc::Psarc<File>,
    manifest: &[String],
) -> (String, String, i32) {
    let hsan_name = manifest
        .iter()
        .find(|n| n.to_ascii_lowercase().ends_with(".hsan"));
    let Some(hsan_name) = hsan_name else {
        return (String::new(), String::new(), 0);
    };

    let Ok(bytes) = psarc.inflate_file(hsan_name) else {
        return (String::new(), String::new(), 0);
    };
    let Ok(text) = String::from_utf8(bytes) else {
        return (String::new(), String::new(), 0);
    };
    let Ok(json) = serde_json::from_str::<Value>(&text) else {
        return (String::new(), String::new(), 0);
    };

    let title = find_first_string(
        &json,
        &["SongName", "Title", "songName", "title", "name", "Name"],
    )
    .unwrap_or_default();
    let artist = find_first_string(
        &json,
        &[
            "ArtistName",
            "artistName",
            "Artist",
            "artist",
            "Band",
            "band",
        ],
    )
    .unwrap_or_default();
    let year = find_first_i32(
        &json,
        &["AlbumYear", "albumYear", "SongYear", "songYear", "Year", "year"],
    )
    .unwrap_or(0);

    (title, artist, year)
}

fn find_first_string(v: &Value, keys: &[&str]) -> Option<String> {
    match v {
        Value::Object(map) => {
            for (k, val) in map {
                if keys.iter().any(|needle| k.eq_ignore_ascii_case(needle)) {
                    if let Some(s) = val.as_str() {
                        if !s.trim().is_empty() {
                            return Some(s.trim().to_string());
                        }
                    }
                }
            }
            for (_, val) in map {
                if let Some(found) = find_first_string(val, keys) {
                    return Some(found);
                }
            }
            None
        }
        Value::Array(arr) => arr.iter().find_map(|it| find_first_string(it, keys)),
        _ => None,
    }
}

fn find_first_i32(v: &Value, keys: &[&str]) -> Option<i32> {
    match v {
        Value::Object(map) => {
            for (k, val) in map {
                if keys.iter().any(|needle| k.eq_ignore_ascii_case(needle)) {
                    if let Some(n) = val.as_i64() {
                        return i32::try_from(n).ok();
                    }
                    if let Some(n) = val.as_f64() {
                        return Some(n.round() as i32);
                    }
                    if let Some(s) = val.as_str() {
                        if let Ok(n) = s.parse::<i32>() {
                            return Some(n);
                        }
                    }
                }
            }
            for (_, val) in map {
                if let Some(found) = find_first_i32(val, keys) {
                    return Some(found);
                }
            }
            None
        }
        Value::Array(arr) => arr.iter().find_map(|it| find_first_i32(it, keys)),
        _ => None,
    }
}
