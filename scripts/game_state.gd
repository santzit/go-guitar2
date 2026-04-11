extends RefCounted
class_name GameState

## Absolute filesystem path to the PSARC selected in the game menu.
static var selected_psarc_path: String = ""


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
