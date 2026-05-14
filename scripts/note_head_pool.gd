extends Node3D

const MAX_NOTE_HEADS: int = 192
const NOTE_HEAD_SCENE: PackedScene = preload("res://scenes/note_head.tscn")

var _pool: Array[Node3D] = []
var _active: Array[Node3D] = []


func _ready() -> void:
	for _i in MAX_NOTE_HEADS:
		_pool.append(_make_note_head())


func begin_frame() -> void:
	for i in range(_active.size() - 1, -1, -1):
		var head := _active[i]
		if is_instance_valid(head):
			if head.has_method("hide_head"):
				head.hide_head()
			else:
				head.visible = false
		_pool.append(head)
	_active.clear()


func spawn_note_head(p_fret: int, p_string: int, p_marker_type: String = "single") -> Node3D:
	if _pool.is_empty():
		_pool.append(_make_note_head())
	var head: Node3D = _pool.pop_back()
	if head.has_method("setup_head"):
		head.setup_head(p_fret, p_string, p_marker_type)
	else:
		head.visible = true
	_active.append(head)
	return head


func active_count() -> int:
	return _active.size()


func get_active_heads() -> Array[Node3D]:
	return _active


func _make_note_head() -> Node3D:
	var head: Node3D = NOTE_HEAD_SCENE.instantiate()
	head.visible = false
	add_child(head)
	return head
