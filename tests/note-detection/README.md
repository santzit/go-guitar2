## Note detection dataset tests

This folder contains Godot-side dataset tests for note detection helpers using WAV files.

### Script

- `test_note_detection_dataset.gd`
  - Scans `res://tests/note-detection/dataset` recursively for `*.wav`
  - Parses 16-bit PCM RIFF WAV files directly (no import dependency)
  - Runs lightweight pitch estimation (autocorrelation) on dataset clips
  - Verifies at least one note-labeled clip can be matched when such filenames exist
  - Exercises Godot playback path through `AudioStreamWAV` + `AudioStreamPlayer`
  - Skips gracefully when no dataset WAV files are present

### Dataset source

Recommended dataset source referenced by the PR feedback:

https://github.com/santzit/guitar-pitch-detection-/tree/main/tests/dataset

Place WAV files under:

`tests/note-detection/dataset/`

### Run

```bash
./Godot_v4.4.1-stable_linux.x86_64 --headless --path . \
  --script tests/note-detection/test_note_detection_dataset.gd
```
