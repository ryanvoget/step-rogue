extends Node

signal health_changed(current: int, maximum: int)
signal floor_changed(floor_num: int)
signal room_cleared
signal player_died
signal deploy_equipment_requested(angle: float) # angle only meaningful for throwables (see mobile_controls.gd)

var current_floor: int = 1

# Set by mobile_controls when the right aim-joystick is pushed; zero when idle.
var mobile_aim_dir: Vector2 = Vector2.ZERO

# Set by player.gd whenever the equipped weapon changes; read by mobile_controls to swap
# the right-side control from an aim joystick to a plain attack button for melee weapons.
var melee_equipped: bool = false

# Set by world.gd at run start from SaveManager.equipped_equipment; read by mobile_controls
# to show/hide its deploy button (shown when either is true). equipment_deployed flips true
# once used (one-shot per run) — sandbox.gd may choose not to set it for repeat testing.
var equipment_placeable: bool = false
var equipment_throwable: bool = false
var equipment_deployed: bool = false

var step_bank: int:
	get: return SaveManager.step_bank
	set(v): SaveManager.step_bank = v

var _bullets_container: Node = null

func register_bullets_container(node: Node) -> void:
	_bullets_container = node

func spawn_bullet(scene: PackedScene, pos: Vector2, angle: float, damage: int = -1, speed: float = -1.0) -> void:
	if _bullets_container == null:
		return
	var b = scene.instantiate()
	b.global_position = pos
	b.rotation = angle
	if damage >= 0:
		b.damage = damage
	if speed >= 0.0:
		b.speed = speed
	_bullets_container.add_child(b)

func next_floor() -> void:
	current_floor += 1
	floor_changed.emit(current_floor)

func reset() -> void:
	current_floor = 1
	SceneManager.go_to_menu()
