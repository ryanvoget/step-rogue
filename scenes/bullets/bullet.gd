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
const LASER_CORE_COLOR := Color(1.0, 0.88, 0.82)

const WAVE_COLOR := Color(0.25, 0.85, 0.85)
const WAVE_MAX_TRAVEL_DISTANCE := 980.0 # ~ the 480x854 room's diagonal — the longest possible shot
const WAVE_MIN_WIDTH := 12.0
const WAVE_LENGTH_RATIO := 0.5 # travel-axis size relative to transverse width, for an elliptical look

var _distance_traveled := 0.0
var _wave_width := WAVE_MIN_WIDTH
var _wave_length := WAVE_MIN_WIDTH * WAVE_LENGTH_RATIO

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _base_collision_radius: float = _collision_shape.shape.radius

func _ready() -> void:
	$VisibleOnScreenNotifier2D.screen_exited.connect(queue_free)

func _process(delta: float) -> void:
	var motion := transform.x * speed * delta
	# High-speed bullets (e.g. Sniper Rifle Blaster, ~9800px/s) can tunnel clean through an
	# enemy within a single frame before Area2D's body_entered overlap below ever registers —
	# a ray-sweep along this frame's motion catches that case. Normal-speed bullets are
	# unaffected: if the ray finds nothing, movement + the existing overlap detection behave
	# exactly as before.
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

func _apply_hit(body: Node2D) -> void:
	if body.is_in_group(target_group):
		body.take_damage(damage, transform.x, knockback_force, freeze_duration, FREEZE_COLOR, freeze_duration > 0.0, shooter)
		if from_player:
			GameManager.record_shot_hit()
	queue_free()

func _draw() -> void:
	if wave_max_width > 0.0:
		_draw_wave()
	elif freeze_duration > 0.0:
		draw_rect(Rect2(-FREEZE_RECT_SIZE / 2.0, FREEZE_RECT_SIZE), FREEZE_COLOR)
	else:
		# Layered glow: soft halo -> body -> hot core, all centered and along-travel.
		var halo := LASER_RECT_SIZE * 1.9
		draw_rect(Rect2(-halo / 2.0, halo), Color(LASER_GLOW_COLOR, 0.18))
		var mid := LASER_RECT_SIZE * 1.35
		draw_rect(Rect2(-mid / 2.0, mid), Color(LASER_GLOW_COLOR, 0.40))
		draw_rect(Rect2(-LASER_RECT_SIZE / 2.0, LASER_RECT_SIZE), Color(1.0, 0.25, 0.18, 0.95))
		var core := LASER_RECT_SIZE * Vector2(0.72, 0.42)
		draw_rect(Rect2(-core / 2.0, core), Color(LASER_CORE_COLOR, 0.95))

func _draw_wave() -> void:
	const SEGMENTS := 24
	var points := PackedVector2Array()
	for i in range(SEGMENTS):
		var a := TAU * float(i) / float(SEGMENTS)
		points.append(Vector2(cos(a) * _wave_length / 2.0, sin(a) * _wave_width / 2.0))
	draw_colored_polygon(points, Color(WAVE_COLOR, 0.5))
	for i in range(points.size()):
		draw_line(points[i], points[(i + 1) % points.size()], Color(WAVE_COLOR, 0.85), 2.0)
