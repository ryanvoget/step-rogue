extends Node2D

# Thrown melee weapon (e.g. Throwable Beam Sword): flies out from the player in the aim
# direction until it hits a wall, then flies back to the player's current position, dealing
# AOE damage continuously the whole way — out and back — so it can hit the same enemy twice
# in one throw. Spawned via GameManager.spawn_thrown_weapon; player.gd blocks throwing
# another one until this returns (see player.gd's _thrown_in_flight / returned signal).

signal returned

enum Leg { OUTBOUND, RETURNING }

const MAX_CAST_DISTANCE := 1200.0 # comfortably longer than the room's ~980px diagonal
const WALL_COLLISION_MASK := 8    # matches room.gd's wall StaticBody2Ds (collision_layer = 8)
const RETURN_ARRIVE_DIST := 16.0  # how close counts as "back at the player"
const ICON_TARGET_SIZE := 36.0

var _damage := 0
var _radius := 100.0
var _speed := 520.0
var _leg := Leg.OUTBOUND
var _player: Node2D = null
var _direction := Vector2.RIGHT
var _turnaround_pos := Vector2.ZERO
var _hit_this_leg: Dictionary = {} # enemy -> true; cleared per leg so out/back can each land a hit
var _scored := false # counts this throw as "connected" once, for melee accuracy (see GameManager)

# ── In-flight emissions ──────────────────────────────────────────────────────────────────────
# Two fused boomerangs do something extra while airborne, both driven from here because they need
# the weapon's live position: Laser Boomerang sprays lasers in every direction as it spins, and
# Scatter Boomerang drops expanding damage rings along its path.
const PULSE_RING_SCENE := preload("res://scenes/fx/wave_pulse.tscn")
const ORBIT_SPOKES := 6 # lasers per volley, spread evenly around the weapon
var _orbit_damage := 0
var _orbit_rate := 0.0
var _orbit_accum := 0.0
var _orbit_spin := 0.0
var _ring_damage := 0
var _ring_rate := 0.0
var _ring_radius := 150.0
var _ring_accum := 0.0
var _bullet_scene: PackedScene = null

func configure_emissions(bullet_scene: PackedScene, orbit_damage: int, orbit_rate: float,
		ring_damage: int, ring_rate: float, ring_radius: float) -> void:
	_bullet_scene = bullet_scene
	_orbit_damage = orbit_damage
	_orbit_rate = orbit_rate
	_ring_damage = ring_damage
	_ring_rate = ring_rate
	_ring_radius = ring_radius

func _tick_emissions(delta: float) -> void:
	if _orbit_damage > 0 and _orbit_rate > 0.0 and _bullet_scene != null:
		_orbit_accum += delta
		while _orbit_accum >= _orbit_rate:
			_orbit_accum -= _orbit_rate
			# Rotate the spoke pattern each volley so the spray reads as spinning rather than
			# firing the same fixed star over and over.
			_orbit_spin += 0.55
			for i in range(ORBIT_SPOKES):
				var a := TAU * float(i) / float(ORBIT_SPOKES) + _orbit_spin
				GameManager.spawn_bullet(_bullet_scene, global_position, a, _orbit_damage, -1.0,
					0.0, 0.0, 0.0, true)
	if _ring_damage > 0 and _ring_rate > 0.0:
		_ring_accum += delta
		while _ring_accum >= _ring_rate:
			_ring_accum -= _ring_rate
			var ring: Node2D = PULSE_RING_SCENE.instantiate()
			get_parent().add_child(ring)
			ring.configure(global_position, _ring_damage, _ring_radius, 0.0, false, Color(0.5, 0.9, 1.0))

@onready var _sprite: Sprite2D = $Sprite

# Applies an item's tuned stats (damage/thrown_radius/bullet_speed from ItemRegistry) and icon.
func configure(tex: Texture2D, damage: int, radius: float, speed: float) -> void:
	_damage = damage
	_radius = radius
	_speed = speed
	_sprite.texture = tex
	var size := tex.get_size()
	var largest: float = max(size.x, size.y)
	var scale_factor: float = ICON_TARGET_SIZE / largest if largest > 0.0 else 1.0
	_sprite.scale = Vector2(scale_factor, scale_factor)

# Must be called after this node is already inside the tree (configure()+add_child first) —
# the wall raycast needs a valid World2D to query.
func launch(origin: Vector2, direction: Vector2, player: Node2D) -> void:
	global_position = origin
	_direction = direction.normalized()
	_player = player
	rotation = _direction.angle()
	_turnaround_pos = _raycast_wall(origin, _direction)
	_leg = Leg.OUTBOUND
	_hit_this_leg.clear()

func _raycast_wall(origin: Vector2, direction: Vector2) -> Vector2:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(origin, origin + direction * MAX_CAST_DISTANCE)
	query.collision_mask = WALL_COLLISION_MASK
	var result := space_state.intersect_ray(query)
	return result.position if result else origin + direction * MAX_CAST_DISTANCE

func _physics_process(delta: float) -> void:
	_tick_emissions(delta)
	_apply_hitbox()
	match _leg:
		Leg.OUTBOUND:
			global_position = global_position.move_toward(_turnaround_pos, _speed * delta)
			if global_position.distance_to(_turnaround_pos) < 1.0:
				_leg = Leg.RETURNING
				_hit_this_leg.clear()
		Leg.RETURNING:
			if _player == null or not is_instance_valid(_player):
				queue_free()
				return
			var target: Vector2 = _player.global_position
			if global_position.distance_to(target) > 1.0:
				rotation = (target - global_position).angle()
			global_position = global_position.move_toward(target, _speed * delta)
			if global_position.distance_to(target) < RETURN_ARRIVE_DIST:
				returned.emit()
				queue_free()

# Constant hitbox for the whole flight (out and back), not a one-shot check — matches
# _radius exactly to the drawn circle so what's shown is what actually connects.
func _apply_hitbox() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if _hit_this_leg.has(enemy):
			continue
		if global_position.distance_to(enemy.global_position) <= _radius and enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
			_hit_this_leg[enemy] = true
			# Same impact shake a melee hit gives, scaled by damage — a returning boomerang
			# connecting should land as hard as a swing that does the same damage.
			GameManager.add_screen_shake(clampf(float(_damage) / 18.0, 0.15, 0.55))
			if not _scored:
				_scored = true
				GameManager.record_melee_hit()

func _draw() -> void:
	draw_circle(Vector2.ZERO, _radius, Color(0.75, 0.8, 0.95, 0.15))
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 32, Color(0.85, 0.9, 1.0, 0.45), 2.0)
