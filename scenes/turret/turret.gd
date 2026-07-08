extends Node2D

# Stationary auto-turret deployed by ItemRegistry-driven equipment (Turret, Advanced Turret).
# Stats are set externally via configure() right after instantiation; the turret then finds
# its own targets and fires with no player input, for the rest of the run.

const ICON_TARGET_SIZE := 48.0
const BULLET_SCENE := preload("res://scenes/bullets/bullet.tscn")

var _damage := 2
var _bullet_speed := 520.0
var _can_fire := true
var _target: Node2D = null

@onready var _sprite: Sprite2D = $Sprite
@onready var _fire_timer: Timer = $FireTimer

func _ready() -> void:
	_fire_timer.timeout.connect(func(): _can_fire = true)

# Applies an item's tuned stats (damage/fire_rate/bullet_speed from ItemRegistry) and icon.
func configure(tex: Texture2D, damage: int, fire_rate: float, bullet_speed: float) -> void:
	_damage = damage
	_bullet_speed = bullet_speed
	_fire_timer.wait_time = fire_rate
	_sprite.texture = tex
	var size := tex.get_size()
	var largest: float = max(size.x, size.y)
	var scale_factor: float = ICON_TARGET_SIZE / largest if largest > 0.0 else 1.0
	_sprite.scale = Vector2(scale_factor, scale_factor)

func _process(_delta: float) -> void:
	_acquire_target()
	if _target == null:
		return
	_sprite.rotation = (_target.global_position - global_position).angle()
	if _can_fire:
		_fire()

# No range cap — the room is a single fixed-size screen, so the turret always tracks
# whatever enemy is nearest, anywhere on the map. Keeps the current target until it dies.
func _acquire_target() -> void:
	if _target != null and is_instance_valid(_target):
		return
	var nearest: Node2D = null
	var nearest_dist := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var dist: float = global_position.distance_to(enemy.global_position)
		if dist <= nearest_dist:
			nearest = enemy
			nearest_dist = dist
	_target = nearest

func _fire() -> void:
	_can_fire = false
	_fire_timer.start()
	var angle := (_target.global_position - global_position).angle()
	GameManager.spawn_bullet(BULLET_SCENE, global_position, angle, _damage, _bullet_speed)
