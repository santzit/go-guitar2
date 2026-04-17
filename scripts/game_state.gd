extends RefCounted
class_name GameState

## Absolute filesystem path to the PSARC selected in the game menu.
static var selected_psarc_path: String = ""

## Gameplay difficulty (0–100).  100 = Hard / 100% full arrangement (default).
## Maps to DDC bands: 0–33=Easy, 34–66=Medium, 67–100=Hard.
static var difficulty_percent: float = 100.0

## ── Mixer settings (persisted to user://mixer_settings.cfg) ─────────────────

const BUS_COUNT: int = 9

## Display names for each bus (index matches BusId in gg-mixer / RtEngine).
const BUS_NAMES: Array = [
	"UI", "Music", "Lead Guitar", "Rhythm Guitar", "Bass",
	"Player Instrument", "Master", "Metronome", "Mic Room"
]

## Per-bus gain in dB.  Range: -60.0 to +6.0.  Default: 0.0 (unity gain).
static var bus_gains_db: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

## Per-bus mute state.
static var bus_mutes: Array = [false, false, false, false, false, false, false, false, false]


## Persist mixer settings to disk.
static func save_mixer_settings() -> void:
	var cfg := ConfigFile.new()
	for i in BUS_COUNT:
		cfg.set_value("mixer", "gain_db_%d" % i, bus_gains_db[i])
		cfg.set_value("mixer", "mute_%d" % i,    bus_mutes[i])
	cfg.save("user://mixer_settings.cfg")


## Load mixer settings from disk.  Safe to call even when the file does not exist.
static func load_mixer_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://mixer_settings.cfg") != OK:
		return
	for i in BUS_COUNT:
		bus_gains_db[i] = cfg.get_value("mixer", "gain_db_%d" % i, 0.0)
		bus_mutes[i]    = cfg.get_value("mixer", "mute_%d" % i,    false)


## Apply the current mixer settings to a running RtEngine GDExtension object.
static func apply_mixer_to_rt_engine(rt: Object) -> void:
	if rt == null:
		return
	for i in BUS_COUNT:
		rt.set_bus_gain_db(i, bus_gains_db[i])
		rt.set_bus_mute(i,    bus_mutes[i])


## Return sorted absolute PSARC paths from known DLC folders.
static func list_dlc_psarc_paths() -> Array[String]:
	var roots: Array[String] = []

	var res_dlc := ProjectSettings.globalize_path("res://DLC")
	roots.append(res_dlc)

	var exe_dlc := OS.get_executable_path().get_base_dir().path_join("DLC")
	if exe_dlc != res_dlc:
		roots.append(exe_dlc)

	var user_dlc := ProjectSettings.globalize_path("user://DLC")
	roots.append(user_dlc)

	var paths: Array[String] = []
	var seen: Dictionary = {}

	for root in roots:
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.to_lower().ends_with(".psarc"):
				var full_path := root.path_join(file_name)
				if not seen.has(full_path):
					seen[full_path] = true
					paths.append(full_path)
			file_name = dir.get_next()
		dir.list_dir_end()

	paths.sort()
	return paths
