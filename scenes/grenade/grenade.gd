extends Node2D

# Thrown equipment (e.g. Blast Grenade) or a launched weapon projectile (e.g. Void Grenade
# Launcher): flies from origin to a landing spot, waits explode_delay seconds, then either
# deals one flat AOE burst (gravity_duration == confuse_duration == linger_duration == 0, the
# original Blast Grenade behavior), becomes a persistent gravity well for gravity_duration
# seconds (pulling every enemy within radius toward its center every physics frame and ticking
# damage every gravity_tick_interval), confuses instead of damaging (Smoke Grenade), or — after
# the initial damage burst — leaves a lingering fire circle for linger_duration seconds that
# burns (apply_burn) anyone inside at explosion time or who walks in afterward, once each
# (Molotov Grenade), distracts every enemy on the map regardless of position (apply_distract,
# Distraction Grenade) for distract_duration seconds instead of damaging anyone, or freezes
# (take_damage's is_freeze flag, same mechanism as Freeze Gun) everyone within radius for
# freeze_duration seconds instead of damaging anyone — automatically slowed by 50% for a few
# seconds after thawing, see enemy_basic.gd's THAW_SLOW_* (Ice Grenade) — or blinds
# (apply_blind) everyone within radius for flash_duration seconds instead of damaging anyone,
# making their own attacks/shots miss the player entirely (Flash Grenade). On top of (not
# instead of) the normal damage burst, mesh_count > 0 also pops that many independent mini
# grenades out equidistant around the edge of radius, each detonating on its own shortly after
# with its own smaller radius/damage (Mesh Grenade — see _spawn_mesh_grenades). Before
# disappearing. Configured post-instantiate via configure().
#
# Alternatively (Sticky Grenade), configure_stick() skips the landing-spot/explosion flow
# entirely: it flies to and sticks onto a specific enemy (reparented so it moves with them),
# then deals one delayed hit instead of an AOE burst.

const ICON_TARGET_SIZE := 32.0
const THROW_DURATION := 0.15 # seconds to visually travel from origin to landing spot
const EXPLOSION_FLASH_DURATION := 0.15 # seconds the one-shot AOE ring stays drawn after exploding
const FREEZE_COLOR := Color(0.25, 0.55, 1.0) # matches bullet.gd's FREEZE_COLOR (Freeze Gun)
const BLIND_COLOR := Color(1.0, 1.0, 0.3) # matches enemy_basic.gd's BLIND_FLASH_COLOR
const MESH_EXPLODE_DELAY := 0.05 # seconds each mini grenade waits after popping out before it detonates

var _damage := 0
var _radius := 0.0
var _exploded := false
var _explode_on_impact := false # Void Grenade Launcher: detonate on hitting an enemy mid-flight
const IMPACT_RADIUS := 32.0     # so it doesn't sail through and past the enemy it was aimed at

var _gravity_duration := 0.0 # >0 marks this a gravity well instead of a one-shot burst
var _gravity_tick_interval := 0.5
var _gravity_pull_speed := 90.0
var _gravity_timer := 0.0
var _gravity_tick_timer := 0.0

var _confuse_duration := 0.0 # >0 marks this a Smoke Grenade-style confuse burst instead of damage

var _linger_duration := 0.0 # >0 marks this a Molotov Grenade-style lingering burn zone after the initial damage burst
var _linger_burn_damage := 0
var _linger_burn_duration := 0.0
var _linger_timer := 0.0
var _linger_burned: Dictionary = {} # enemy -> true, so each enemy is only burned once per lingering window

var _distract_duration := 0.0 # >0 marks this a Distraction Grenade-style whole-map distract burst instead of damage

var _freeze_duration := 0.0 # >0 marks this an Ice Grenade-style freeze burst instead of damage — see
                             # enemy_basic.gd's take_damage is_freeze param and its automatic thaw-slow

var _flash_duration := 0.0 # >0 marks this a Flash Grenade-style blind burst instead of damage —
                            # see enemy_basic.gd's apply_blind/is_blinded

var _mesh_count := 0 # >0 marks this a Mesh Grenade-style secondary burst: on top of the normal
                      # damage burst above (not instead of it), this many mini grenades pop out
                      # equidistant around the edge of _radius and each detonate independently
                      # — see _spawn_mesh_grenades
var _mesh_radius_ratio := 0.25 # each mini grenade's radius, as a fraction of _radius
var _mesh_damage := 0 # each mini grenade's damage — enemies caught in more than one mini
                       # blast circle take this once per circle they're touching (no
                       # dedup — each mini grenade is a fully independent instance)

var _stick_target: Node2D = null
var _stick_damage := 0
var _stick_delay := 0.0

var _enemy_blast := false # Nova Unit's grenade — a plain blast that damages the PLAYER group
                           # instead of enemies (see configure_enemy_blast)

@onready var _sprite: Sprite2D = $Sprite
@onready var _explode_timer: Timer = $ExplodeTimer

func _ready() -> void:
	_explode_timer.timeout.connect(_explode)

func _set_icon(tex: Texture2D) -> void:
	_sprite.texture = tex
	var size := tex.get_size()
	var largest: float = max(size.x, size.y)
	var scale_factor: float = ICON_TARGET_SIZE / largest if largest > 0.0 else 1.0
	_sprite.scale = Vector2(scale_factor, scale_factor)

# Applies an item's tuned stats (damage/aoe_radius/explode_delay from ItemRegistry, plus the
# optional gravity_* trio for a Void Grenade Launcher-style well) and icon, then tweens from
# origin to landing_pos before starting the explode_delay fuse.
func configure(tex: Texture2D, origin: Vector2, landing_pos: Vector2, damage: int, radius: float, explode_delay: float,
		gravity_duration: float = 0.0, gravity_tick_interval: float = 0.5, gravity_pull_speed: float = 90.0,
		confuse_duration: float = 0.0, linger_duration: float = 0.0, linger_burn_damage: int = 0,
		linger_burn_duration: float = 0.0, distract_duration: float = 0.0, freeze_duration: float = 0.0,
		flash_duration: float = 0.0, mesh_count: int = 0, mesh_radius_ratio: float = 0.25,
		mesh_damage: int = 0) -> void:
	_damage = damage
	_radius = radius
	_gravity_duration = gravity_duration
	_gravity_tick_interval = gravity_tick_interval
	_gravity_pull_speed = gravity_pull_speed
	_confuse_duration = confuse_duration
	_linger_duration = linger_duration
	_linger_burn_damage = linger_burn_damage
	_linger_burn_duration = linger_burn_duration
	_distract_duration = distract_duration
	_freeze_duration = freeze_duration
	_flash_duration = flash_duration
	_mesh_count = mesh_count
	_mesh_radius_ratio = mesh_radius_ratio
	_mesh_damage = mesh_damage
	_set_icon(tex)

	global_position = origin
	_explode_timer.wait_time = explode_delay
	var tween := create_tween()
	tween.tween_property(self, "global_position", landing_pos, THROW_DURATION)
	tween.finished.connect(_explode_timer.start)

# Sticky Grenade's alternate flight path: flies to target's current position, then sticks
# (reparents onto target so it moves along with them) for stick_delay seconds before dealing
# one hit of stick_damage and disappearing.
func configure_stick(tex: Texture2D, origin: Vector2, target: Node2D, stick_damage: int, stick_delay: float) -> void:
	_stick_target = target
	_stick_damage = stick_damage
	_stick_delay = stick_delay
	_set_icon(tex)

	global_position = origin
	var tween := create_tween()
	tween.tween_property(self, "global_position", target.global_position, THROW_DURATION)
	tween.finished.connect(_on_stick_arrived)

# Detonator Mine's alternate flow: drops instantly at position (no flight tween, no fuse
# timer) and sits idle indefinitely — unlike configure()'s explode_delay, which starts counting
# down immediately on landing — until detonate() is called externally (the second green
# equipment-button tap; see world.gd/sandbox.gd's _use_mine).
func configure_mine(tex: Texture2D, position: Vector2, damage: int, radius: float) -> void:
	_damage = damage
	_radius = radius
	_set_icon(tex)
	global_position = position

func detonate() -> void:
	_explode()

func _on_stick_arrived() -> void:
	if _stick_target == null or not is_instance_valid(_stick_target):
		queue_free()
		return
	reparent(_stick_target)
	global_position = _stick_target.global_position
	get_tree().create_timer(_stick_delay).timeout.connect(_apply_stick_damage)

func _apply_stick_damage() -> void:
	if _stick_target != null and is_instance_valid(_stick_target) and _stick_target.has_method("take_damage"):
		_stick_target.take_damage(_stick_damage)
	queue_free()

# Continuous gravity pull + periodic damage tick while the well is active. Reuses the
# existing knockback mechanism (take_damage's knockback_dir/force) to pull — resetting it to
# a full-strength pull toward the current center every physics frame reads as a steady
# continuous pull rather than a one-off shove, with no changes needed to enemy_basic.gd.
func _physics_process(delta: float) -> void:
	if not _exploded:
		# Detonate the moment it reaches an enemy (in flight or waiting on its fuse).
		if _explode_on_impact:
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if global_position.distance_to(enemy.global_position) <= IMPACT_RADIUS:
					_explode()
					return
		return
	if _gravity_duration > 0.0:
		_gravity_timer -= delta
		_gravity_tick_timer -= delta
		var tick_now := _gravity_tick_timer <= 0.0
		if tick_now:
			_gravity_tick_timer += _gravity_tick_interval
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if not enemy.has_method("take_damage"):
				continue
			var to_center: Vector2 = global_position - enemy.global_position
			if to_center.length() > _radius:
				continue
			var pull_dir := to_center.normalized() if to_center.length() > 1.0 else Vector2.ZERO
			enemy.take_damage(_damage if tick_now else 0, pull_dir, _gravity_pull_speed)
		if _gravity_timer <= 0.0:
			queue_free()
	elif _linger_duration > 0.0 and _linger_timer > 0.0:
		_linger_timer -= delta
		_apply_linger_burn()
		if _linger_timer <= 0.0:
			queue_free()

# Catches anyone already standing in the circle at explosion time, then re-checked every
# physics frame for the rest of _linger_timer (Molotov Grenade) so anyone who walks in gets
# burned too — but only once each, so standing in the fire doesn't keep refreshing/stacking
# the burn duration.
func _apply_linger_burn() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if _linger_burned.has(enemy):
			continue
		if global_position.distance_to(enemy.global_position) <= _radius and enemy.has_method("apply_burn"):
			enemy.apply_burn(_linger_burn_damage, _linger_burn_duration)
			_linger_burned[enemy] = true

# Nova Unit throws this at the player: fly to landing_pos, wait explode_delay, then deal one
# flat AOE burst to anyone in the "player" group within radius. Kept separate from configure()
# so the (enemy-group-targeted) player grenade logic is untouched.
func configure_enemy_blast(tex: Texture2D, origin: Vector2, landing_pos: Vector2, damage: int, radius: float, explode_delay: float) -> void:
	_damage = damage
	_radius = radius
	_enemy_blast = true
	_set_icon(tex)
	global_position = origin
	_explode_timer.wait_time = explode_delay
	var tween := create_tween()
	tween.tween_property(self, "global_position", landing_pos, THROW_DURATION)
	tween.finished.connect(_explode_timer.start)

func _explode() -> void:
	_exploded = true
	_sprite.visible = false
	if _enemy_blast:
		for p in get_tree().get_nodes_in_group("player"):
			if global_position.distance_to(p.global_position) <= _radius and p.has_method("take_damage"):
				p.take_damage(_damage)
		queue_redraw()
		get_tree().create_timer(EXPLOSION_FLASH_DURATION).timeout.connect(queue_free)
		return
	if _gravity_duration > 0.0:
		_gravity_timer = _gravity_duration
		_gravity_tick_timer = _gravity_tick_interval
		queue_redraw()
		return
	if _distract_duration > 0.0:
		# Whole-map effect — every enemy regardless of distance, unlike every other burst mode
		# here which only reaches enemies within _radius.
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy.has_method("apply_distract"):
				enemy.apply_distract(global_position, _distract_duration)
		queue_redraw()
		get_tree().create_timer(EXPLOSION_FLASH_DURATION).timeout.connect(queue_free)
		return
	if _freeze_duration > 0.0:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if global_position.distance_to(enemy.global_position) <= _radius and enemy.has_method("take_damage"):
				enemy.take_damage(0, Vector2.ZERO, 0.0, _freeze_duration, FREEZE_COLOR, true)
		queue_redraw()
		get_tree().create_timer(EXPLOSION_FLASH_DURATION).timeout.connect(queue_free)
		return
	if _flash_duration > 0.0:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if global_position.distance_to(enemy.global_position) <= _radius and enemy.has_method("apply_blind"):
				enemy.apply_blind(_flash_duration)
		queue_redraw()
		get_tree().create_timer(EXPLOSION_FLASH_DURATION).timeout.connect(queue_free)
		return
	if _confuse_duration > 0.0:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if global_position.distance_to(enemy.global_position) <= _radius and enemy.has_method("apply_confuse"):
				enemy.apply_confuse(_confuse_duration)
	else:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if global_position.distance_to(enemy.global_position) <= _radius and enemy.has_method("take_damage"):
				enemy.take_damage(_damage)
	if _mesh_count > 0:
		_spawn_mesh_grenades() # on top of the damage burst above, not instead of it (Mesh Grenade)
	if _linger_duration > 0.0:
		_linger_timer = _linger_duration
		_apply_linger_burn() # catches anyone already standing in the circle at explosion time
		queue_redraw()
		return
	queue_redraw()
	get_tree().create_timer(EXPLOSION_FLASH_DURATION).timeout.connect(queue_free)

# Mesh Grenade: pops _mesh_count mini grenades out equidistant around the edge of _radius, each
# a fully independent grenade.tscn instance that flies out (reusing the same THROW_DURATION
# flight tween as any normal throw) then detonates on its own after MESH_EXPLODE_DELAY with a
# radius of _radius * _mesh_radius_ratio and _mesh_damage — no coordination between them, so an
# enemy standing where two adjacent mini blast circles overlap takes _mesh_damage from each one
# independently, exactly as many times as it's touching.
func _spawn_mesh_grenades() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var mini_radius := _radius * _mesh_radius_ratio
	for i in range(_mesh_count):
		var angle := TAU * float(i) / float(_mesh_count)
		var edge_pos := global_position + Vector2.RIGHT.rotated(angle) * _radius
		var mini: Node2D = load("res://scenes/grenade/grenade.tscn").instantiate()
		parent.add_child(mini)
		mini.configure(_sprite.texture, global_position, edge_pos, _mesh_damage, mini_radius, MESH_EXPLODE_DELAY)

func _draw() -> void:
	if not _exploded:
		return
	if _gravity_duration > 0.0:
		draw_circle(Vector2.ZERO, _radius, Color(0.45, 0.15, 0.65, 0.30))
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 32, Color(0.7, 0.3, 1.0, 0.85), 3.0)
	elif _confuse_duration > 0.0:
		draw_circle(Vector2.ZERO, _radius, Color(0.6, 0.6, 0.65, 0.30))
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 32, Color(0.8, 0.8, 0.85, 0.85), 3.0)
	elif _linger_duration > 0.0:
		draw_circle(Vector2.ZERO, _radius, Color(1.0, 0.35, 0.05, 0.30))
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 32, Color(1.0, 0.5, 0.1, 0.85), 3.0)
	elif _distract_duration > 0.0:
		draw_circle(Vector2.ZERO, _radius, Color(1.0, 0.85, 0.1, 0.30))
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 32, Color(1.0, 0.9, 0.2, 0.85), 3.0)
	elif _freeze_duration > 0.0:
		draw_circle(Vector2.ZERO, _radius, Color(FREEZE_COLOR, 0.30))
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 32, Color(FREEZE_COLOR, 0.85), 3.0)
	elif _flash_duration > 0.0:
		draw_circle(Vector2.ZERO, _radius, Color(BLIND_COLOR, 0.30))
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 32, Color(BLIND_COLOR, 0.9), 3.0)
	else:
		draw_circle(Vector2.ZERO, _radius, Color(1.0, 0.5, 0.1, 0.35))
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 32, Color(1.0, 0.6, 0.15, 0.9), 3.0)
