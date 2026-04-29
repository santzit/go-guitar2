use crate::rsapi::{
    ChordTemplateEntry, HandShapeEntry, LevelEntry, PhraseEntry, PhraseIterationEntry, PsarcData,
    ToneChangeEntry,
};
use godot::prelude::*;

const CHORD_GROUP_THRESHOLD: f32 = 0.02;
const FRET_COUNT: i32 = 24;
const STRING_OPEN_MIDI: [i32; 6] = [40, 45, 50, 55, 59, 64];
const NOTE_NAMES: [&str; 12] = [
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
];

#[derive(Clone, Debug)]
struct NoteData {
    time: f32,
    fret: i32,
    string_index: i32,
    duration: f32,
    hand_shape_id: i32,
    hand_shape_chord_id: i32,
    hand_shape_min_fret: i32,
    hand_shape_max_fret: i32,
    hand_shape_min_string: i32,
    hand_shape_max_string: i32,
}

#[derive(Clone, Debug)]
struct PlayEventData {
    time_start: f32,
    time_end: f32,
    hand_fret_start: i32,
    hand_fret_end: i32,
    notes: Vec<NoteData>,
    kind: String,
    chord_name: String,
    show_details: bool,
    force_outline: bool,
    outline_min_fret: i32,
    outline_max_fret: i32,
    outline_min_string: i32,
    outline_max_string: i32,
}

#[allow(non_camel_case_types)]
#[derive(GodotClass)]
#[class(base = Object)]
pub struct RSAPI_SNG {
    #[base]
    base: Base<Object>,
    notes: Vec<NoteData>,
    play_events: Vec<PlayEventData>,
    chord_templates: Vec<ChordTemplateEntry>,
    hand_shapes: Vec<HandShapeEntry>,
    phrases: Vec<PhraseEntry>,
    phrase_iterations: Vec<PhraseIterationEntry>,
    levels: Vec<LevelEntry>,
    wem_data: Option<Vec<u8>>,
    preview_wem_data: Option<Vec<u8>>,
    sng_start_time: f32,
    sng_difficulty: i32,
    sng_capo: i8,
    sng_tuning: Vec<i16>,
    sng_difficulty_count: i32,
    sng_is_dynamic_difficulty: bool,
    sng_song_length: f32,
    song_title: String,
    song_artist: String,
    song_year: i32,
    has_lead: bool,
    has_rhythm: bool,
    has_bass: bool,
    mapped_tone_preset_json: String,
    tone_mapping_report_json: String,
    raw_tone_summary_json: String,
    tone_changes: Vec<ToneChangeEntry>,
    difficulty_band: usize,
}

#[godot_api]
impl IObject for RSAPI_SNG {
    fn init(base: Base<Object>) -> Self {
        Self {
            base,
            notes: Vec::new(),
            play_events: Vec::new(),
            chord_templates: Vec::new(),
            hand_shapes: Vec::new(),
            phrases: Vec::new(),
            phrase_iterations: Vec::new(),
            levels: Vec::new(),
            wem_data: None,
            preview_wem_data: None,
            sng_start_time: 0.0,
            sng_difficulty: -1,
            sng_capo: 0,
            sng_tuning: vec![],
            sng_difficulty_count: 1,
            sng_is_dynamic_difficulty: false,
            sng_song_length: 0.0,
            song_title: String::new(),
            song_artist: String::new(),
            song_year: 0,
            has_lead: false,
            has_rhythm: false,
            has_bass: false,
            mapped_tone_preset_json: String::new(),
            tone_mapping_report_json: String::new(),
            raw_tone_summary_json: String::new(),
            tone_changes: Vec::new(),
            difficulty_band: 2,
        }
    }
}

#[godot_api]
impl RSAPI_SNG {
    #[func]
    fn set_difficulty(&mut self, percent: f64) {
        self.difficulty_band = if percent <= 33.0 {
            0
        } else if percent <= 66.0 {
            1
        } else {
            2
        };
        godot_print!(
            "RSAPI_SNG: difficulty set to {:.0}% -> band {}",
            percent,
            self.difficulty_band
        );
    }

    #[func]
    fn load_psarc(&mut self, path: GString) -> bool {
        self.reset();
        let path_str = path.to_string();
        godot_print!("RSAPI_SNG: loading '{}'", path_str);
        match self.parse_psarc(&path_str) {
            Ok(_) => true,
            Err(e) => {
                godot_error!("RSAPI_SNG: failed to load '{}': {}", path_str, e);
                false
            }
        }
    }

    #[func]
    fn get_notes(&self) -> Array<Variant> {
        let mut arr: Array<Variant> = Array::new();
        for n in &self.notes {
            arr.push(&note_to_dict(n).to_variant());
        }
        arr
    }

    #[func]
    fn get_play_events(&self) -> Array<Variant> {
        let mut arr: Array<Variant> = Array::new();
        for ev in &self.play_events {
            let mut notes_arr: Array<Variant> = Array::new();
            for n in &ev.notes {
                notes_arr.push(&note_to_dict(n).to_variant());
            }
            let mut d: Dictionary<GString, Variant> = Dictionary::new();
            d.set(&GString::from("time_start"), ev.time_start);
            d.set(&GString::from("time_end"), ev.time_end);
            d.set(&GString::from("hand_fret_start"), ev.hand_fret_start);
            d.set(&GString::from("hand_fret_end"), ev.hand_fret_end);
            d.set(&GString::from("notes"), &notes_arr.to_variant());
            d.set(&GString::from("kind"), &Variant::from(ev.kind.as_str()));
            d.set(
                &GString::from("chord_name"),
                &Variant::from(ev.chord_name.as_str()),
            );
            d.set(&GString::from("show_details"), ev.show_details);
            d.set(&GString::from("force_outline"), ev.force_outline);
            d.set(&GString::from("outline_min_fret"), ev.outline_min_fret);
            d.set(&GString::from("outline_max_fret"), ev.outline_max_fret);
            d.set(&GString::from("outline_min_string"), ev.outline_min_string);
            d.set(&GString::from("outline_max_string"), ev.outline_max_string);
            arr.push(&d.to_variant());
        }
        arr
    }

    #[func]
    fn get_chord_templates(&self) -> Array<Variant> {
        let mut arr: Array<Variant> = Array::new();
        for c in &self.chord_templates {
            let mut d: Dictionary<GString, Variant> = Dictionary::new();
            d.set(&GString::from("id"), c.id);
            d.set(&GString::from("name"), &Variant::from(c.name.as_str()));
            let mut frets: Array<Variant> = Array::new();
            let mut fingers: Array<Variant> = Array::new();
            for &v in &c.frets {
                frets.push(&Variant::from(v as i32));
            }
            for &v in &c.fingers {
                fingers.push(&Variant::from(v as i32));
            }
            d.set(&GString::from("frets"), &frets.to_variant());
            d.set(&GString::from("fingers"), &fingers.to_variant());
            arr.push(&d.to_variant());
        }
        arr
    }

    #[func]
    fn get_hand_shapes(&self) -> Array<Variant> {
        let mut arr: Array<Variant> = Array::new();
        for hs in &self.hand_shapes {
            let mut d: Dictionary<GString, Variant> = Dictionary::new();
            d.set(&GString::from("level_difficulty"), hs.level_difficulty);
            d.set(&GString::from("chord_id"), hs.chord_id);
            d.set(&GString::from("start_time"), hs.start_time);
            d.set(&GString::from("end_time"), hs.end_time);
            d.set(&GString::from("first_note_time"), hs.first_note_time);
            d.set(&GString::from("last_note_time"), hs.last_note_time);
            d.set(&GString::from("min_fret"), hs.min_fret as i32);
            d.set(&GString::from("max_fret"), hs.max_fret as i32);
            d.set(&GString::from("min_string"), hs.min_string as i32);
            d.set(&GString::from("max_string"), hs.max_string as i32);
            arr.push(&d.to_variant());
        }
        arr
    }

    #[func]
    fn get_phrases(&self) -> Array<Variant> {
        let mut arr: Array<Variant> = Array::new();
        for p in &self.phrases {
            let mut d: Dictionary<GString, Variant> = Dictionary::new();
            d.set(&GString::from("id"), p.id);
            d.set(&GString::from("name"), &Variant::from(p.name.as_str()));
            d.set(&GString::from("max_difficulty"), p.max_difficulty);
            d.set(&GString::from("iteration_count"), p.iteration_count);
            d.set(&GString::from("solo"), p.solo as i32);
            arr.push(&d.to_variant());
        }
        arr
    }

    #[func]
    fn get_phrase_iterations(&self) -> Array<Variant> {
        let mut arr: Array<Variant> = Array::new();
        for pi in &self.phrase_iterations {
            let mut d: Dictionary<GString, Variant> = Dictionary::new();
            d.set(&GString::from("phrase_id"), pi.phrase_id);
            d.set(&GString::from("start_time"), pi.start_time);
            d.set(&GString::from("end_time"), pi.end_time);
            d.set(&GString::from("easy"), pi.easy);
            d.set(&GString::from("medium"), pi.medium);
            d.set(&GString::from("hard"), pi.hard);
            arr.push(&d.to_variant());
        }
        arr
    }

    #[func]
    fn get_levels(&self) -> Array<Variant> {
        let mut arr: Array<Variant> = Array::new();
        for lvl in &self.levels {
            let mut d: Dictionary<GString, Variant> = Dictionary::new();
            d.set(&GString::from("difficulty"), lvl.difficulty);
            d.set(&GString::from("notes_count"), lvl.notes_count);
            d.set(&GString::from("hand_shapes_count"), lvl.hand_shapes_count);
            d.set(&GString::from("anchors_count"), lvl.anchors_count);
            arr.push(&d.to_variant());
        }
        arr
    }

    #[func]
    fn get_wem_bytes(&self) -> PackedByteArray {
        match &self.wem_data {
            Some(data) => PackedByteArray::from(data.as_slice()),
            None => PackedByteArray::new(),
        }
    }

    #[func]
    fn get_preview_wem_bytes(&self) -> PackedByteArray {
        match &self.preview_wem_data {
            Some(data) => PackedByteArray::from(data.as_slice()),
            None => PackedByteArray::new(),
        }
    }

    #[func]
    fn get_sng_info(&self) -> Dictionary<GString, Variant> {
        let mut dict: Dictionary<GString, Variant> = Dictionary::new();
        dict.set(&GString::from("start_time"), self.sng_start_time);
        dict.set(&GString::from("difficulty"), self.sng_difficulty);
        dict.set(&GString::from("capo"), self.sng_capo as i32);
        dict.set(
            &GString::from("difficulty_count"),
            self.sng_difficulty_count,
        );
        dict.set(
            &GString::from("is_dynamic_difficulty"),
            self.sng_is_dynamic_difficulty,
        );
        let mut tuning_arr: Array<Variant> = Array::new();
        for &t in &self.sng_tuning {
            tuning_arr.push(&Variant::from(t as i32));
        }
        dict.set(&GString::from("tuning"), &tuning_arr.to_variant());
        dict
    }

    #[func]
    fn get_song_metadata(&self) -> Dictionary<GString, Variant> {
        let mut d: Dictionary<GString, Variant> = Dictionary::new();
        d.set(
            &GString::from("title"),
            &Variant::from(self.song_title.as_str()),
        );
        d.set(
            &GString::from("artist"),
            &Variant::from(self.song_artist.as_str()),
        );
        d.set(&GString::from("year"), self.song_year);
        d.set(&GString::from("sng_song_length"), self.sng_song_length);
        d.set(&GString::from("has_lead"), self.has_lead);
        d.set(&GString::from("has_rhythm"), self.has_rhythm);
        d.set(&GString::from("has_bass"), self.has_bass);
        d
    }

    #[func]
    fn get_mapped_tone_preset_json(&self) -> GString {
        GString::from(self.mapped_tone_preset_json.as_str())
    }

    #[func]
    fn get_tone_mapping_report_json(&self) -> GString {
        GString::from(self.tone_mapping_report_json.as_str())
    }

    #[func]
    fn get_raw_tone_summary_json(&self) -> GString {
        GString::from(self.raw_tone_summary_json.as_str())
    }

    #[func]
    fn get_tone_changes(&self) -> Array<Variant> {
        let mut arr: Array<Variant> = Array::new();
        for tc in &self.tone_changes {
            let mut d: Dictionary<GString, Variant> = Dictionary::new();
            d.set(&GString::from("time"), tc.time);
            d.set(&GString::from("tone_id"), tc.tone_id);
            d.set(
                &GString::from("tone_name"),
                &Variant::from(tc.tone_name.as_str()),
            );
            arr.push(&d.to_variant());
        }
        arr
    }
}

impl RSAPI_SNG {
    fn reset(&mut self) {
        self.notes.clear();
        self.play_events.clear();
        self.chord_templates.clear();
        self.hand_shapes.clear();
        self.phrases.clear();
        self.phrase_iterations.clear();
        self.levels.clear();
        self.wem_data = None;
        self.preview_wem_data = None;
        self.sng_start_time = 0.0;
        self.sng_difficulty = -1;
        self.sng_capo = 0;
        self.sng_tuning.clear();
        self.sng_difficulty_count = 1;
        self.sng_is_dynamic_difficulty = false;
        self.sng_song_length = 0.0;
        self.song_title = String::new();
        self.song_artist = String::new();
        self.song_year = 0;
        self.has_lead = false;
        self.has_rhythm = false;
        self.has_bass = false;
        self.mapped_tone_preset_json = String::new();
        self.tone_mapping_report_json = String::new();
        self.raw_tone_summary_json = String::new();
        self.tone_changes.clear();
    }

    fn parse_psarc(&mut self, path: &str) -> Result<(), Box<dyn std::error::Error>> {
        let data = PsarcData::open(path, self.difficulty_band)?;
        self.sng_start_time = data.sng_start_time;
        self.sng_difficulty = data.sng_difficulty;
        self.sng_capo = data.sng_capo;
        self.sng_tuning = data.sng_tuning;
        self.sng_difficulty_count = data.sng_difficulty_count;
        self.sng_is_dynamic_difficulty = data.sng_is_dynamic_difficulty;
        self.sng_song_length = data.sng_song_length;
        self.song_title = data.song_title;
        self.song_artist = data.song_artist;
        self.song_year = data.song_year;
        self.has_lead = data.has_lead;
        self.has_rhythm = data.has_rhythm;
        self.has_bass = data.has_bass;
        self.mapped_tone_preset_json = data.mapped_tone_preset_json;
        self.tone_mapping_report_json = data.tone_mapping_report_json;
        self.raw_tone_summary_json = data.raw_tone_summary_json;
        self.tone_changes = data.tone_changes;
        self.chord_templates = data.chord_templates;
        self.hand_shapes = data.hand_shapes;
        self.phrases = data.phrases;
        self.phrase_iterations = data.phrase_iterations;
        self.levels = data.levels;

        self.notes = data
            .notes
            .iter()
            .filter(|n| (0..=24).contains(&n.fret) && (0..=5).contains(&n.string_index))
            .map(|n| NoteData {
                time: n.time,
                fret: n.fret as i32,
                string_index: n.string_index as i32,
                duration: if n.sustain < 0.0 { 0.0 } else { n.sustain },
                hand_shape_id: n.hand_shape_id,
                hand_shape_chord_id: n.hand_shape_chord_id,
                hand_shape_min_fret: n.hand_shape_min_fret as i32,
                hand_shape_max_fret: n.hand_shape_max_fret as i32,
                hand_shape_min_string: n.hand_shape_min_string as i32,
                hand_shape_max_string: n.hand_shape_max_string as i32,
            })
            .collect();

        self.notes.sort_by(|a, b| {
            a.time
                .partial_cmp(&b.time)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        self.play_events = build_play_events(&self.notes, &self.sng_tuning);

        self.wem_data = data.wem_bytes;
        self.preview_wem_data = data.preview_wem_bytes;

        godot_print!(
            "RSAPI_SNG: notes={} events={} phrases={} levels={}",
            self.notes.len(),
            self.play_events.len(),
            self.phrases.len(),
            self.levels.len()
        );
        Ok(())
    }
}

fn note_to_dict(n: &NoteData) -> Dictionary<GString, Variant> {
    let mut dict: Dictionary<GString, Variant> = Dictionary::new();
    dict.set(&GString::from("time"), n.time);
    dict.set(&GString::from("fret"), n.fret);
    dict.set(&GString::from("string"), n.string_index);
    dict.set(&GString::from("duration"), n.duration);
    dict.set(&GString::from("hand_shape_id"), n.hand_shape_id);
    dict.set(&GString::from("hand_shape_chord_id"), n.hand_shape_chord_id);
    dict.set(&GString::from("hand_shape_min_fret"), n.hand_shape_min_fret);
    dict.set(&GString::from("hand_shape_max_fret"), n.hand_shape_max_fret);
    dict.set(
        &GString::from("hand_shape_min_string"),
        n.hand_shape_min_string,
    );
    dict.set(
        &GString::from("hand_shape_max_string"),
        n.hand_shape_max_string,
    );
    dict
}

fn build_play_events(src_notes: &[NoteData], tuning: &[i16]) -> Vec<PlayEventData> {
    let mut events = Vec::new();
    let mut i = 0usize;
    let mut last_chord_sig = String::new();

    while i < src_notes.len() {
        let t0 = src_notes[i].time;
        let mut group: Vec<NoteData> = vec![src_notes[i].clone()];
        let mut j = i + 1;
        while j < src_notes.len() && (src_notes[j].time - t0).abs() < CHORD_GROUP_THRESHOLD {
            group.push(src_notes[j].clone());
            j += 1;
        }

        let mut valid_notes: Vec<NoteData> = Vec::new();
        let mut max_duration = 0.0f32;
        let mut min_fret = i32::MAX;
        let mut has_hand_shape = false;
        let mut outline_min_fret = i32::MAX;
        let mut outline_max_fret = -1;
        let mut outline_min_string = i32::MAX;
        let mut outline_max_string = -1;

        for gn in group {
            // fret 0 = open string (valid); fret -1 = string not played in chord template.
            if gn.fret < 0 || gn.fret > FRET_COUNT || gn.string_index < 0 || gn.string_index > 5 {
                continue;
            }
            let dur = gn.duration.max(0.0);
            let mut n = gn.clone();
            n.duration = dur;
            valid_notes.push(n.clone());
            max_duration = max_duration.max(dur);
            min_fret = min_fret.min(n.fret);
            if n.hand_shape_id >= 0 {
                has_hand_shape = true;
            }
            if n.hand_shape_min_fret >= 1 && n.hand_shape_max_fret >= n.hand_shape_min_fret {
                outline_min_fret = outline_min_fret.min(n.hand_shape_min_fret);
                outline_max_fret = outline_max_fret.max(n.hand_shape_max_fret);
            }
            if n.hand_shape_min_string >= 0 && n.hand_shape_max_string >= n.hand_shape_min_string {
                outline_min_string = outline_min_string.min(n.hand_shape_min_string);
                outline_max_string = outline_max_string.max(n.hand_shape_max_string);
            }
        }

        if !valid_notes.is_empty() {
            let mut event_kind = String::from("single");
            if valid_notes.len() > 1 || has_hand_shape {
                event_kind = String::from("chord");
            }

            let mut hand_start = (min_fret - 1).max(1);
            let mut hand_end = (hand_start + 3).min(FRET_COUNT);
            let force_outline = has_hand_shape;

            if outline_min_fret == i32::MAX {
                outline_min_fret = -1;
            }
            if outline_min_string == i32::MAX {
                outline_min_string = -1;
            }

            if force_outline && outline_min_fret >= 1 && outline_max_fret >= outline_min_fret {
                hand_start = (outline_min_fret - 1).max(1);
                hand_end = outline_max_fret.min(FRET_COUNT);
            }

            let mut chord_name = String::new();
            let mut show_details = false;

            if event_kind == "chord" {
                let sig = if force_outline {
                    format!(
                        "hs:{}:{}",
                        valid_notes[0].hand_shape_id, valid_notes[0].hand_shape_chord_id
                    )
                } else {
                    chord_signature(&valid_notes)
                };
                show_details = sig != last_chord_sig;
                last_chord_sig = sig;
                chord_name = note_name(valid_notes[0].fret, valid_notes[0].string_index, tuning);
            }

            events.push(PlayEventData {
                time_start: t0,
                time_end: t0 + max_duration,
                hand_fret_start: hand_start,
                hand_fret_end: hand_end,
                notes: valid_notes,
                kind: event_kind,
                chord_name,
                show_details,
                force_outline,
                outline_min_fret,
                outline_max_fret,
                outline_min_string,
                outline_max_string,
            });
        }

        i = j;
    }

    events
}

fn chord_signature(notes: &[NoteData]) -> String {
    let mut parts: Vec<String> = notes
        .iter()
        .map(|n| format!("{}:{}", n.fret, n.string_index))
        .collect();
    parts.sort();
    parts.join(",")
}

fn note_name(fret: i32, string_idx: i32, tuning: &[i16]) -> String {
    if !(0..=5).contains(&string_idx) || !(0..=24).contains(&fret) {
        return String::from("?");
    }
    let tune = tuning.get(string_idx as usize).copied().unwrap_or(0) as i32;
    let midi = STRING_OPEN_MIDI[string_idx as usize] + tune + fret;
    NOTE_NAMES[((midi % 12) + 12) as usize % 12].to_string()
}
