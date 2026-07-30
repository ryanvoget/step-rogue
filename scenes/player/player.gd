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

# Heal-item state (Small Heal Vial, Passive Health Regen Vials, Stim Shot — see
# ItemRegistry's heal_item fields and world.gd/sandbox.gd's _use_heal_item). Regen and speed
# boost are independent, generic, single-slot effects: starting a new one replaces whatever
# was previously running rather than stacking, matching how equipping a new item would.
var _regen_amount := 0
var _regen_interval := 1.0
var _regen_timer := 0.0
var _regen_ticks_left := 0
var _speed_multiplier := 1.0
var _speed_boost_timer := 0.0

# Speed Boost Battery (equipment): tap the green equipment button (not a joystick — see
# item_registry.gd's battery field docs) to cycle ready -> active (speed boost, bar depletes)
# -> recharging (bar refills) -> ready again, repeatable indefinitely. Kept as its own
# multiplier (not _speed_multiplier above, which is the heal_item Stim Shot's boost) and
# combined multiplicatively in _physics_process, so the two effects can't stomp each other if
# both happen to be active at once. GameManager.battery_state/battery_charge mirror this state
# for mobile_controls.gd's button/bar drawing.
var _battery_state: int = 0 # GameManager.BATTERY_READY — see game_manager.gd's plain-int note
var _battery_timer := 0.0
var _battery_multiplier := 1.5
var _battery_active_duration := 10.0
var _battery_recharge_duration := 10.0
var _battery_charges := 0 # activations remaining this run (batteries no longer recharge)
var _battery_speed_multiplier := 1.0

# Force Push Bracelet (equipment): holding/aiming the green joystick (see item_registry.gd's
# force_push field docs) pushes every enemy in a cone toward GameManager.force_push_dir
# continuously back out to the edge of _force_push_range while held and mana remains —
# reusing take_damage's knockback params (0 damage) the same way grenade.gd's gravity well
# reuses them for a continuous pull, just outward instead of inward. Mana never regenerates.
const FORCE_PUSH_KNOCKBACK_SPEED := 520.0 # px/s outward impulse reapplied every frame in-cone —
                                           # comfortably outpaces enemy_basic.gd's SPEED (90)
                                           # against its own KNOCKBACK_FRICTION decay (600/s²)
var _force_push_range := 0.0
var _force_push_arc_degrees := 0.0
var _force_push_mana := 0.0
var _force_push_mana_max := 100.0
var _force_push_mana_drain_rate := 10.0
var _force_push_angle := 0.0 # last joystick-aimed angle used for both the push and its draw
var _force_push_active := false # true while actually channeling (held AND mana > 0) — drives the cone draw

# Hoverboard (equipment): tap the green equipment button (not a joystick — see
# item_registry.gd's hoverboard field docs) to toggle mounted/unmounted — no timer, no bar,
# just a plain on/off state, repeatable indefinitely. Own dedicated multiplier (not
# _speed_multiplier/_battery_speed_multiplier above) combined multiplicatively in
# _physics_process, same reasoning as the battery: independent effects shouldn't be able to
# stomp each other. The board sprite (reusing the item's icon, see configure_hoverboard) sits
# behind the player (see player.tscn's child order) and rotates to track _mouse_angle every
# frame while mounted, so it always reads as "under the feet" regardless of facing direction.
const HOVERBOARD_ICON_TARGET_SIZE := 40.0
var _hoverboard_active := false
var _hoverboard_speed_multiplier := 1.0
const FROZEN_SLOW_MULT := 0.5      # movement multiplier while slowed by a Cryo Unit freeze bolt
const FROZEN_SLOW_DURATION := 1.5
var _frozen_slow_timer := 0.0
var _hoverboard_mount_multiplier := 1.5
@onready var _hoverboard_sprite: Sprite2D = $Hoverboard

# Temporary Invincible Battery (equipment): tap the green equipment button (not a joystick —
# see item_registry.gd's invincible field docs) to toggle invincibility on/off. Drains
# _invincible_mana_max at _invincible_mana_drain_rate per second while active; mana never
# regenerates (same non-regenerating-resource pattern as Force Push Bracelet), and once it
# hits zero the state auto-turns-off and the button greys out for the rest of the run. While
# active, take_damage is a no-op entirely (see is_invincible()) and a pulsing purple glow is
# drawn around the player (see _draw).
var _invincible_active := false
var _invincible_mana := 0.0
var _invincible_mana_max := 100.0
var _invincible_mana_drain_rate := 10.0

# Shield Barrier (Light/Medium/Heavy, a heal_item): tap the blue heal button (not a joystick —
# see item_registry.gd's shield field docs) to arm it once; while active, take_damage is fully
# absorbed by _shield_hp instead of the player's own health, draining it by each hit's damage
# until it hits zero, at which point the shield breaks permanently (checked in take_damage,
# below invincibility — an equipped Invincible Battery takes priority and the shield's pool
# isn't touched while it's active). Reflect Shield (_shield_reflect) additionally deals that
# same damage straight back to whoever attacked, on top of (not instead of) depleting the pool
# exactly like any other shield — see take_damage's attacker param.
var _shield_active := false
var _shield_hp := 0.0
var _shield_hp_max := 0.0
var _shield_reflect := false
var _shield_color := Color(0.4, 0.8, 1.0) # outline colour drawn around the player while active

# Shared aim-ray helper for any green-joystick equipment that previews "what's in front of
# me" before release (Grapple Hook, Sticky Grenade, ...) — see get_aim_target and
# GameManager.equipment_aim_preview/aim_preview_dir/aim_preview_max_distance (set by
# world.gd/sandbox.gd from the equipped item, read by mobile_controls.gd during the throw
# joystick drag and by _draw_aim_preview below). Whichever raycast the live preview line uses
# is also what the actual release logic (world.gd/sandbox.gd's _use_grapple/
# _use_sticky_grenade) uses, so what's shown and what happens always agree.
const AIM_PREVIEW_MASK := 0b1010 # enemies (layer 2) | walls (layer 8)
var _was_previewing_aim := false # tracks the falling edge so the dotted line's last frame gets
                                  # cleared — see _physics_process's queue_redraw() call below
var _was_shield_drawn := false   # same falling-edge tracking for the active-shield outline

# Grapple Hook (equipment): releases into one of two effects depending on what the aim ray
# hits first — dash the player to a wall, or drag an enemy close. World.gd/sandbox.gd own the
# release (_use_grapple); player.gd owns the dash movement.
const GRAPPLE_MAX_DISTANCE := 1200.0 # comfortably longer than the room's ~980px diagonal — the
                                      # ray always finds a wall since they fully enclose the room
const GRAPPLE_DASH_SPEED := 700.0
const GRAPPLE_DASH_ARRIVE_DIST := 8.0
const GRAPPLE_WALL_CLEARANCE := 20.0 # stop this far short of the wall, not on top of it
var _dash_target := Vector2.ZERO
var _dash_active := false

# Teleportation Bracelet (equipment): same green-joystick aim/release lifecycle as any other
# scaleable_throw item (see world.gd/sandbox.gd's dispatch), but instead of a dotted line to
# whatever get_aim_target's raycast hits, this is a free-floating point — not stopped by walls
# or enemies, just clamped to stay inside the room — previewed as a dotted circle
# (_draw_teleport_preview) and, on release, the player is moved there directly (teleport_to).
# GameManager.equipment_teleport (world.gd/sandbox.gd-set) tells _draw() which preview shape to
# use; get_teleport_target is shared between the preview and the actual release so what's shown
# always matches what happens, same principle as get_aim_target.
const TELEPORT_PREVIEW_RADIUS := 27.0 # ~1.5x the player's own collision radius (18, see player.tscn)
const TELEPORT_WALL_T := 28.0 # matches room.gd's WALL_T; room bounds come from GameManager.room_w/play_h
const TELEPORT_MARGIN := 20.0 # clearance from the wall face, same idea as GRAPPLE_WALL_CLEARANCE
const TELEPORT_SENSITIVITY_CURVE := 2.0 # >1 = squared drag response instead of linear — see
                                         # _draw_teleport_preview/world.gd+sandbox.gd's _use_teleport

var _can_attack := true
var _mouse_angle := 0.0
var _shot_damage := -1 # -1 = no weapon-specific override yet, bullet uses its own default
var _barrel_offset := 0.0 # >0 = dual-barrel weapon; fire one bullet from each side instead of one from center
var _shot_freeze_duration := 0.0 # >0 = bullets fully halt whatever they hit for this long (e.g. Freeze Gun)
var _shot_knockback := 0.0 # px/s impulse on hit (e.g. Wave Ray Gun's slight push)
var _shot_wave_max_width := 0.0 # >0 = bullets are expanding elliptical waves (e.g. Wave Ray Gun)

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

# Beam weapons (set via set_beam_stats, e.g. Flamethrower) are a third attack type alongside
# ranged/melee: a continuous cone, active every frame "shoot" is held (no fire_rate cooldown),
# that ticks damage_per_sec to whatever it's touching and applies a burn DOT to anything it
# stops touching (by leaving the cone, or the player releasing/switching weapons).
var _is_beam := false
var _beam_damage_per_sec := 0
var _beam_range := 0.0
var _beam_arc_degrees := 0.0
var _beam_burn_damage := 0
var _beam_burn_duration := 0.0
var _beam_tick_interval := 1.0 # seconds of continuous contact between damage ticks (e.g. Flamethrower's 0.75s)
var _beam_active := false # true while the beam is currently being drawn/firing
var _beam_contact: Dictionary = {} # enemy -> seconds of continuous contact this activation (for the tick)

# Sniper Rifle Blaster: a fourth attack type with no joystick/button at all. Charge state
# lives on GameManager since mobile_controls.gd needs to read/drive it too (drawing the
# charge bar, detecting the arm-tap and the anywhere-on-screen fire-tap). See set_sniper_stats.
var _is_sniper := false
var _sniper_damage := 0
var _sniper_bullet_speed := -1.0

# Thrown melee weapon (e.g. Throwable Beam Sword): a fifth attack type, fired from the same
# aim joystick as ranged weapons. thrown_barrel_offset > 0 throws two, staggered, the same
# way ranged dual-barrel weapons do (e.g. Double Beam Swords vs. Double Pistol Blasters).
# Only once ALL in-flight copies have returned (_thrown_active_count back to 0) can the
# weapon throw again.
const THROWN_WEAPON_SCENE := preload("res://scenes/thrown_weapon/thrown_weapon.tscn")
const THROWN_STAGGER_DELAY := 0.15 # seconds between the two swords' launches when doubled
var _is_thrown_melee := false
var _thrown_damage := 0
var _thrown_radius := 100.0
var _thrown_speed := 520.0
var _thrown_barrel_offset := 0.0
var _thrown_active_count := 0

# Grenade-launcher weapon (e.g. Void Grenade Launcher): a sixth attack type — uses the normal
# aim joystick and _attack_timer/fire_rate cooldown like ranged weapons, but fires a
# grenade.tscn (traveling launcher_distance in front of the player, then exploding) instead
# of a bullet. gravity_duration > 0 makes the explosion a persistent pulling zone instead of
# an instant burst — see grenade.gd.
const LAUNCHER_GRENADE_SCENE := preload("res://scenes/grenade/grenade.tscn")
var _is_launcher := false
var _launcher_damage := 0
var _launcher_distance := 200.0
var _launcher_radius := 100.0
var _launcher_explode_delay := 0.25
var _launcher_gravity_duration := 0.0
var _launcher_gravity_tick_interval := 0.5
# The launcher (Void Grenade Launcher) also machine-guns small lasers while firing, on top of
# lobbing grenades — same rate as the Laser Blaster.
const LAUNCHER_LASER_INTERVAL := 0.2
const LAUNCHER_LASER_DAMAGE := 2
var _launcher_laser_accum := 0.0

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
	GameManager.sniper_fire_requested.connect(_fire_sniper)
	GameManager.thrown_melee_throw_requested.connect(_on_thrown_melee_throw_requested)
	_setup_sprite()
	_setup_weapon()

func _setup_sprite() -> void:
	# Single-frame 32x32 character ("Guy 1"). The movement state machine (_update_sprite) still
	# plays idle/run_up/run_down/run_left/run_right, so each is registered as a one-frame animation
	# of the same texture — the player renders as the 32x32 guy in every state/facing.
	var guy_tex: Texture2D = load("res://assets/Sprites/Guy/Guy 1.png")
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim_name in ["idle", "run_up", "run_down", "run_left", "run_right"]:
		sf.add_animation(anim_name)
		sf.set_animation_loop(anim_name, true)
		sf.add_frame(anim_name, guy_tex)
	_sprite.sprite_frames = sf
	_sprite.play("idle")
	_apply_shirt_color()

func _physics_process(delta: float) -> void:
	# Locked between arming the sniper's charge bar and firing at the tapped target (so a
	# touch meant to aim the shot can never also register as movement), and while a grapple
	# dash is in progress (see _tick_dash, which sets velocity directly below instead).
	var dir := Vector2.ZERO if (GameManager.sniper_armed or _dash_active) \
		else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _frozen_slow_timer > 0.0:
		_frozen_slow_timer -= delta
	var frozen_mult := FROZEN_SLOW_MULT if _frozen_slow_timer > 0.0 else 1.0
	velocity = dir * SPEED * _speed_multiplier * _battery_speed_multiplier * _hoverboard_speed_multiplier * frozen_mult

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
	if _hoverboard_active:
		_hoverboard_sprite.rotation = _mouse_angle
	if _dash_active:
		_tick_dash()
	move_and_slide()
	# Keep the player inside the play area. The canvas can resize a couple times as the device
	# rotation settles at load, and the player may have spawned against the room's earlier size —
	# without this it can end up stranded off-screen below the raised bottom wall, appearing stuck.
	var bm := 16.0
	var r: Rect2 = GameManager.play_rect
	global_position.x = clampf(global_position.x, r.position.x + bm, r.end.x - bm)
	global_position.y = clampf(global_position.y, r.position.y + bm, r.end.y - bm)
	_update_sprite(dir)
	_update_weapon()
	_tick_melee_swings(delta)
	_tick_regen(delta)
	_tick_speed_boost(delta)
	_tick_battery(delta)
	_tick_force_push(delta)
	_tick_invincible(delta)
	if _is_launcher:
		_tick_launcher_laser(delta)

	# Godot's _draw() output persists on the canvas until the next queue_redraw() — calling it
	# only while previewing means the moment the joystick is released, _draw() never runs again
	# to omit the line, so it stays stuck showing the last frame drawn until something unrelated
	# (a melee swing, beam, take_damage flash, ...) happens to redraw the player. Redrawing once
	# more on the falling edge (previewing -> not) forces _draw() to run with the now-false
	# condition, which correctly clears it.
	var previewing_now := GameManager.equipment_aim_preview and GameManager.aim_preview_active and GameManager.aim_preview_dir.length() > 0.0
	# Same falling-edge reasoning for the shield outline: redraw while active, plus one extra
	# frame after it turns off so the ring is cleared.
	var shield_drawn_now := _shield_active and _shield_hp > 0.0
	if previewing_now or _was_previewing_aim or shield_drawn_now or _was_shield_drawn:
		queue_redraw()
	_was_previewing_aim = previewing_now
	_was_shield_drawn = shield_drawn_now

	if _is_sniper:
		GameManager.sniper_charge = minf(GameManager.sniper_charge + delta, GameManager.sniper_charge_time)

	# Auto-fire/swing while the shoot action is held (works for keyboard hold and touch).
	# Beam weapons bypass _try_attack's fire_rate cooldown entirely — they're just "on"
	# every frame the button's held, and "off" (burning whatever they were touching) otherwise.
	if Input.is_action_pressed("shoot"):
		if _is_beam:
			_tick_beam(delta)
		else:
			_try_attack()
	elif _is_beam:
		_stop_beam()

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
func set_ranged_stats(damage: int, fire_rate: float, barrel_offset: float = 0.0, freeze_duration: float = 0.0,
		knockback: float = 0.0, wave_max_width: float = 0.0) -> void:
	_stop_beam()
	_stop_sniper()
	_is_melee = false
	_is_beam = false
	_is_thrown_melee = false
	_is_launcher = false
	GameManager.melee_equipped = false
	GameManager.thrown_melee_equipped = false
	_shot_damage = damage
	_attack_timer.wait_time = fire_rate
	_barrel_offset = barrel_offset
	_shot_freeze_duration = freeze_duration
	_shot_knockback = knockback
	_shot_wave_max_width = wave_max_width

# Applies a melee weapon's tuned gameplay stats (from ItemRegistry) to swing behavior.
# arc_degrees <= 0 keeps the default cone width. use_joystick_aim swaps mobile_controls'
# button-style attack input for the continuous aim joystick guns use (e.g. Metallic Whip),
# while the hit itself still uses melee cone/range logic rather than firing a bullet.
func set_melee_stats(damage: int, attack_rate: float, melee_range: float, knockback: float = 0.0,
		hits: int = 1, arc_degrees: float = -1.0, stun: float = 0.0, use_joystick_aim: bool = false) -> void:
	_stop_beam()
	_stop_sniper()
	_is_melee = true
	_is_beam = false
	_is_thrown_melee = false
	_is_launcher = false
	GameManager.melee_equipped = not use_joystick_aim
	GameManager.thrown_melee_equipped = false
	_melee_damage = damage
	_attack_timer.wait_time = attack_rate
	_melee_range = melee_range
	_melee_knockback = knockback
	_melee_hits = hits
	_melee_arc_degrees = arc_degrees if arc_degrees > 0.0 else DEFAULT_MELEE_ARC_DEGREES
	_melee_stun = stun

# Applies a beam weapon's tuned gameplay stats (from ItemRegistry, e.g. Flamethrower) to
# continuous-fire behavior. Always uses the aim joystick, like ranged weapons — a beam held
# in one spot while swinging around doesn't make sense as a button-press action.
func set_beam_stats(damage_per_sec: int, beam_range: float, arc_degrees: float, burn_damage: int,
		burn_duration: float, tick_interval: float = 1.0) -> void:
	_stop_beam()
	_stop_sniper()
	_is_melee = false
	_is_beam = true
	_is_thrown_melee = false
	_is_launcher = false
	GameManager.melee_equipped = false
	GameManager.thrown_melee_equipped = false
	_beam_damage_per_sec = damage_per_sec
	_beam_range = beam_range
	_beam_arc_degrees = arc_degrees
	_beam_burn_damage = burn_damage
	_beam_burn_duration = burn_duration
	_beam_tick_interval = tick_interval

# Applies the Throwable Beam Sword's tuned gameplay stats. Fires from the main aim joystick,
# but aim-and-release-to-throw (like the grenade's equipment throw joystick) rather than
# hold-to-fire — mobile_controls.gd checks GameManager.thrown_melee_equipped to switch the
# joystick into that mode, emitting thrown_melee_throw_requested on release.
func set_thrown_stats(damage: int, radius: float, speed: float, barrel_offset: float = 0.0) -> void:
	_stop_beam()
	_stop_sniper()
	_is_melee = false
	_is_beam = false
	_is_thrown_melee = true
	_is_launcher = false
	GameManager.melee_equipped = false
	GameManager.thrown_melee_equipped = true
	_thrown_damage = damage
	_thrown_radius = radius
	_thrown_speed = speed
	_thrown_barrel_offset = barrel_offset

# Applies the Void Grenade Launcher's tuned gameplay stats. Uses the normal aim joystick and
# _attack_timer/fire_rate cadence exactly like a ranged weapon — only what gets spawned
# (grenade.tscn instead of bullet.tscn) and how it resolves differs. See _try_launch_grenade.
func set_launcher_stats(damage: int, fire_rate: float, distance: float, radius: float, explode_delay: float,
		gravity_duration: float = 0.0, gravity_tick_interval: float = 0.5) -> void:
	_stop_beam()
	_stop_sniper()
	_is_melee = false
	_is_beam = false
	_is_thrown_melee = false
	_is_launcher = true
	GameManager.melee_equipped = false
	GameManager.thrown_melee_equipped = false
	_attack_timer.wait_time = fire_rate
	_launcher_damage = damage
	_launcher_distance = distance
	_launcher_radius = radius
	_launcher_explode_delay = explode_delay
	_launcher_gravity_duration = gravity_duration
	_launcher_gravity_tick_interval = gravity_tick_interval

# Applies the Sniper Rifle Blaster's tuned gameplay stats. Unlike every other weapon type,
# this has no joystick/button at all — mobile_controls.gd draws a charge bar in that spot
# instead and drives the whole charge/arm/fire flow via GameManager.sniper_* state, calling
# back into _fire_sniper() via the sniper_fire_requested signal (connected in _ready()).
func set_sniper_stats(damage: int, charge_time: float, bullet_speed: float = -1.0) -> void:
	_stop_beam()
	_is_melee = false
	_is_beam = false
	_is_sniper = true
	_is_thrown_melee = false
	_is_launcher = false
	GameManager.melee_equipped = false
	GameManager.thrown_melee_equipped = false
	GameManager.sniper_equipped = true
	GameManager.sniper_charge_time = charge_time
	GameManager.sniper_charge = 0.0
	GameManager.sniper_armed = false
	_sniper_damage = damage
	_sniper_bullet_speed = bullet_speed

# Flushes sniper state when switching to a different weapon type mid-charge/mid-arm, so
# leftover charge/armed state doesn't leak into whatever's equipped next.
func _stop_sniper() -> void:
	_is_sniper = false
	GameManager.sniper_equipped = false
	GameManager.sniper_armed = false
	GameManager.sniper_charge = 0.0

# Fires at the tapped world position (mobile_controls passes the raw touch position — the
# room has no camera scroll/zoom, so viewport and world coordinates coincide). Resets the
# charge bar to start recharging for the next shot; mobile_controls has already cleared
# sniper_armed by the time this runs (see its fire-tap handler).
func _fire_sniper(target_pos: Vector2) -> void:
	if not _is_sniper or bullet_scene == null:
		return
	var angle := (target_pos - global_position).angle()
	_mouse_angle = angle
	_spawn_point.position = Vector2(22, 0).rotated(_mouse_angle)
	GameManager.spawn_bullet(bullet_scene, _spawn_point.global_position, angle, _sniper_damage, _sniper_bullet_speed, -1.0, -1.0, -1.0, true)
	GameManager.sniper_charge = 0.0

# ── Shared green-joystick equipment aim ray (Grapple Hook, Sticky Grenade, ...) ─────────────

# Casts a ray in direction, up to max_distance, and returns whichever of a wall or an enemy
# it hits first: {"is_enemy": bool, "position": Vector2, "collider": Node}. If nothing's hit
# within max_distance (always true for a short-range item like Sticky Grenade; shouldn't
# happen for Grapple Hook's effectively-uncapped range, since walls fully enclose the room),
# "position" falls back to the capped endpoint and "collider" is null.
func get_aim_target(direction: Vector2, max_distance: float) -> Dictionary:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + direction * max_distance)
	query.collision_mask = AIM_PREVIEW_MASK
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return {"is_enemy": false, "position": global_position + direction * max_distance, "collider": null}
	return {
		"is_enemy": result.collider.is_in_group("enemies"),
		"position": result.position,
		"collider": result.collider,
	}

# ── Teleportation Bracelet ───────────────────────────────────────────────────────────────────

# Unlike get_aim_target above, this never raycasts — direction * max_distance lands wherever it
# lands, only clamped to stay inside the room's walls (so the player can't teleport into/past
# them). Shared by the preview (_draw_teleport_preview) and the actual release
# (world.gd/sandbox.gd's _use_teleport), so the dotted circle always shows exactly where a
# release would send the player.
func get_teleport_target(direction: Vector2, max_distance: float) -> Vector2:
	var raw: Vector2 = global_position + direction * max_distance
	var r: Rect2 = GameManager.play_rect
	var min_x := r.position.x + TELEPORT_MARGIN
	var max_x := r.end.x - TELEPORT_MARGIN
	var min_y := r.position.y + TELEPORT_MARGIN
	var max_y := r.end.y - TELEPORT_MARGIN
	return Vector2(clampf(raw.x, min_x, max_x), clampf(raw.y, min_y, max_y))

func teleport_to(pos: Vector2) -> void:
	global_position = pos

# ── Grapple Hook ─────────────────────────────────────────────────────────────────────────

# Dashes the player toward target (a wall hit point, already pulled back GRAPPLE_WALL_CLEARANCE
# by the caller) — locks normal movement input until it arrives (see _dash_active in
# _physics_process), same pattern as the sniper's armed-movement lock.
func start_grapple_dash(target: Vector2) -> void:
	_dash_target = target
	_dash_active = true

func _tick_dash() -> void:
	if global_position.distance_to(_dash_target) <= GRAPPLE_DASH_ARRIVE_DIST:
		_dash_active = false
		velocity = Vector2.ZERO
		return
	velocity = (_dash_target - global_position).normalized() * GRAPPLE_DASH_SPEED

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
	# Sniper fires only via the charge-bar-then-tap-target flow (see _fire_sniper), never
	# through the normal hold-to-fire path.
	if not _can_attack or _is_sniper:
		return
	if _is_melee:
		_try_melee_attack()
	elif _is_thrown_melee:
		_try_throw_sword()
	elif _is_launcher:
		_try_launch_grenade()
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
		GameManager.spawn_bullet(bullet_scene, pos + perp, angle, _shot_damage, -1.0, _shot_freeze_duration, _shot_knockback, _shot_wave_max_width, true)
		get_tree().create_timer(_attack_timer.wait_time / 2.0).timeout.connect(
			func(): GameManager.spawn_bullet(bullet_scene, pos - perp, angle, _shot_damage, -1.0, _shot_freeze_duration, _shot_knockback, _shot_wave_max_width, true)
		)
	else:
		GameManager.spawn_bullet(bullet_scene, _spawn_point.global_position, _mouse_angle, _shot_damage, -1.0, _shot_freeze_duration, _shot_knockback, _shot_wave_max_width, true)

# Fires a grenade a fixed _launcher_distance in front of the player (not aimed at a target
# like the equipment grenade or sniper) — same _attack_timer/fire_rate cooldown as ranged.
# Rapid 2-damage lasers fired while "shoot" is held, independent of the slower grenade cadence,
# so the Void Grenade Launcher chips away between lobs.
func _tick_launcher_laser(delta: float) -> void:
	if bullet_scene == null or not Input.is_action_pressed("shoot"):
		_launcher_laser_accum = 0.0
		return
	_launcher_laser_accum += delta
	while _launcher_laser_accum >= LAUNCHER_LASER_INTERVAL:
		_launcher_laser_accum -= LAUNCHER_LASER_INTERVAL
		GameManager.spawn_bullet(bullet_scene, _spawn_point.global_position, _mouse_angle,
			LAUNCHER_LASER_DAMAGE, -1.0, -1.0, -1.0, -1.0, true)

func _try_launch_grenade() -> void:
	_can_attack = false
	_attack_timer.start()
	var origin := _spawn_point.global_position
	var landing := origin + Vector2.RIGHT.rotated(_mouse_angle) * _launcher_distance
	GameManager.spawn_launched_grenade(LAUNCHER_GRENADE_SCENE, _weapon.texture, origin, landing,
		_launcher_damage, _launcher_radius, _launcher_explode_delay,
		_launcher_gravity_duration, _launcher_gravity_tick_interval)

# Throws the sword (or two, staggered, if _thrown_barrel_offset > 0 — see Double Beam
# Swords); _can_attack stays false (blocking _try_attack) until every copy has returned,
# rather than the usual _attack_timer cooldown — its "cooldown" is however long the round
# trip actually takes, not a fixed duration.
func _try_throw_sword() -> void:
	if _thrown_active_count > 0:
		return
	_can_attack = false
	var origin := _spawn_point.global_position
	var dir := Vector2.RIGHT.rotated(_mouse_angle)
	if _thrown_barrel_offset > 0.0:
		# Same stagger pattern as ranged dual-barrel weapons' second shot, just applied to
		# a second sword launch instead of a second bullet.
		var perp := Vector2.RIGHT.rotated(_mouse_angle + PI / 2.0) * _thrown_barrel_offset
		_launch_sword(origin + perp, dir)
		get_tree().create_timer(THROWN_STAGGER_DELAY).timeout.connect(
			func(): _launch_sword(origin - perp, dir)
		)
	else:
		_launch_sword(origin, dir)

func _launch_sword(origin: Vector2, direction: Vector2) -> void:
	_thrown_active_count += 1
	GameManager.record_melee_attempt() # thrown-melee counts toward melee accuracy
	var sword := GameManager.spawn_thrown_weapon(THROWN_WEAPON_SCENE, _weapon.texture,
		origin, direction, self, _thrown_damage, _thrown_radius, _thrown_speed)
	if sword:
		sword.returned.connect(_on_sword_returned)
	else:
		_on_sword_returned()

func _on_sword_returned() -> void:
	_thrown_active_count = maxi(_thrown_active_count - 1, 0)
	if _thrown_active_count <= 0:
		_can_attack = true

# Fired by mobile_controls.gd when the main aim joystick is released past the dead zone
# while a thrown-melee weapon is equipped (aim-and-release, like the grenade throw joystick,
# rather than hold-to-fire). _try_throw_sword's own in-flight check still applies.
func _on_thrown_melee_throw_requested(angle: float) -> void:
	if not _is_thrown_melee:
		return
	_mouse_angle = angle
	_try_throw_sword()

func _try_melee_attack() -> void:
	_can_attack = false
	_attack_timer.start()
	AudioManager.play_swing()
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
	_active_melee_swings.append({"angle": angle, "remaining": duration, "hit": {}, "scored": false})
	GameManager.record_melee_attempt()

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
				# Count this swing as "connected" once, the first time it lands on anything.
				if not swing["scored"]:
					swing["scored"] = true
					GameManager.record_melee_hit()
	_active_melee_swings = _active_melee_swings.filter(func(s): return s["remaining"] > 0.0)

# Ticks the beam every physics frame it's held: ongoing contact accrues toward a damage tick
# every _beam_tick_interval seconds (fractional seconds carry over, so DPS is exact rather
# than rounding per-frame), and anything that drops out of contact this frame (left the
# cone/range) starts burning immediately rather than waiting for the whole beam to release.
# Active contact also clears any leftover burn on that enemy — burn is only meant to apply
# once the hitbox is fully off, not layered on top of live beam damage.
func _tick_beam(delta: float) -> void:
	_beam_active = true
	var half_arc := deg_to_rad(_beam_arc_degrees / 2.0)
	var still_contacted := {}
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var to_enemy: Vector2 = enemy.global_position - global_position
		var dist := to_enemy.length()
		if dist > _beam_range:
			continue
		var angle_diff := absf(wrapf(to_enemy.angle() - _mouse_angle, -PI, PI))
		if angle_diff > half_arc:
			continue
		if enemy.has_method("clear_burn"):
			enemy.clear_burn()
		var contact_time: float = _beam_contact.get(enemy, 0.0) + delta
		if contact_time >= _beam_tick_interval:
			contact_time -= _beam_tick_interval
			if enemy.has_method("take_damage"):
				enemy.take_damage(_beam_damage_per_sec)
		still_contacted[enemy] = contact_time
	for enemy in _beam_contact:
		if not still_contacted.has(enemy) and is_instance_valid(enemy) and enemy.has_method("apply_burn"):
			enemy.apply_burn(_beam_burn_damage, _beam_burn_duration)
	_beam_contact = still_contacted
	queue_redraw()

# Called when the beam stops firing entirely (button released, or the weapon is switched
# away from mid-beam) — whatever it was still touching starts burning.
func _stop_beam() -> void:
	if not _beam_active and _beam_contact.is_empty():
		return
	for enemy in _beam_contact:
		if is_instance_valid(enemy) and enemy.has_method("apply_burn"):
			enemy.apply_burn(_beam_burn_damage, _beam_burn_duration)
	_beam_contact.clear()
	_beam_active = false
	queue_redraw()

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

const SHIELD_OUTLINE_RADIUS := 26.0

func _draw() -> void:
	# Active shield: ring the player in the shield type's colour (glow + crisp outline).
	if _shield_active and _shield_hp > 0.0:
		draw_arc(Vector2.ZERO, SHIELD_OUTLINE_RADIUS, 0.0, TAU, 40, Color(_shield_color, 0.22), 7.0)
		draw_arc(Vector2.ZERO, SHIELD_OUTLINE_RADIUS, 0.0, TAU, 40, Color(_shield_color, 0.95), 3.0)
	if _show_hitbox:
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
	if _beam_active:
		_draw_beam()
	if _force_push_active:
		_draw_force_push_cone()
	if _invincible_active:
		_draw_invincible_glow()
	if GameManager.equipment_aim_preview and GameManager.aim_preview_active and GameManager.aim_preview_dir.length() > 0.0:
		if GameManager.equipment_teleport:
			_draw_teleport_preview()
		else:
			_draw_aim_preview()

# Floating dotted circle at get_teleport_target's result — never a raycasted line, since
# Teleportation Bracelet ignores walls/enemies entirely. Same shared-target principle as
# _draw_aim_preview: this is exactly where release sends the player. Unlike a normal throwable's
# linear scaleable_throw distance, this squares the drag fraction (TELEPORT_SENSITIVITY_CURVE)
# — a short flick barely moves the circle, a full drag still reaches the full range — so it's
# much easier to land on a specific nearby spot instead of every small twitch of the thumb
# jumping the circle a huge distance across the map.
func _draw_teleport_preview() -> void:
	var max_dist: float = GameManager.aim_preview_max_distance
	if GameManager.equipment_scaleable_throw:
		max_dist *= pow(GameManager.aim_preview_fraction, TELEPORT_SENSITIVITY_CURVE)
	var target: Vector2 = get_teleport_target(GameManager.aim_preview_dir, max_dist)
	var local_center: Vector2 = to_local(target)
	var col := Color(0.6, 0.3, 1.0, 0.85)
	const DOT_COUNT := 16
	for i in range(DOT_COUNT):
		var a := TAU * float(i) / float(DOT_COUNT)
		draw_circle(local_center + Vector2(TELEPORT_PREVIEW_RADIUS, 0.0).rotated(a), 2.5, col)

# Dotted line from the player to whatever get_aim_target finds first — pink for an enemy
# (Grapple Hook drags it in / Sticky Grenade sticks to it), blue for a wall or the max-range
# point (Grapple Hook dashes to it / Sticky Grenade explodes there) — using the exact same
# ray and range the actual release logic uses, so the preview never lies about what happens.
# For "scaleable throwing" items (e.g. Distraction Grenade), the range itself is scaled live by
# how far the throw joystick is currently dragged, matching _throw_grenade's actual distance.
func _draw_aim_preview() -> void:
	var max_dist: float = GameManager.aim_preview_max_distance
	if GameManager.equipment_scaleable_throw:
		max_dist *= GameManager.aim_preview_fraction
	var target: Dictionary = get_aim_target(GameManager.aim_preview_dir, max_dist)
	var local_end: Vector2 = to_local(target["position"])
	var col := Color(0.95, 0.25, 0.9, 0.85) if target["is_enemy"] else Color(0.5, 0.85, 1.0, 0.85)
	const DASH_LEN := 10.0
	const GAP_LEN := 6.0
	var dist := local_end.length()
	if dist < 1.0:
		return
	var dir := local_end / dist
	var traveled := 0.0
	while traveled < dist:
		var seg_end := minf(traveled + DASH_LEN, dist)
		draw_line(dir * traveled, dir * seg_end, col, 2.5)
		traveled = seg_end + GAP_LEN
	draw_circle(local_end, 6.0, col)

# Solid flame-colored cone, redrawn every frame the beam fires (queue_redraw() is called
# from _tick_beam each tick) so it tracks the live aim angle exactly like the beam's own
# hit detection does.
func _draw_beam() -> void:
	var half_arc := deg_to_rad(_beam_arc_degrees / 2.0)
	const SEGMENTS := 16
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	for i in range(SEGMENTS + 1):
		var a := _mouse_angle - half_arc + (2.0 * half_arc) * (float(i) / float(SEGMENTS))
		points.append(Vector2(_beam_range, 0.0).rotated(a))
	draw_colored_polygon(points, Color(1.0, 0.45, 0.1, 0.6))
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], Color(1.0, 0.6, 0.15, 0.85), 2.0)

# Solid green cone, redrawn every frame the Force Push Bracelet channels (queue_redraw() is
# called from _tick_force_push each tick) — same construction as _draw_beam, just green and
# using _force_push_range/_force_push_arc_degrees/_force_push_angle (the joystick's aim, not
# the beam's _mouse_angle) instead of the beam's.
func _draw_force_push_cone() -> void:
	var half_arc := deg_to_rad(_force_push_arc_degrees / 2.0)
	const SEGMENTS := 16
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	for i in range(SEGMENTS + 1):
		var a := _force_push_angle - half_arc + (2.0 * half_arc) * (float(i) / float(SEGMENTS))
		points.append(Vector2(_force_push_range, 0.0).rotated(a))
	draw_colored_polygon(points, Color(0.25, 0.9, 0.4, 0.35))
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], Color(0.35, 1.0, 0.5, 0.8), 2.0)

# Pulsing purple glow around the player while Temporary Invincible Battery is active
# (queue_redraw() is called from _tick_invincible/toggle_invincible each tick/edge).
func _draw_invincible_glow() -> void:
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 150.0)
	draw_circle(Vector2.ZERO, 28.0, Color(0.6, 0.2, 1.0, 0.18 * pulse))
	draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 32, Color(0.75, 0.35, 1.0, 0.75 * pulse), 3.0)

# Extra params exist only so bullet.gd's _apply_hit can call take_damage() uniformly
# regardless of target_group ("enemies" vs "player") — the player has no knockback/stun/
# freeze reactions (yet), so most are accepted and ignored rather than branching bullet.gd on
# which kind of body it just hit. attacker is the exception: a Reflect Shield uses it to deal
# the same damage straight back to whoever attacked (bullet.gd's shooter for lasers,
# enemy_basic.gd's ATTACK state passing itself for melee) — null/ignored for any hit source
# that doesn't pass one.
func take_damage(amount: int, _knockback_dir: Vector2 = Vector2.ZERO, _knockback_force: float = 0.0,
		_stun_duration: float = 0.0, _stun_color: Color = Color(1.0, 1.0, 1.0), is_freeze: bool = false,
		attacker: Node2D = null) -> void:
	if _invincible_active:
		return
	# Cryo Unit's freeze bolts briefly slow the player (no full stun) — only if they actually
	# land (shield/invincibility above still fully block).
	if is_freeze:
		_frozen_slow_timer = FROZEN_SLOW_DURATION
	if _shield_active and _shield_hp > 0.0:
		_shield_hp = maxf(_shield_hp - amount, 0.0)
		GameManager.shield_hp = _shield_hp
		if _shield_hp <= 0.0:
			_shield_active = false
			GameManager.shield_active = false
			GameManager.shield_broken = true
		if _shield_reflect and attacker != null and is_instance_valid(attacker) and attacker.has_method("take_damage"):
			attacker.take_damage(amount)
		return
	health = max(0, health - amount)
	health_changed.emit(health, max_health)
	GameManager.health_changed.emit(health, max_health)
	if health == 0:
		died.emit()
		GameManager.player_died.emit()
		queue_free()

# ── Heal items (Small Heal Vial, Passive Health Regen Vials, Stim Shot) ─────────────────────

func heal(amount: int) -> void:
	health = mini(health + amount, max_health)
	health_changed.emit(health, max_health)
	GameManager.health_changed.emit(health, max_health)

func heal_full() -> void:
	heal(max_health)

# Starts (or replaces) a heal-over-time effect: amount_per_tick HP every interval seconds,
# for duration seconds total.
func start_regen(amount_per_tick: int, interval: float, duration: float) -> void:
	_regen_amount = amount_per_tick
	_regen_interval = interval
	_regen_timer = interval
	_regen_ticks_left = int(round(duration / interval))

func _tick_regen(delta: float) -> void:
	if _regen_ticks_left <= 0:
		return
	_regen_timer -= delta
	if _regen_timer <= 0.0:
		_regen_timer += _regen_interval
		_regen_ticks_left -= 1
		heal(_regen_amount)

# Starts (or replaces) a temporary movement speed multiplier (e.g. Stim Shot's 1.5x).
func apply_speed_boost(multiplier: float, duration: float) -> void:
	_speed_multiplier = multiplier
	_speed_boost_timer = duration

func _tick_speed_boost(delta: float) -> void:
	if _speed_boost_timer <= 0.0:
		return
	_speed_boost_timer -= delta
	if _speed_boost_timer <= 0.0:
		_speed_multiplier = 1.0

# ── Speed Boost Battery (equipment) ─────────────────────────────────────────────────────────

# Called once by world.gd/sandbox.gd right after equipping a battery-type item — resets to the
# ready state (e.g. when switching items in the sandbox dropdown mid-cycle).
const BATTERY_MAX_USES := 5 # activations per run (batteries no longer recharge)

func configure_battery(multiplier: float, active_duration: float, recharge_duration: float) -> void:
	_battery_multiplier = multiplier
	_battery_active_duration = active_duration
	_battery_recharge_duration = recharge_duration # unused now — batteries have fixed uses
	_battery_state = GameManager.BATTERY_READY
	_battery_speed_multiplier = 1.0
	_battery_charges = BATTERY_MAX_USES
	GameManager.battery_state = GameManager.BATTERY_READY
	GameManager.battery_charge = 1.0
	GameManager.battery_charges = BATTERY_MAX_USES

# Called by world.gd/sandbox.gd on GameManager.battery_activate_requested (the green equipment
# button tap). No-ops outside the ready state — mobile_controls.gd already gates the tap to
# only register then, this is just the authoritative guard.
func activate_battery() -> void:
	if _battery_state != GameManager.BATTERY_READY or _battery_charges <= 0:
		return
	_battery_charges -= 1
	GameManager.battery_charges = _battery_charges
	_battery_state = GameManager.BATTERY_ACTIVE
	_battery_timer = _battery_active_duration
	_battery_speed_multiplier = _battery_multiplier
	GameManager.battery_state = GameManager.BATTERY_ACTIVE

# No recharge phase anymore: when the active window ends it just returns to READY (usable again
# only while charges remain — mobile_controls hides the button once they're spent).
func _tick_battery(delta: float) -> void:
	if _battery_state != GameManager.BATTERY_ACTIVE:
		return
	_battery_timer -= delta
	GameManager.battery_charge = clampf(_battery_timer / _battery_active_duration, 0.0, 1.0)
	if _battery_timer <= 0.0:
		_battery_speed_multiplier = 1.0
		_battery_state = GameManager.BATTERY_READY
		GameManager.battery_state = GameManager.BATTERY_READY
		GameManager.battery_charge = 1.0

# ── Force Push Bracelet (equipment) ─────────────────────────────────────────────────────────

# Called once by world.gd/sandbox.gd right after equipping a force_push-type item — resets
# mana to full (e.g. when switching items in the sandbox dropdown).
func configure_force_push(range_px: float, arc_degrees: float, mana_max: float, drain_rate: float) -> void:
	_force_push_range = range_px
	_force_push_arc_degrees = arc_degrees
	_force_push_mana_max = mana_max
	_force_push_mana_drain_rate = drain_rate
	_force_push_mana = mana_max
	_force_push_active = false
	GameManager.force_push_mana = mana_max
	GameManager.force_push_mana_max = mana_max
	GameManager.force_push_held = false
	GameManager.force_push_dir = Vector2.ZERO

# Polled every physics frame — GameManager.force_push_held/force_push_dir are set directly by
# mobile_controls.gd's green-joystick press/drag/release (like aim_preview_active, not a
# one-shot signal, since this needs continuous per-frame state). The cone points wherever the
# joystick is currently aimed (force_push_dir), not the player's facing direction.
func _tick_force_push(delta: float) -> void:
	if not GameManager.force_push_held or _force_push_mana <= 0.0 or GameManager.force_push_dir.length() <= 0.0:
		if _force_push_active:
			_force_push_active = false
			queue_redraw()
		return
	_force_push_active = true
	_force_push_angle = GameManager.force_push_dir.angle()
	_force_push_mana = maxf(_force_push_mana - _force_push_mana_drain_rate * delta, 0.0)
	GameManager.force_push_mana = _force_push_mana
	if _force_push_mana <= 0.0:
		GameManager.force_push_held = false

	var half_arc := deg_to_rad(_force_push_arc_degrees / 2.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var to_enemy: Vector2 = enemy.global_position - global_position
		var dist := to_enemy.length()
		if dist > _force_push_range or dist < 0.001:
			continue
		var angle_diff := absf(wrapf(to_enemy.angle() - _force_push_angle, -PI, PI))
		if angle_diff > half_arc:
			continue
		# Fling the enemy toward the wall in the push direction; force_push handles the
		# on-impact damage + stun (see enemy_basic.gd). Skips enemies already stunned (mid-slam).
		if enemy.has_method("force_push"):
			enemy.force_push(to_enemy / dist, FORCE_PUSH_KNOCKBACK_SPEED)
	queue_redraw()

# ── Hoverboard (equipment) ──────────────────────────────────────────────────────────────────

# Called once by world.gd/sandbox.gd right after equipping a hoverboard-type item — resets to
# unmounted (e.g. when switching items in the sandbox dropdown).
func configure_hoverboard(tex: Texture2D, speed_multiplier: float) -> void:
	_hoverboard_mount_multiplier = speed_multiplier
	_hoverboard_active = false
	_hoverboard_speed_multiplier = 1.0
	_hoverboard_sprite.visible = false
	if tex != null:
		var size := tex.get_size()
		var largest: float = max(size.x, size.y)
		var scale_factor: float = HOVERBOARD_ICON_TARGET_SIZE / largest if largest > 0.0 else 1.0
		_hoverboard_sprite.texture = tex
		_hoverboard_sprite.scale = Vector2(scale_factor, scale_factor)
	GameManager.hoverboard_active = false

# Called by world.gd/sandbox.gd on the green equipment button's plain tap
# (GameManager.deploy_equipment_requested), same dispatch as placeable/mine/barrier. Simple
# on/off flip, no timer or resource — repeatable indefinitely.
func toggle_hoverboard() -> void:
	_hoverboard_active = not _hoverboard_active
	_hoverboard_speed_multiplier = _hoverboard_mount_multiplier if _hoverboard_active else 1.0
	_hoverboard_sprite.visible = _hoverboard_active
	if _hoverboard_active:
		_hoverboard_sprite.rotation = _mouse_angle
	GameManager.hoverboard_active = _hoverboard_active

# ── Temporary Invincible Battery (equipment) ────────────────────────────────────────────────

# Called once by world.gd/sandbox.gd right after equipping an invincible-type item — resets to
# off with full mana (e.g. when switching items in the sandbox dropdown).
func configure_invincible(mana_max: float, drain_rate: float) -> void:
	_invincible_mana_max = mana_max
	_invincible_mana_drain_rate = drain_rate
	_invincible_mana = mana_max
	_invincible_active = false
	GameManager.invincible_active = false
	GameManager.invincible_mana = mana_max
	GameManager.invincible_mana_max = mana_max
	queue_redraw() # clears any glow left over from a previously equipped invincible item

# Called by world.gd/sandbox.gd on the green equipment button's plain tap. Simple on/off flip
# like Hoverboard, except gated by remaining mana to turn ON (can't restart once empty — mana
# never regenerates) and it drains while active (_tick_invincible).
func toggle_invincible() -> void:
	if _invincible_active:
		_invincible_active = false
	elif _invincible_mana > 0.0:
		_invincible_active = true
	GameManager.invincible_active = _invincible_active
	queue_redraw() # forces _draw() to re-evaluate the glow immediately either way

func is_invincible() -> bool:
	return _invincible_active

func _tick_invincible(delta: float) -> void:
	if not _invincible_active:
		return
	_invincible_mana = maxf(_invincible_mana - _invincible_mana_drain_rate * delta, 0.0)
	GameManager.invincible_mana = _invincible_mana
	if _invincible_mana <= 0.0:
		_invincible_active = false
		GameManager.invincible_active = false
	queue_redraw() # keeps the glow's pulse animating, and clears it on the frame it turns off

# ── Shield Barrier (Light/Medium/Heavy, a heal_item) ────────────────────────────────────────

# Called once by world.gd/sandbox.gd right after equipping a shield-type item — resets to
# un-armed with a full HP pool (e.g. when switching items in the sandbox dropdown).
func configure_shield(hp_max: float, reflect: bool = false, color: Color = Color(0.4, 0.8, 1.0)) -> void:
	_shield_hp_max = hp_max
	_shield_hp = hp_max
	_shield_active = false
	_shield_reflect = reflect
	_shield_color = color
	GameManager.shield_active = false
	GameManager.shield_broken = false
	GameManager.shield_hp = hp_max
	GameManager.shield_hp_max = hp_max

# Called by world.gd/sandbox.gd on every blue heal button tap — a repeatable on/off toggle
# (world.gd's _use_heal_item deliberately bypasses the usual one-shot heal_item_deployed gate
# for shield-type items so this can fire more than once). Turning it off does NOT refill or
# reset _shield_hp; toggling back on resumes with whatever was left. Does nothing once the
# shield has broken (_shield_hp <= 0.0) — permanently unusable for the rest of the run.
func toggle_shield() -> void:
	if _shield_hp <= 0.0:
		return
	_shield_active = not _shield_active
	GameManager.shield_active = _shield_active
