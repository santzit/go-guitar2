use crate::pitch_detector::GuitarPitchDetector;
use godot::prelude::*;

const DEFAULT_RING_CAPACITY: usize = 2048;

#[derive(Clone, Debug, Default)]
struct DetectionEvent {
    timestamp_sec: f64,
    string_num:    i64,
    frequency:     f32,
    periodicity:   f32,
}

#[derive(Debug)]
struct SpscDetectionRing {
    buf:   Vec<DetectionEvent>,
    read:  usize,
    write: usize,
    len:   usize,
}

impl SpscDetectionRing {
    fn new(capacity: usize) -> Self {
        let cap = capacity.max(8);
        Self {
            buf: vec![DetectionEvent::default(); cap],
            read: 0,
            write: 0,
            len: 0,
        }
    }

    fn clear(&mut self) {
        self.read = 0;
        self.write = 0;
        self.len = 0;
    }

    fn capacity(&self) -> usize {
        self.buf.len()
    }

    fn available(&self) -> usize {
        self.len
    }

    fn push(&mut self, ev: DetectionEvent) -> bool {
        if self.len >= self.buf.len() {
            return false;
        }
        self.buf[self.write] = ev;
        self.write = (self.write + 1) % self.buf.len();
        self.len += 1;
        true
    }

    fn pop(&mut self) -> Option<DetectionEvent> {
        if self.len == 0 {
            return None;
        }
        let ev = self.buf[self.read].clone();
        self.read = (self.read + 1) % self.buf.len();
        self.len -= 1;
        Some(ev)
    }
}

#[derive(GodotClass)]
#[class(base = Object)]
pub struct QEngine {
    #[base]
    base: Base<Object>,
    detector: Option<GuitarPitchDetector>,
    ring: SpscDetectionRing,
    sample_rate: u32,
    noise_gate: f32,
    dropped_events: u64,
}

#[godot_api]
impl IObject for QEngine {
    fn init(base: Base<Object>) -> Self {
        Self {
            base,
            detector: None,
            ring: SpscDetectionRing::new(DEFAULT_RING_CAPACITY),
            sample_rate: 48_000,
            noise_gate: 0.0,
            dropped_events: 0,
        }
    }
}

#[godot_api]
impl QEngine {
    #[func]
    pub fn start(&mut self, sample_rate: i32) -> bool {
        let sr = sample_rate.clamp(8_000, 192_000) as u32;
        match GuitarPitchDetector::new(sr) {
            Some(det) => {
                self.detector = Some(det);
                self.sample_rate = sr;
                self.ring.clear();
                self.dropped_events = 0;
                godot_print!("QEngine: started at {} Hz", sr);
                true
            }
            None => {
                godot_error!("QEngine: failed to initialize cycfi/q detector");
                false
            }
        }
    }

    #[func]
    pub fn stop(&mut self) {
        self.detector = None;
        self.ring.clear();
    }

    #[func]
    pub fn is_running(&self) -> bool {
        self.detector.is_some()
    }

    #[func]
    pub fn set_noise_gate(&mut self, gate: f32) {
        self.noise_gate = gate.clamp(0.0, 1.0);
    }

    #[func]
    pub fn push_input_stereo(&mut self, data: PackedVector2Array, block_time_sec: f64) -> i64 {
        let det = match self.detector.as_mut() {
            Some(d) => d,
            None => return 0,
        };

        let sr = self.sample_rate as f64;
        let mut processed = 0i64;
        for (i, v) in data.as_slice().iter().enumerate() {
            let mut s = v.x.clamp(-1.0, 1.0);
            if s.abs() < self.noise_gate {
                s = 0.0;
            }

            if let Some(r) = det.process(s) {
                let ev = DetectionEvent {
                    timestamp_sec: block_time_sec + (i as f64 / sr),
                    string_num: (6 - r.string_index) as i64,
                    frequency: r.frequency,
                    periodicity: r.periodicity,
                };
                if !self.ring.push(ev) {
                    self.dropped_events += 1;
                }
            }
            processed += 1;
        }
        processed
    }

    #[func]
    pub fn pop_detections(&mut self, max_count: i32) -> Array<Variant> {
        let mut out: Array<Variant> = Array::new();
        let n = max_count.max(0) as usize;
        for _ in 0..n {
            let Some(ev) = self.ring.pop() else {
                break;
            };
            let mut d: Dictionary<GString, Variant> = Dictionary::new();
            d.set(&GString::from("timestamp"), ev.timestamp_sec);
            d.set(&GString::from("string"), ev.string_num);
            d.set(&GString::from("frequency"), ev.frequency);
            d.set(&GString::from("periodicity"), ev.periodicity);
            out.push(&d.to_variant());
        }
        out
    }

    #[func]
    pub fn available_detections(&self) -> i64 {
        self.ring.available() as i64
    }

    #[func]
    pub fn detection_ring_capacity(&self) -> i64 {
        self.ring.capacity() as i64
    }

    #[func]
    pub fn dropped_detection_count(&self) -> i64 {
        self.dropped_events as i64
    }
}
