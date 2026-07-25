extends Node2D

# Passive companion equipment (Sidekick Robot) — no green button, active automatically for the
# whole run the instant it's equipped (see world.gd/sandbox.gd's _spawn_sidekick, called from
# _ready()/_on_item_selected() directly, not through the deploy_equipment_requested flow every
# other piece of equipment uses). Follows the player, trailing FOLLOW_DISTANCE pixels behind
# their current movement direction, and auto-fires at the nearest enemy — same targeting/fire
# logic as turret.gd, just also chasing a moving player instead of sitting still.

const ICON_TARGET_SIZE := 40.0
const BULLET_SCENE := preload("res://scenes/bullets/bullet.tscn")
const FOLLOW_DISTANCE := 25.0

var _damage := 5
var _bullet_speed := 1040.0
var _player: Node2D = null
var _follow_dir := Vector2.DOWN # last non-zero movement direction, held while the player is still
var _can_fire := true
var _target: Node2D = null

@onready var _sprite: Sprite2D = $Sprite
@onready var _fire_timer: Timer = $FireTimer

func _ready() -> void:
	_fire_timer.timeout.connect(func(): _can_fire = true)

# Applies an item's tuned stats (damage/fire_rate/bullet_speed from ItemRegistry) and icon, and
# stores the player reference to follow.
func configure(tex: Texture2D, damage: int, fire_rate: float, bullet_speed: float, player: Node2D) -> void:
	_damage = damage
	_bullet_speed = bullet_speed
	_fire_timer.wait_time = fire_rate
	_player = player
	_sprite.texture = tex
	var size := tex.get_size()
	var largest: float = max(size.x, size.y)
	var scale_factor: float = ICON_TARGET_SIZE / largest if largest > 0.0 else 1.0
	_sprite.scale = Vector2(scale_factor, scale_factor)

func _process(_delta: float) -> void:
	_follow_player()
	_acquire_target()
	if _target == null:
		return
	_sprite.rotation = (_target.global_position - global_position).angle()
	if _can_fire:
		_fire()

# Tracks the player's own move-joystick-driven velocity (already computed in player.gd's
# _physics_process — no new GameManager plumbing needed) to know which way to trail; holds the
# last direction while the player is stationary rather than snapping to a default.
func _follow_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.velocity.length() > 1.0:
		_follow_dir = _player.velocity.normalized()
	global_position = _player.global_position - _follow_dir * FOLLOW_DISTANCE

# No range cap — the room is a single fixed-size screen, so the robot always tracks whatever
# enemy is nearest, anywhere on the map. Keeps the current target until it dies.
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
