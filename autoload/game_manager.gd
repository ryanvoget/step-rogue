extends Node

signal health_changed(current: int, maximum: int)
signal floor_changed(floor_num: int)
signal room_cleared
signal player_died

var current_floor: int = 1

var step_bank: int:
	get: return SaveManager.step_bank
	set(v): SaveManager.step_bank = v

var _bullets_container: Node = null

func register_bullets_container(node: Node) -> void:
	_bullets_container = node

func spawn_bullet(scene: PackedScene, pos: Vector2, angle: float) -> void:
	if _bullets_container == null:
		return
	var b = scene.instantiate()
	b.global_position = pos
	b.rotation = angle
	_bullets_container.add_child(b)

func next_floor() -> void:
	current_floor += 1
	floor_changed.emit(current_floor)

func reset() -> void:
	current_floor = 1
	SceneManager.go_to_menu()
