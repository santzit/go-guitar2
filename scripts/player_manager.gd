extends Node
## player_manager.gd — Autoload singleton that owns Player 1 and Player 2 profiles.
##
## Holds players[0] (P1) and players[1] (P2) as PlayerProfile objects.
## Loads profiles from user://players.cfg at startup and saves them whenever
## a profile value is changed via save().
##
## Registered in project.godot as:
##   PlayerManager="*res://scripts/player_manager.gd"
##
## Usage from any scene:
##   var p1 : PlayerProfile = PlayerManager.players[0]
##   p1.difficulty_percent = 50.0
##   PlayerManager.save()

const PlayerProfileScript = preload("res://scripts/player_profile.gd")

const SAVE_PATH : String = "user://players.cfg"

## Index 0 = Player 1, index 1 = Player 2.
var players : Array = []


func _ready() -> void:
	_init_defaults()
	_load()
	print("PlayerManager: loaded %d profile(s) from '%s'." % [players.size(), SAVE_PATH])


# ── Public API ────────────────────────────────────────────────────────────────

## Persist all player profiles to disk immediately.
func save() -> void:
	var cfg := ConfigFile.new()
	for p in players:
		p.save_to_cfg(cfg)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("PlayerManager: failed to save '%s' (err=%d)." % [SAVE_PATH, err])


## Return the PlayerProfile for the given 1-based player id (1 or 2).
## Returns null for invalid ids.
func get_player(player_id: int):
	if player_id < 1 or player_id > players.size():
		return null
	return players[player_id - 1]


# ── Internal helpers ──────────────────────────────────────────────────────────

func _init_defaults() -> void:
	var p1 := PlayerProfileScript.new()
	p1.id             = 1
	p1.display_name   = "Player 1"
	p1.input_bus_name = "P1_In"

	var p2 := PlayerProfileScript.new()
	p2.id             = 2
	p2.display_name   = "Player 2"
	p2.input_bus_name = "P2_In"

	players = [p1, p2]


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return   # No saved file yet — keep defaults.
	for p in players:
		p.load_from_cfg(cfg)
