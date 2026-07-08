extends CharacterBody2D

const SPEED     := 180.0
const FRAME_W   := 64
const FRAME_H   := 64
const IDLE_FPS  := 8.0
const RUN_FPS   := 10.0

const SHIRT_HUES := {
	"blue":   0.583,
	"red":    0.0,
	"yellow": 0.144,
	"green":  0.361,
}

@export var bullet_scene: PackedScene
@export var max_health := 100

var health: int
var _can_attack := true
var _mouse_angle := 0.0
var _shot_damage := -1 # -1 = no weapon-specific override yet, bullet uses its own default
var _barrel_offset := 0.0 # >0 = dual-barrel weapon; fire one bullet from each side instead of one from center

# Melee weapons (set via set_melee_stats) swing in a cone instead of firing a bullet.
const DEFAULT_MELEE_ARC_DEGREES := 100.0 # total width of the swipe cone in front of the player
var _is_melee := false
var _melee_damage := 0
var _melee_range := 0.0
var _melee_knockback := 0.0
var _melee_hits := 1 # >1 = that many staggered strikes per swing (e.g. dual daggers)
var _melee_arc_degrees := DEFAULT_MELEE_ARC_DEGREES # per-weapon override (e.g. Metallic Whip's narrower cone)
var _melee_stun := 0.0 # seconds to stun on hit, instead of/alongside knockback (e.g. Metallic Whip)
var _is_swinging := false # true while the swing tween owns _weapon.rotation
var _show_hitbox := false # true briefly while the melee hit cone is telegraphed
var _hitbox_angle := 0.0

# Active melee swings, each: {angle, remaining, hit}. Checked every physics frame (not just
# once at swing start) so a target that wasn't in range/arc yet still gets caught if it moves
# into the (player-relative) cone before the swing ends. "hit" tracks who's already been
# struck this swing so a lingering target isn't hit repeatedly across multiple frames.
var _active_melee_swings: Array = []

@onready var _spawn_point: Marker2D    = $BulletSpawnPoint
@onready var _attack_timer: Timer      = $ShootCooldown
@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _weapon: Sprite2D         = $Weapon

signal health_changed(current: int, maximum: int)
signal died

func _ready() -> void:
	health = max_health
	add_to_group("player")
	_attack_timer.timeout.connect(func(): _can_attack = true)
	_setup_sprite()
	_setup_weapon()

func _setup_sprite() -> void:
	var idle_tex: Texture2D = load("res://assets/Sprites/idle_spritesheet.png")
	var run_tex:  Texture2D = load("res://assets/Sprites/run_spritesheet.png")
	var sf := SpriteFrames.new()
	sf.remove_animation("default")

	# Idle: 5 frames from idle_spritesheet
	sf.add_animation("idle")
	sf.set_animation_speed("idle", IDLE_FPS)
	sf.set_animation_loop("idle", true)
	for i in range(5):
		var atlas := AtlasTexture.new()
		atlas.atlas = idle_tex
		atlas.region = Rect2(i * FRAME_W, 0, FRAME_W, FRAME_H)
		sf.add_frame("idle", atlas)

	# Directional run: run_spritesheet layout
	# [0]=up1 [1]=up2 [2]=down1 [3]=down2 [4]=right1 [5]=right2 [6]=left1 [7]=left2
	var run_anims := {
		"run_up":    [0, 1],
		"run_down":  [2, 3],
		"run_right": [4, 5],
		"run_left":  [6, 7],
	}
	for anim_name in run_anims:
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, RUN_FPS)
		sf.set_animation_loop(anim_name, true)
		for idx in run_anims[anim_name]:
			var atlas := AtlasTexture.new()
			atlas.atlas = run_tex
			atlas.region = Rect2(idx * FRAME_W, 0, FRAME_W, FRAME_H)
			sf.add_frame(anim_name, atlas)

	_sprite.sprite_frames = sf
	_sprite.play("idle")
	_apply_shirt_color()

func _physics_process(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED

	# GameManager.mobile_aim_dir is set by the right joystick in mobile_controls.gd.
	# It's zero when the joystick is idle, non-zero when pushed past the dead zone.
	if GameManager.mobile_aim_dir.length() > 0.1:
		_mouse_angle = GameManager.mobile_aim_dir.angle()
	elif OS.has_feature("ios") or OS.has_feature("android"):
		# Mobile, no aim joystick active: face movement direction, hold last angle when still.
		if dir.length() > 0.1:
			_mouse_angle = dir.angle()
	else:
		# Desktop: aim at mouse cursor.
		var to_mouse := get_global_mouse_position() - global_position
		if to_mouse.length() > 1.0:
			_mouse_angle = to_mouse.angle()

	_spawn_point.position = Vector2(22, 0).rotated(_mouse_angle)
	move_and_slide()
	_update_sprite(dir)
	_update_weapon()
	_tick_melee_swings(delta)

	# Auto-fire/swing while the shoot action is held (works for keyboard hold and touch).
	if Input.is_action_pressed("shoot"):
		_try_attack()

const WEAPON_TARGET_SIZE := 40.0

func _setup_weapon() -> void:
	_weapon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_weapon_texture(load("res://assets/Sprites/assault_rifle.png"))

# Swaps the held weapon sprite to an arbitrary texture (e.g. an ItemRegistry icon),
# normalizing scale since icon assets vary wildly in native resolution/aspect ratio.
# Offset stays in texture-pixel space (half the width) so the pivot sits at the
# grip/left edge regardless of scale, matching the tuned assault_rifle.png convention.
func set_weapon_texture(tex: Texture2D) -> void:
	_weapon.texture = tex
	var size := tex.get_size()
	var largest: float = max(size.x, size.y)
	var scale_factor: float = WEAPON_TARGET_SIZE / largest if largest > 0.0 else 1.0
	_weapon.scale  = Vector2(scale_factor, scale_factor)
	_weapon.offset = Vector2(size.x / 2.0, 0)

# Applies a ranged weapon's tuned gameplay stats (from ItemRegistry) to shooting behavior.
func set_ranged_stats(damage: int, fire_rate: float, barrel_offset: float = 0.0) -> void:
	_is_melee = false
	GameManager.melee_equipped = false
	_shot_damage = damage
	_attack_timer.wait_time = fire_rate
	_barrel_offset = barrel_offset

# Applies a melee weapon's tuned gameplay stats (from ItemRegistry) to swing behavior.
# arc_degrees <= 0 keeps the default cone width. use_joystick_aim swaps mobile_controls'
# button-style attack input for the continuous aim joystick guns use (e.g. Metallic Whip),
# while the hit itself still uses melee cone/range logic rather than firing a bullet.
func set_melee_stats(damage: int, attack_rate: float, melee_range: float, knockback: float = 0.0,
		hits: int = 1, arc_degrees: float = -1.0, stun: float = 0.0, use_joystick_aim: bool = false) -> void:
	_is_melee = true
	GameManager.melee_equipped = not use_joystick_aim
	_melee_damage = damage
	_attack_timer.wait_time = attack_rate
	_melee_range = melee_range
	_melee_knockback = knockback
	_melee_hits = hits
	_melee_arc_degrees = arc_degrees if arc_degrees > 0.0 else DEFAULT_MELEE_ARC_DEGREES
	_melee_stun = stun

func _apply_shirt_color() -> void:
	var shader := load("res://scenes/character/shirt_recolor.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("target_hue", SHIRT_HUES.get(SaveManager.shirt_color, 0.583))
	_sprite.material = mat

func _update_weapon() -> void:
	# While a melee swing tween is playing, it owns _weapon.rotation — don't fight it.
	if not _is_swinging:
		_weapon.rotation = _mouse_angle
	_weapon.flip_v = absf(_mouse_angle) > PI / 2

func _update_sprite(dir: Vector2) -> void:
	var anim: String
	if dir == Vector2.ZERO:
		anim = "idle"
	elif absf(dir.x) >= absf(dir.y):
		anim = "run_right" if dir.x > 0.0 else "run_left"
	elif dir.y < 0.0:
		anim = "run_up"
	else:
		anim = "run_down"
	if _sprite.animation != anim:
		_sprite.play(anim)
	_sprite.flip_h = false

func _unhandled_input(event: InputEvent) -> void:
	# On mobile, touch-to-mouse emulation converts every tap to a left mouse button
	# press. Skip that path — shooting is handled by mobile_controls + _physics_process.
	if OS.has_feature("ios") or OS.has_feature("android"):
		return
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_try_attack()
	elif event.is_action_pressed("shoot"):
		_try_attack()

func _try_attack() -> void:
	if not _can_attack:
		return
	if _is_melee:
		_try_melee_attack()
	else:
		_try_ranged_attack()

func _try_ranged_attack() -> void:
	if bullet_scene == null:
		return
	_can_attack = false
	_attack_timer.start()
	if _barrel_offset > 0.0:
		# Stagger the second barrel by half the cooldown so the two guns alternate
		# (left, right, left, right...) instead of firing both lasers in lockstep.
		var perp := Vector2.RIGHT.rotated(_mouse_angle + PI / 2.0) * _barrel_offset
		var pos := _spawn_point.global_position
		var angle := _mouse_angle
		GameManager.spawn_bullet(bullet_scene, pos + perp, angle, _shot_damage)
		get_tree().create_timer(_attack_timer.wait_time / 2.0).timeout.connect(
			func(): GameManager.spawn_bullet(bullet_scene, pos - perp, angle, _shot_damage)
		)
	else:
		GameManager.spawn_bullet(bullet_scene, _spawn_point.global_position, _mouse_angle, _shot_damage)

func _try_melee_attack() -> void:
	_can_attack = false
	_attack_timer.start()
	var duration := clampf(_attack_timer.wait_time * 0.5, 0.05, 0.25)
	_play_melee_swing(duration)
	_flash_melee_hitbox(duration)
	var angle := _mouse_angle
	_start_melee_swing(angle, duration)
	# Extra staggered strikes for dual-wielded melee weapons (e.g. Daggers): each lands
	# a beat after the previous, using the aim captured at swing start — same stagger
	# pattern as the ranged dual-barrel weapons' second shot. Each gets its own active
	# window so a target that dodges the first strike can still be caught by later ones.
	var stagger := _attack_timer.wait_time / 2.0
	for i in range(1, _melee_hits):
		get_tree().create_timer(stagger * i).timeout.connect(
			func(): _start_melee_swing(angle, duration)
		)

func _start_melee_swing(angle: float, duration: float) -> void:
	_active_melee_swings.append({"angle": angle, "remaining": duration, "hit": {}})

# Re-checks every active swing each physics frame instead of once at swing start, so a
# target outside _melee_range/the cone at the moment of the swing still gets hit if it
# (or the player) moves into range before the swing ends. Uses live global_position, same
# as _draw()'s hitbox flash (drawn in local space, so it already visually tracks the
# player) — this keeps what's shown and what actually connects in sync.
func _tick_melee_swings(delta: float) -> void:
	if _active_melee_swings.is_empty():
		return
	var half_arc := deg_to_rad(_melee_arc_degrees / 2.0)
	for swing in _active_melee_swings:
		swing["remaining"] -= delta
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if swing["hit"].has(enemy):
				continue
			var to_enemy: Vector2 = enemy.global_position - global_position
			var dist := to_enemy.length()
			if dist > _melee_range:
				continue
			var angle_diff := absf(wrapf(to_enemy.angle() - swing["angle"], -PI, PI))
			if angle_diff > half_arc:
				continue
			if enemy.has_method("take_damage"):
				var knockback_dir := to_enemy.normalized() if dist > 0.001 else Vector2.RIGHT.rotated(swing["angle"])
				enemy.take_damage(_melee_damage, knockback_dir, _melee_knockback, _melee_stun)
				swing["hit"][enemy] = true
	_active_melee_swings = _active_melee_swings.filter(func(s): return s["remaining"] > 0.0)

# Quick arc swipe of the weapon sprite across the swing cone for visual feedback.
# Duration scales with attack rate so faster/slower melee weapons still read as a "swing".
func _play_melee_swing(duration: float) -> void:
	var half_arc := deg_to_rad(_melee_arc_degrees / 2.0)
	_is_swinging = true
	_weapon.rotation = _mouse_angle - half_arc
	var tween := create_tween()
	tween.tween_property(_weapon, "rotation", _mouse_angle + half_arc, duration)
	tween.finished.connect(func(): _is_swinging = false)

# Draws the exact cone/range used by _apply_melee_hit() so it's obvious what will
# actually get hit, fading in sync with the swing animation.
func _flash_melee_hitbox(duration: float) -> void:
	_hitbox_angle = _mouse_angle
	_show_hitbox = true
	queue_redraw()
	get_tree().create_timer(duration).timeout.connect(func():
		_show_hitbox = false
		queue_redraw()
	)

func _draw() -> void:
	if not _show_hitbox:
		return
	var half_arc := deg_to_rad(_melee_arc_degrees / 2.0)
	const SEGMENTS := 16
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	for i in range(SEGMENTS + 1):
		var a := _hitbox_angle - half_arc + (2.0 * half_arc) * (float(i) / float(SEGMENTS))
		points.append(Vector2(_melee_range, 0.0).rotated(a))
	draw_colored_polygon(points, Color(1.0, 0.9, 0.2, 0.28))
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], Color(1.0, 0.9, 0.2, 0.7), 2.0)

func take_damage(amount: int) -> void:
	health = max(0, health - amount)
	health_changed.emit(health, max_health)
	GameManager.health_changed.emit(health, max_health)
	if health == 0:
		died.emit()
		GameManager.player_died.emit()
		queue_free()
