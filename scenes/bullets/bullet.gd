extends Area2D

@export var speed := 520.0
@export var damage := 15
@export var freeze_duration := 0.0 # >0 = freezes (fully halts) whatever it hits for this long;
                                    # also swaps the draw from the default yellow dot to a
                                    # blue laser rectangle (e.g. Freeze Gun)
@export var knockback_force := 0.0 # px/s impulse on hit; 0 = no knockback (e.g. Wave Ray Gun's slight push)
@export var wave_max_width := 0.0  # >0 marks this an expanding elliptical wave (Wave Ray Gun):
                                    # drawn (and collision-scaled) wider the farther it's traveled,
                                    # capping at this width once it's gone WAVE_MAX_TRAVEL_DISTANCE
@export var burn_damage := 0       # >0 = applies a burn DOT on hit (e.g. Fire Blaster)
@export var burn_duration := 0.0
@export var chain_lightning := false # arcs to a nearby enemy on hit (e.g. Electro Blaster)
@export var target_group := "enemies" # which group take_damage() is called on when this bullet
                                    # hits a body — "player" for enemy-fired bullets (see
                                    # GameManager.spawn_enemy_bullet), "enemies" otherwise

var from_player := false # true for player-fired bullets — see GameManager.spawn_bullet; drives
                          # the bullet-accuracy "shot hit" stat in _apply_hit
var shooter: Node2D = null # who fired this (enemy-fired bullets only — see
                            # GameManager.spawn_enemy_bullet) so Reflect Shield knows who to
                            # deal reflected damage back to; null/unused for player-fired bullets

const FREEZE_COLOR := Color(0.25, 0.55, 1.0)
const FREEZE_RECT_SIZE := Vector2(16.0, 5.0) # long and thin, laser-shaped, oriented along travel

# Default bullet look: a glowing red laser rectangle (was a plain yellow dot). Drawn as
# layered translucent rects — a soft outer halo, a mid body, and a hot near-white core — so it
# reads as a glowing bolt over the dark room without needing a shader. Oriented along travel,
# same as the freeze rect.
const LASER_RECT_SIZE := Vector2(18.0, 6.0)
const LASER_GLOW_COLOR := Color(1.0, 0.12, 0.08)
const LASER_CORE_COLOR := Color(0.85, 0.97, 1.0) # blinding cyan-white core wrapped in red bloom

const LASER_IMPACT_SCENE := preload("res://scenes/fx/laser_impact.tscn")
const HEAVY_SHOT_DAMAGE := 12 # at/above this, an enemy hit gets a brief freeze-frame (hit-lag)

const WAVE_COLOR := Color(0.25, 0.85, 0.85)
const WAVE_MAX_TRAVEL_DISTANCE := 980.0 # ~ the 480x854 room's diagonal — the longest possible shot
const WAVE_MIN_WIDTH := 12.0
const WAVE_LENGTH_RATIO := 0.5 # travel-axis size relative to transverse width, for an elliptical look

var _distance_traveled := 0.0
var _wave_width := WAVE_MIN_WIDTH
var _wave_length := WAVE_MIN_WIDTH * WAVE_LENGTH_RATIO
var _hit_bodies := {} # enemies already damaged by a piercing wave, so each is hit only once

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _base_collision_radius: float = _collision_shape.shape.radius

func _ready() -> void:
	$VisibleOnScreenNotifier2D.screen_exited.connect(queue_free)

func _process(delta: float) -> void:
	# Laser Homing+ relic: a player laser gently steers toward the nearest enemy within its radius.
	if from_player and wave_max_width <= 0.0:
		var homing := ItemRegistry.artifact_num("laser_homing_radius", 0.0)
		if homing > 0.0:
			_home_toward_enemy(homing, delta)
	var motion := transform.x * speed * delta
	# High-speed bullets (e.g. Sniper Rifle Blaster, ~9800px/s) can tunnel clean through an
	# enemy within a single frame before Area2D's body_entered overlap below ever registers —
	# a ray-sweep along this frame's motion catches that case. Normal-speed bullets are
	# unaffected: if the ray finds nothing, movement + the existing overlap detection behave
	# exactly as before.
	# The wave (Wave Ray Gun) pierces — it passes through and damages everything in its path — so it
	# skips the single-hit ray-sweep and relies purely on the Area2D overlap (_on_body_entered),
	# tracking who it's already hit. Normal bullets keep the ray-sweep for high-speed tunnelling.
	if wave_max_width <= 0.0:
		var space_state := get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + motion)
		query.collision_mask = collision_mask
		var result := space_state.intersect_ray(query)
		if result and result.collider.is_in_group(target_group):
			global_position = result.position
			_apply_hit(result.collider)
			return
	position += motion
	if wave_max_width > 0.0:
		_distance_traveled += speed * delta
		_update_wave_size()
		queue_redraw()

# Scales the (otherwise circular) CollisionShape2D non-uniformly so the hit area actually
# grows with the visual — a wide, barely-there graze at max range still connects.
func _update_wave_size() -> void:
	var t := clampf(_distance_traveled / WAVE_MAX_TRAVEL_DISTANCE, 0.0, 1.0)
	_wave_width = lerpf(WAVE_MIN_WIDTH, wave_max_width, t)
	_wave_length = _wave_width * WAVE_LENGTH_RATIO
	_collision_shape.scale = Vector2((_wave_length / 2.0) / _base_collision_radius, (_wave_width / 2.0) / _base_collision_radius)

func _on_body_entered(body: Node2D) -> void:
	_apply_hit(body)

# Steers the bullet's heading toward the nearest enemy within `radius`, turning at a limited rate so
# it curves rather than snapping — a homing laser (Laser Homing+ relic).
func _home_toward_enemy(radius: float, delta: float) -> void:
	var best: Node2D = null
	var best_d := radius
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d <= best_d:
			best_d = d
			best = e
	if best == null:
		return
	var desired := (best.global_position - global_position).angle()
	rotation = rotate_toward(rotation, desired, 6.0 * delta) # ~6 rad/s max turn

# Electro Blaster: arc to the nearest OTHER enemy within range, dealing half damage + a brief stun.
# Electric+ artifact widens the reach.
const CHAIN_RANGE := 220.0
func _chain_from(source: Node2D) -> void:
	var best: Node2D = null
	var best_d := CHAIN_RANGE * ItemRegistry.artifact_num("electric_range_mult", 1.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == source or not is_instance_valid(e):
			continue
		var d: float = source.global_position.distance_to(e.global_position)
		if d <= best_d:
			best_d = d
			best = e
	if best != null and best.has_method("take_damage"):
		# Red character doubles the arc damage (GameManager.elemental_effect_mult).
		var arc_dmg := maxi(1, int(round(float(damage) / 2.0 * GameManager.elemental_effect_mult)))
		best.take_damage(arc_dmg, Vector2.ZERO, 0.0, 0.1)

func _apply_hit(body: Node2D) -> void:
	var is_target := body.is_in_group(target_group)
	if is_target:
		# A piercing wave hits each enemy only once, then keeps going (no queue_free below).
		if wave_max_width > 0.0 and _hit_bodies.has(body):
			return
		if wave_max_width > 0.0:
			_hit_bodies[body] = true
		body.take_damage(damage, transform.x, knockback_force, freeze_duration, FREEZE_COLOR, freeze_duration > 0.0, shooter)
		if from_player:
			GameManager.record_shot_hit()
			_spawn_impact_fx(true) # energy-transfer burst on the enemy
			if burn_damage > 0 and body.has_method("apply_burn"):
				body.apply_burn(burn_damage, burn_duration) # Fire Blaster
			if chain_lightning:
				_chain_from(body) # Electro Blaster
	# Wave passes through enemies but still stops on a wall (non-target body); normal bullets die on
	# any hit.
	if wave_max_width > 0.0 and is_target:
		return
	if from_player and not is_target:
		_spawn_impact_fx(false) # scorch/spark on a wall
	queue_free()

# Impact juice for player lasers: an expanding energy burst at the point of contact plus a
# damage-scaled screen shake, an impact zap-crack, and (heavy enemy hits only) a brief freeze-frame.
func _spawn_impact_fx(is_enemy: bool) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var col: Color = GameManager.laser_energy_color(freeze_duration, wave_max_width)
	var scl: float = clampf(float(damage) / 8.0, 0.7, 2.4)
	var fx: Node2D = LASER_IMPACT_SCENE.instantiate()
	fx.setup(col, scl)
	fx.global_position = global_position
	parent.add_child(fx)
	GameManager.add_screen_shake(clampf(float(damage) / 50.0, 0.03, 0.5) if is_enemy else 0.08)
	AudioManager.play_laser_impact()
	if is_enemy and damage >= HEAVY_SHOT_DAMAGE:
		GameManager.hitstop(0.08, 0.035) # momentary hit-lag sells the kinetic force of a heavy shot

func _draw() -> void:
	if wave_max_width > 0.0:
		_draw_wave()
	elif freeze_duration > 0.0:
		# Freeze bolt gets the same layered treatment (blue bloom + icy white core).
		var fhalo := FREEZE_RECT_SIZE * 2.0
		draw_rect(Rect2(-fhalo / 2.0, fhalo), Color(FREEZE_COLOR, 0.20))
		var fmid := FREEZE_RECT_SIZE * 1.4
		draw_rect(Rect2(-fmid / 2.0, fmid), Color(FREEZE_COLOR, 0.45))
		draw_rect(Rect2(-FREEZE_RECT_SIZE / 2.0, FREEZE_RECT_SIZE), FREEZE_COLOR)
		var fcore := FREEZE_RECT_SIZE * Vector2(0.7, 0.45)
		draw_rect(Rect2(-fcore / 2.0, fcore), Color(0.85, 0.95, 1.0, 0.95))
	else:
		# Multi-layered bolt: a faint trailing streak, a broad soft bloom, the body, and a blinding
		# white/cyan core line — all centred and oriented along travel, to fake intense light.
		var trail := Vector2(LASER_RECT_SIZE.x * 2.6, LASER_RECT_SIZE.y * 0.75)
		draw_rect(Rect2(Vector2(-trail.x, -trail.y / 2.0), trail), Color(LASER_GLOW_COLOR, 0.10))
		var bloom := LASER_RECT_SIZE * Vector2(2.6, 2.5)
		draw_rect(Rect2(-bloom / 2.0, bloom), Color(LASER_GLOW_COLOR, 0.12))
		var halo := LASER_RECT_SIZE * 1.9
		draw_rect(Rect2(-halo / 2.0, halo), Color(LASER_GLOW_COLOR, 0.22))
		var mid := LASER_RECT_SIZE * 1.35
		draw_rect(Rect2(-mid / 2.0, mid), Color(LASER_GLOW_COLOR, 0.42))
		draw_rect(Rect2(-LASER_RECT_SIZE / 2.0, LASER_RECT_SIZE), Color(1.0, 0.30, 0.20, 0.95))
		var core := LASER_RECT_SIZE * Vector2(0.92, 0.34)
		draw_rect(Rect2(-core / 2.0, core), Color(LASER_CORE_COLOR, 0.98))
		var spark := LASER_RECT_SIZE * Vector2(0.55, 0.16)
		draw_rect(Rect2(-spark / 2.0, spark), Color(1, 1, 1, 1.0))

func _draw_wave() -> void:
	const SEGMENTS := 24
	var points := PackedVector2Array()
	for i in range(SEGMENTS):
		var a := TAU * float(i) / float(SEGMENTS)
		points.append(Vector2(cos(a) * _wave_length / 2.0, sin(a) * _wave_width / 2.0))
	draw_colored_polygon(points, Color(WAVE_COLOR, 0.5))
	for i in range(points.size()):
		draw_line(points[i], points[(i + 1) % points.size()], Color(WAVE_COLOR, 0.85), 2.0)
