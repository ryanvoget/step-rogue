extends Node2D

# Summoned companion (Dennis) — appears on the map when the gold "SUMMON DENNIS" equipment
# button is pressed (see item_registry.gd's summon field docs), then stays for the rest of the
# run/test session. Fires continuously at the nearest enemy using Assault Rifle Blaster's own
# damage/fire_rate/bullet_speed, read live from ItemRegistry at spawn time (see configure())
# so the two can never drift out of sync — same targeting/fire pattern as turret.gd/
# sidekick_robot.gd. Every GRENADE_INTERVAL seconds he also throws a random item from the
# whole grenade list (ItemRegistry.random_grenade()) at the nearest enemy.

const ICON_TARGET_SIZE := 48.0
const BULLET_SCENE := preload("res://scenes/bullets/bullet.tscn")
const GRENADE_SCENE := preload("res://scenes/grenade/grenade.tscn")
const GRENADE_INTERVAL := 5.0

var _damage := 1
var _bullet_speed := 520.0
var _can_fire := true
var _target: Node2D = null
var _grenade_timer := GRENADE_INTERVAL

@onready var _sprite: Sprite2D = $Sprite
@onready var _fire_timer: Timer = $FireTimer

func _ready() -> void:
	_fire_timer.timeout.connect(func(): _can_fire = true)

# Applies Assault Rifle Blaster's own stats (damage/fire_rate/bullet_speed, looked up by
# world.gd/sandbox.gd via ItemRegistry.get_item_by_name) and Dennis's own icon, then places him
# at spawn_pos (the player's position at the moment of summoning).
func configure(tex: Texture2D, damage: int, fire_rate: float, bullet_speed: float, spawn_pos: Vector2) -> void:
	_damage = damage
	_bullet_speed = bullet_speed
	_fire_timer.wait_time = fire_rate
	global_position = spawn_pos
	_grenade_timer = GRENADE_INTERVAL
	_sprite.texture = tex
	var size := tex.get_size()
	var largest: float = max(size.x, size.y)
	var scale_factor: float = ICON_TARGET_SIZE / largest if largest > 0.0 else 1.0
	_sprite.scale = Vector2(scale_factor, scale_factor)

func _process(delta: float) -> void:
	_acquire_target()
	if _target == null:
		return
	_sprite.rotation = (_target.global_position - global_position).angle()
	if _can_fire:
		_fire()
	_grenade_timer -= delta
	if _grenade_timer <= 0.0:
		_grenade_timer += GRENADE_INTERVAL
		_throw_random_grenade()

# No range cap — the room is a single fixed-size screen, so Dennis always tracks whatever
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

# Sticky Grenade needs a direct target reference (configure_stick) instead of a landing
# position; every other grenade just needs one, which for Dennis is always exactly where the
# nearest enemy currently is — he's a perfect shot, no raycast/joystick simulation needed.
# Mirrors world.gd/sandbox.gd's _throw_grenade's generic field extraction for every grenade
# mode (gravity/confuse/linger/distract/freeze/flash/mesh) so any grenade works unmodified.
func _throw_random_grenade() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var item: Dictionary = ItemRegistry.random_grenade()
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	var grenade: Node2D = GRENADE_SCENE.instantiate()
	get_parent().add_child(grenade)
	if item.get("sticky", false):
		grenade.configure_stick(tex, global_position, _target, item["sticky_damage"], item["sticky_delay"])
		return
	var dmg: int = item["damage"] if item.get("damage") != null else 0
	grenade.configure(tex, global_position, _target.global_position, dmg, item["aoe_radius"], item["explode_delay"],
		item.get("gravity_duration", 0.0), item.get("gravity_tick_interval", 0.5), item.get("gravity_pull_speed", 90.0),
		item.get("confuse_duration", 0.0), item.get("linger_duration", 0.0), item.get("linger_burn_damage", 0),
		item.get("linger_burn_duration", 0.0), item.get("distract_duration", 0.0), item.get("freeze_duration", 0.0),
		item.get("flash_duration", 0.0), item.get("mesh_count", 0), item.get("mesh_radius_ratio", 0.25),
		item.get("mesh_damage", 0))
