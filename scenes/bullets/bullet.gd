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
@export var chain_count := 1        # how many enemies the arc hops through after the first hit
@export var chain_damage_frac := 0.5 # arc damage as a fraction of the bullet's own (1.0 = same)
@export var pierce := false        # passes through enemies (each hit once) instead of dying on the
                                    # first — Photon Spear. Walls still stop it.
@export var ricochet_bounces := 0  # how many times this bounces off walls before dying — the
                                    # dagger family and Cannon Boomerang
@export var split_count := 0       # splits into this many children after split_delay, fanned
                                    # around its heading — Dagger Hammer's knives
@export var split_delay := 0.0
@export var max_range := 0.0       # >0 = dies after travelling this far. Bullets are otherwise
                                    # unlimited (they only stop on a wall or off-screen), so this
                                    # is what makes "shorter/longer range" mean anything
@export var bolt_style := false     # draws as a long light-blue lightning bolt instead of the
                                    # default red laser dash — Photon Spear. Purely visual; the
                                    # collision shape is unchanged.
@export var spiral_radius := 0.0    # >0 = corkscrews around its launch axis instead of flying
                                    # straight — Beam Laser Blaster's side lasers vortexing around
                                    # the beam. The bullet still advances at `speed` along the
                                    # axis; the orbit is on top of that.
@export var spiral_rate := 0.0      # orbits per second
@export var spiral_phase := 0.0     # starting angle, so paired shots can launch opposite
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
const LIGHTNING_ARC_SCENE := preload("res://scenes/fx/lightning_arc.tscn")
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

var _bounces_left := 0
var _split_timer := 0.0
var _range_travelled := 0.0
# Spiral state: the axis is captured at launch and never changes, so the corkscrew stays centred
# on the line the shot was fired along (i.e. the beam) even as the player keeps turning.
var _spiral_origin := Vector2.ZERO
var _spiral_axis := Vector2.ZERO
var _spiral_along := 0.0

func _ready() -> void:
	$VisibleOnScreenNotifier2D.screen_exited.connect(queue_free)
	_bounces_left = ricochet_bounces
	_split_timer = split_delay
	if spiral_radius > 0.0:
		_spiral_origin = global_position
		_spiral_axis = transform.x

# Splits into `split_count` children fanned around the current heading, then dies. The children
# inherit damage and bounces but never split again, so one shot can't cascade without limit.
# Cap on how many bodies one piercing shot resolves in a single frame's sweep, so a dense crowd
# can't spin the loop. At 66,000px/s the Photon Spear crosses the whole room in one frame, so this
# needs headroom above "a couple of enemies".
const PIERCE_SWEEP_LIMIT := 12

const SPLIT_FAN := deg_to_rad(50.0)
func _do_split() -> void:
	var parent := get_parent()
	if parent != null:
		for i in range(split_count):
			var t := 0.5 if split_count == 1 else float(i) / float(split_count - 1)
			var a: float = rotation - SPLIT_FAN * 0.5 + SPLIT_FAN * t
			var child = duplicate()
			child.split_count = 0
			child.split_delay = 0.0
			child.rotation = a
			child.global_position = global_position
			parent.add_child(child)
	queue_free()

func _process(delta: float) -> void:
	if split_count > 0:
		_split_timer -= delta
		if _split_timer <= 0.0:
			_do_split()
			return
	# Laser Homing+ relic: a player laser gently steers toward the nearest enemy within its radius.
	if from_player and wave_max_width <= 0.0:
		var homing := ItemRegistry.artifact_num("laser_homing_radius", 0.0)
		if homing > 0.0:
			_home_toward_enemy(homing, delta)
	var motion := transform.x * speed * delta
	if spiral_radius > 0.0:
		# Advance along the fixed axis, then offset perpendicular by the orbit. Movement is
		# expressed as a delta to `motion` rather than a direct position set so the ray-sweep and
		# max_range tracking below both see the true path, curve included.
		_spiral_along += speed * delta
		spiral_phase += TAU * spiral_rate * delta
		var perp := Vector2(-_spiral_axis.y, _spiral_axis.x)
		var want := _spiral_origin + _spiral_axis * _spiral_along \
			+ perp * (spiral_radius * sin(spiral_phase))
		motion = want - global_position
		queue_redraw() # the drawn size breathes with the orbit — see _draw
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
		if pierce:
			# A piercing shot has to damage EVERY target along this frame's path and then carry on.
			# Taking the normal path below would pin it in place: it snaps to the first body's
			# surface and returns without moving, so the next frame's ray starts on that same
			# surface, finds the same body, and the bullet never advances again. Walk the ray
			# instead, excluding each body as it's hit, and fall through to the move at the end.
			var exclude: Array[RID] = []
			for _i in range(PIERCE_SWEEP_LIMIT):
				var pq := PhysicsRayQueryParameters2D.create(global_position, global_position + motion)
				pq.collision_mask = collision_mask
				pq.exclude = exclude
				var pr := space_state.intersect_ray(pq)
				if not pr:
					break
				if not pr.collider.is_in_group(target_group):
					global_position = pr.position # a wall still stops a piercing shot
					_apply_hit(pr.collider)
					return
				_apply_hit(pr.collider)
				exclude.append(pr.rid)
		else:
			var query := PhysicsRayQueryParameters2D.create(global_position, global_position + motion)
			query.collision_mask = collision_mask
			var result := space_state.intersect_ray(query)
			if result and result.collider.is_in_group(target_group):
				global_position = result.position
				_apply_hit(result.collider)
				return
	position += motion
	if max_range > 0.0:
		_range_travelled += motion.length()
		if _range_travelled >= max_range:
			queue_free()
			return
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
# Arcs onward from the enemy just struck, hopping to the nearest untouched enemy each time and
# jumping up to `chain_count` times. Each hop starts from the enemy it last hit, so a chain walks
# through a crowd rather than firing every arc from the same origin. Already-hit enemies are
# excluded, so it can't bounce between the same pair.
func _chain_from(source: Node2D) -> void:
	var reach := CHAIN_RANGE * ItemRegistry.artifact_num("electric_range_mult", 1.0)
	var parent := get_parent()
	var struck := {source: true}
	var from: Node2D = source
	for _hop in range(maxi(chain_count, 1)):
		var best: Node2D = null
		var best_d := reach
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or struck.has(e):
				continue
			var d: float = from.global_position.distance_to(e.global_position)
			if d <= best_d:
				best_d = d
				best = e
		if best == null or not best.has_method("take_damage"):
			return
		struck[best] = true
		# Red character doubles the arc damage (GameManager.elemental_effect_mult).
		var arc_dmg := maxi(1, int(round(float(damage) * chain_damage_frac * GameManager.elemental_effect_mult)))
		best.take_damage(arc_dmg, Vector2.ZERO, 0.0, 0.1)
		# Draw the arc. Parented to the bullets container rather than this bullet, since a
		# non-piercing bullet frees itself the same frame it chains.
		if parent != null:
			var arc: Node2D = LIGHTNING_ARC_SCENE.instantiate()
			parent.add_child(arc)
			arc.setup(from.global_position, best.global_position)
		from = best

func _apply_hit(body: Node2D) -> void:
	var is_target := body.is_in_group(target_group)
	if is_target:
		# Piercing shots (a Wave Ray Gun wave, or a `pierce` weapon like the Photon Spear) hit each
		# enemy once and keep going. Everything else dies on its first enemy.
		# Ricochet shots track who they've struck for the same reason piercing ones do: so a shot
		# that kicks off an enemy can't immediately re-detect it and spend its bounces in place.
		var passes_through := wave_max_width > 0.0 or pierce or ricochet_bounces > 0
		if passes_through and _hit_bodies.has(body):
			return
		if passes_through:
			_hit_bodies[body] = true
		body.take_damage(damage, transform.x, knockback_force, freeze_duration, FREEZE_COLOR, freeze_duration > 0.0, shooter)
		if from_player:
			GameManager.record_shot_hit()
			_spawn_impact_fx(true) # energy-transfer burst on the enemy
			if burn_damage > 0 and body.has_method("apply_burn"):
				body.apply_burn(burn_damage, burn_duration) # Fire Blaster
			if chain_lightning:
				_chain_from(body) # Electro Blaster
	# Piercing shots pass through enemies but still stop on a wall (non-target body).
	if (wave_max_width > 0.0 or pierce) and is_target:
		return
	# Ricochet off the ENEMY it just hit and seek the next one. This is the primary meaning of
	# ricochet_bounces — a knife that buries into one enemy, kicks off, and finds another. Falls
	# through to the wall bounce below (and then to death) when there's nobody else in reach.
	if is_target and _bounces_left > 0:
		if _ricochet_to_enemy(body):
			return
	if not is_target and _bounces_left > 0:
		# Ricochet weapons (Ricochet Flame Daggers, Spiked/Beam Daggers, Cannon Boomerang) bounce
		# off walls instead of dying. Reflect about the surface normal and carry on with one fewer
		# bounce; the enemies already hit are forgotten so a bounce-back can hit them again.
		if _ricochet_off_wall():
			return
	if from_player and not is_target:
		_spawn_impact_fx(false) # scorch/spark on a wall
	queue_free()

# Redirects at the nearest OTHER enemy after striking one. Enemies already struck are remembered
# for the shot's whole life so a two-bounce knife hits three different targets rather than
# ping-ponging between the same pair. Returns false when nothing else is in range, letting the
# caller fall through to the wall bounce / death path.
const ENEMY_RICOCHET_RANGE := 420.0
func _ricochet_to_enemy(from_body: Node2D) -> bool:
	_hit_bodies[from_body] = true
	var best: Node2D = null
	var best_d := ENEMY_RICOCHET_RANGE
	for e in get_tree().get_nodes_in_group(target_group):
		if e == from_body or not is_instance_valid(e) or _hit_bodies.has(e):
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d <= best_d:
			best_d = d
			best = e
	if best == null:
		return false
	_bounces_left -= 1
	var dir := (best.global_position - global_position).normalized()
	rotation = dir.angle()
	# Start clear of the body just hit so the next frame's sweep doesn't re-detect it.
	var clearance: float = (from_body._radius if "_radius" in from_body else 20.0) + 8.0
	global_position = from_body.global_position + dir * clearance
	if from_player:
		_spawn_impact_fx(false)
	return true

# Reflects travel direction about the wall it just touched. Returns false if no surface could be
# found to bounce off (in which case the caller lets the bullet die as normal).
func _ricochet_off_wall() -> bool:
	var space_state := get_world_2d().direct_space_state
	# Probe a little further along travel than this frame's step, so the surface is definitely hit.
	var probe := transform.x * 24.0
	var query := PhysicsRayQueryParameters2D.create(global_position - transform.x * 8.0, global_position + probe)
	query.collision_mask = collision_mask
	var hit := space_state.intersect_ray(query)
	if not hit or not hit.has("normal"):
		return false
	var reflected: Vector2 = transform.x.bounce(hit["normal"])
	if reflected.length() < 0.01:
		return false
	_bounces_left -= 1
	_hit_bodies.clear()
	rotation = reflected.angle()
	global_position = hit["position"] + reflected.normalized() * 6.0 # nudge clear of the surface
	if from_player:
		_spawn_impact_fx(false)
	return true

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
	# A corkscrewing shot fakes depth: cos(phase) is +1 on the near half of the orbit and -1 on the
	# far half, so scaling by it makes the laser swell as it swings toward the camera and shrink as
	# it passes behind the beam. That's what separates a vortex from a flat side-to-side weave.
	if spiral_radius > 0.0:
		var near := 0.72 + 0.38 * cos(spiral_phase)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(near, near))
	if wave_max_width > 0.0:
		_draw_wave()
	elif bolt_style:
		_draw_bolt()
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

# Photon Spear: a long light-blue bolt rather than a stubby dash. Four times the laser's length,
# tapered to a point at the leading edge so it reads as a thrown spear, with a jagged filament
# running through it so it also reads as lightning. Drawn along +X (travel direction).
const BOLT_COLOR      := Color(0.45, 0.80, 1.0)
const BOLT_CORE_COLOR := Color(0.90, 0.98, 1.0)
func _draw_bolt() -> void:
	var length := LASER_RECT_SIZE.x * 6.0 # 1.5x the original 4x — a long spear, not a dash
	var half_h := LASER_RECT_SIZE.y * 0.5
	var tip := Vector2(length * 0.5, 0.0)
	var tail := Vector2(-length * 0.5, 0.0)
	# Outer bloom, drawn as a stretched diamond so the head is sharp and the tail feathers out.
	draw_colored_polygon(PackedVector2Array([
		tip * 1.12, Vector2(0.0, -half_h * 2.6), tail * 1.15, Vector2(0.0, half_h * 2.6)]),
		Color(BOLT_COLOR, 0.16))
	draw_colored_polygon(PackedVector2Array([
		tip, Vector2(-length * 0.2, -half_h * 1.5), tail, Vector2(-length * 0.2, half_h * 1.5)]),
		Color(BOLT_COLOR, 0.55))
	# Jagged filament: a fixed zigzag down the spine, so the bolt crackles rather than being a bar.
	const KINKS := 5
	var pts := PackedVector2Array()
	for i in range(KINKS + 1):
		var t := float(i) / float(KINKS)
		var y := (half_h * 0.9) * (1.0 if i % 2 == 0 else -1.0) * (1.0 - t) # settles toward the tip
		pts.append(tail.lerp(tip, t) + Vector2(0.0, y))
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], Color(BOLT_CORE_COLOR, 0.9), 2.0)
	draw_line(tail * 0.8, tip, Color(BOLT_CORE_COLOR, 0.95), 2.5) # blinding core
	draw_circle(tip, half_h * 1.3, Color(BOLT_CORE_COLOR, 0.85))  # hot leading point

func _draw_wave() -> void:
	const SEGMENTS := 24
	var points := PackedVector2Array()
	for i in range(SEGMENTS):
		var a := TAU * float(i) / float(SEGMENTS)
		points.append(Vector2(cos(a) * _wave_length / 2.0, sin(a) * _wave_width / 2.0))
	draw_colored_polygon(points, Color(WAVE_COLOR, 0.5))
	for i in range(points.size()):
		draw_line(points[i], points[(i + 1) % points.size()], Color(WAVE_COLOR, 0.85), 2.0)
