# ChartPlayer reference

This folder tracks the upstream reference project used for UI/gameplay inspiration:

- Upstream: https://github.com/mikeoliphant/ChartPlayer
- License: GPL (compatible for reference/reuse in this project)
- Reference image: https://github.com/user-attachments/assets/07610968-9347-4e0f-99d9-fd850a40c817

Current adaptation in GoGuitar2 keeps Godot scene separation (`highway`, `fretboard`, `note`, `number`) and adds a dedicated `chartplayer_reference_hud.tscn` scene for top/bottom HUD composition.

Rust audio/PSARC flow remains unchanged (`cpal`, `gg-mixer`, `q`, `rocksmith2014.rs`, `vgmstream`).
