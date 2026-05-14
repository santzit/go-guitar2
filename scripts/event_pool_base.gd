extends RefCounted
class_name EventPoolBase

var _pool: Array[Node3D] = []
var _active: Array[Node3D] = []


func warm(count: int, factory: Callable) -> void:
	for _i in range(maxi(count, 0)):
		_pool.append(factory.call())


func acquire(factory: Callable) -> Node3D:
	if _pool.is_empty():
		_pool.append(factory.call())
	var instance: Node3D = _pool.pop_back()
	_active.append(instance)
	return instance


func release(instance: Node3D) -> void:
	_active.erase(instance)
	_pool.append(instance)


func release_all(release_callback: Callable = Callable()) -> void:
	for i in range(_active.size() - 1, -1, -1):
		var instance: Node3D = _active[i]
		if release_callback.is_valid():
			release_callback.call(instance)
		_pool.append(instance)
	_active.clear()


func active_count() -> int:
	return _active.size()


func get_active() -> Array[Node3D]:
	return _active
