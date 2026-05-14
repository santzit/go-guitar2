extends Node3D
const EventPoolBase = preload("res://scripts/event_pool_base.gd")

const MAX_NOTE_HEADS: int = 192
const NOTE_HEAD_SCENE: PackedScene = preload("res://scenes/note_head.tscn")

var _heads: EventPoolBase = EventPoolBase.new()


func _ready() -> void:
	_heads.warm(MAX_NOTE_HEADS, Callable(self, "_make_note_head"))


func begin_frame() -> void:
	_heads.release_all(Callable(self, "_hide_head_instance"))


func spawn_note_head(p_fret: int, p_string: int, p_marker_type: String = "single") -> Node3D:
	var head: Node3D = _heads.acquire(Callable(self, "_make_note_head"))
	if head.has_method("setup_head"):
		head.setup_head(p_fret, p_string, p_marker_type)
	else:
		head.visible = true
	return head


func active_count() -> int:
	return _heads.active_count()


func get_active_heads() -> Array[Node3D]:
	return _heads.get_active()


func _make_note_head() -> Node3D:
	var head: Node3D = NOTE_HEAD_SCENE.instantiate()
	head.visible = false
	add_child(head)
	return head


func _hide_head_instance(head: Node3D) -> void:
	if not is_instance_valid(head):
		return
	if head.has_method("hide_head"):
		head.hide_head()
	else:
		head.visible = false
