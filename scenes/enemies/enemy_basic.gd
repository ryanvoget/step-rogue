extends CharacterBody2D

signal died

enum State { IDLE, CHASE, ATTACK }

# Weapon/attack style (see TYPES and world.gd's _spawn_enemies_for_room). STAFF is a melee
# swing up close; LASER/FREEZE/WAVE hold at range and fire the matching projectile; FLAME is a
# short-range continuous cone. Sandbox dummies default to STAFF so sandbox is unchanged.
enum Weapon { STAFF, LASER, FREEZE, WAVE, FLAME }

# The enemy roster from the Enemy Data sheet — HP, body radius (px diameter / 2), weapon,
# special behavior, gold dropped, and color. world.gd picks which of these to spawn per floor;
# configure_type() applies one. Damage/fire cadence per weapon live in WEAPON_DMG/WEAPON_CD.
const TYPES := {
	"M":      {"hp": 20, "radius": 20.0, "weapon": Weapon.STAFF, "special": "",          "gold":  3, "color": Color(1.00, 0.55, 0.10)}, # Orange
	"L":      {"hp": 20, "radius": 20.0, "weapon": Weapon.LASER, "special": "",          "gold":  5, "color": Color(0.25, 0.45, 0.95)}, # Blue
	"Void":   {"hp": 35, "radius": 25.0, "weapon": Weapon.LASER, "special": "fast_fire", "gold":  8, "color": Color(0.32, 0.34, 0.38)}, # Dark Grey
	"Warp":   {"hp": 35, "radius": 25.0, "weapon": Weapon.LASER, "special": "teleport",  "gold":  8, "color": Color(0.60, 0.25, 0.85)}, # Purple
	"Crater": {"hp": 35, "radius": 25.0, "weapon": Weapon.STAFF, "special": "fast_swing","gold":  8, "color": Color(0.45, 0.28, 0.13)}, # Brown
	"Cryo":   {"hp": 35, "radius": 25.0, "weapon": Weapon.FREEZE,"special": "",          "gold":  8, "color": Color(0.50, 0.80, 1.00)}, # Light Blue
	"Solar":  {"hp": 35, "radius": 25.0, "weapon": Weapon.FLAME, "special": "",          "gold":  8, "color": Color(0.90, 0.15, 0.15)}, # Red
	"Nebula": {"hp": 35, "radius": 25.0, "weapon": Weapon.WAVE,  "special": "",          "gold":  8, "color": Color(1.00, 0.45, 0.75)}, # Pink
	"Nova":   {"hp": 50, "radius": 30.0, "weapon": Weapon.LASER, "special": "grenade",   "gold": 15, "color": Color(0.30, 0.85, 0.35)}, # Green
	# Bosses spawn alone on their floor (world.gd's BOSS_BY_FLOOR): Boss1 floor 15, Boss2 floor 25.
	"Boss1":  {"hp": 250, "radius": 55.0, "weapon": Weapon.STAFF, "special": "boss1", "gold":  50, "color": Color(1.00, 0.80, 0.62)}, # Peach — melee, swings 3x speed
	"Boss2":  {"hp": 500, "radius": 55.0, "weapon": Weapon.LASER, "special": "boss2", "gold": 100, "color": Color(0.06, 0.06, 0.09)}, # Black — laser 4x + teleport/8x burst
	# Final boss (floor 35): laser 5x, lobs a random grenade every 5s. Phase 2 (world.gd enables it
	# via enable_boss_split) also splits into two every 10s, each half HP. Gold 9999 (one big payout).
	"BossF":  {"hp": 1000, "radius": 75.0, "weapon": Weapon.LASER, "special": "boss_final", "gold": 9999, "color": Color(0.45, 0.40, 0.85)}, # phase 1 = 1000 HP; phase 2 respawns at 500 (world.gd)
}
# Damage per attack and cooldown (seconds) per weapon — not in the sheet, tuned here.
const WEAPON_DMG := {Weapon.STAFF: 6, Weapon.LASER: 3, Weapon.FREEZE: 3, Weapon.WAVE: 4, Weapon.FLAME: 2}
const WEAPON_CD  := {Weapon.STAFF: 1.1, Weapon.LASER: 1.4, Weapon.FREEZE: 1.6, Weapon.WAVE: 1.6, Weapon.FLAME: 0.25}
const FREEZE_BULLET_COLOR := Color(0.25, 0.55, 1.0)
const WAVE_BULLET_WIDTH := 60.0
const FLAME_RANGE := 150.0       # Solar closes to this and burns continuously in a cone
const FLAME_ARC := 0.6           # half-angle (radians) of the flame cone
const FLAME_COLOR := Color(1.0, 0.5, 0.1)
const TELEPORT_INTERVAL := 3.0   # Warp jumps to a random spot this often
const GRENADE_INTERVAL := 3.0    # Nova lobs a blast grenade this often
const BOSS2_TELEPORT_INTERVAL := 10.0 # Boss2 blinks to a random spot this often
const BOSS2_RAPID_DURATION := 2.0     # ...then fires at 8x (instead of 4x) for this long after
const BOSSF_GRENADE_INTERVAL := 5.0   # Final boss lobs a random grenade this often
const BOSSF_SPLIT_INTERVAL := 8.0     # Final boss phase 2: splits in two this often
const BOSSF_MAX_SPLITS := 3           # ...but only 3 halvings deep (2^3 = 8 enemies max)
const BOSSF_GRENADE_KINDS := ["molitov", "mesh", "freeze", "sticky"]

# Phase 2 only: emitted when the final boss splits — world.gd spawns a second boss at `pos` with
# `hp` health (this boss keeps the other half). Kept a signal so world.gd owns the enemy count and
# the child's died wiring (the boss can't touch world's _enemies_alive itself).
signal boss_split(pos: Vector2, hp: int, radius: float, generation: int)
const ENEMY_GRENADE_DMG := 5
const ENEMY_GRENADE_RADIUS := 100.0
const COIN_SCENE := preload("res://scenes/coin/coin.tscn")
const GRENADE_SCENE := preload("res://scenes/grenade/grenade.tscn")
# Play-area bounds come from GameManager.room_w/play_h (published by room.gd once it fits the
# screen), so teleports and the per-frame clamp always match the actual playable area on any
# device — see _clamp_to_play_area.
const WALL_T := 28.0

# Sandbox-only behaviors (see sandbox.gd's enemy action dropdown), selected via sandbox_action
# while sandbox_mode is true. NEUTRAL matches the original sandbox dummy (still, doesn't move).
enum SandboxAction { NEUTRAL, MOVING, ATTACKING, SHOOTING }

const SPEED       := 90.0
const MELEE_SPEED_MULT := 1.5 # STAFF (melee) enemies move this much faster than others
const DETECT_DIST := 2000.0  # larger than the room diagonal (~1145px) so enemies aggro across the
                             # whole map — they detect and pursue/attack the player from anywhere
const ATTACK_DIST := 36.0
const STAFF_RANGE := 90.0        # reach of the enemy staff's cone hitbox — melee enemies strike
const STAFF_ARC_DEGREES := 100.0 # when the player is within this cone (shown as a wedge on swing)
const STAFF_WALL_SLAM_DMG := 5   # force-push wall slam (see force_push)
const ATTACK_DMG  := 8
const ATTACK_CD   := 1.2
const KNOCKBACK_FRICTION := 600.0 # px/sec^2 deceleration applied to knockback velocity
const STUN_FLASH_INTERVAL := 0.05 # flash toggles this often while stunned (e.g. Metallic Whip, Freeze Gun)
const BURN_TICK_INTERVAL := 1.0 # seconds between burn damage ticks (e.g. Flamethrower)
const BURN_FLASH_INTERVAL := 0.05 # orange flash toggles this often while burning
const BURN_FLASH_COLOR := Color(1.0, 0.55, 0.1)
const CONFUSE_FLASH_INTERVAL := 0.05 # white flash toggles this often while confused
const CONFUSE_FLASH_COLOR := Color(1.0, 1.0, 1.0)
const THAW_SLOW_MULTIPLIER := 0.5 # movement speed while thawing (50% slower)
const THAW_SLOW_DURATION := 3.0 # seconds — applies automatically whenever ANY freeze-flagged
                                 # stun (take_damage's is_freeze param, e.g. Freeze Gun, Ice
                                 # Grenade) expires, not just specific items
const BLIND_FLASH_INTERVAL := 0.05 # yellow flash toggles this often while blinded (Flash Grenade)
const BLIND_FLASH_COLOR := Color(1.0, 1.0, 0.3)
const SHOOT_RANGE := 260.0 # SHOOTER kind stops approaching and starts firing inside this range
const SWING_FLASH_DURATION := 0.18 # seconds the melee swing arc telegraph stays drawn per strike
const MELEE_BODY_COLOR := Color(0.85, 0.20, 0.20)
const SHOOTER_BODY_COLOR := Color(0.70, 0.25, 0.85) # purple, so shooters read differently at a glance

const SANDBOX_ROOM_WIDTH   := 480.0 # matches room.gd's ROOM_W — the room is a fixed single screen
const SANDBOX_PATROL_Y     := 160.0 # "top of the screen", but clear of the sandbox HUD dropdowns
                                     # (which extend down to ~y134) rather than tucked under the wall
# Turn-around margin from each wall — must clear the wall thickness (room.gd's WALL_T=28) PLUS
# this enemy's own collision radius (18, see enemy_basic.tscn) plus a small buffer, or
# move_and_slide's wall collision stops it before the position check below ever fires,
# pinning it against the wall instead of turning around.
const SANDBOX_PATROL_MARGIN := 52.0
const SANDBOX_SHOOT_INTERVAL := 0.25 # matches Laser Blaster's fire_rate
const SANDBOX_SHOOT_DAMAGE   := 1    # matches Laser Blaster's damage
const SANDBOX_BULLET_SCENE := preload("res://scenes/bullets/bullet.tscn")

@export var max_health    := 10
@export var sandbox_mode  := false

var sandbox_action: int = SandboxAction.NEUTRAL # set by sandbox.gd's enemy action dropdown

# Per-instance stats — configure_type() overrides these from TYPES for world enemies. The
# defaults keep unconfigured/sandbox dummies behaving as the original red melee unit.
var type_name := ""
var _weapon: int = Weapon.STAFF
var _special := ""
var _gold := 0
var _radius := 18.0
var _body_color := MELEE_BODY_COLOR
var _attack_dmg := ATTACK_DMG
var _attack_cd := ATTACK_CD
var _move_speed := SPEED
var _shoot_timer := 0.0
var _swing_flash_timer := 0.0 # >0 while the melee swing arc telegraph is showing
var _swing_angle := 0.0
var _teleport_timer := TELEPORT_INTERVAL
var _grenade_timer := GRENADE_INTERVAL
var _boss2_teleport_timer := BOSS2_TELEPORT_INTERVAL # Boss2: countdown to next blink
var _boss2_rapid_timer := 0.0                        # Boss2: remaining seconds of 8x rapid fire
var _bossf_grenade_timer := BOSSF_GRENADE_INTERVAL   # Final boss: countdown to next grenade
var _bossf_split_timer := BOSSF_SPLIT_INTERVAL       # Final boss phase 2: countdown to next split
var _bossf_split_enabled := false                    # phase 2 flag (world.gd calls enable_boss_split)
var _split_generation := 0                           # how many times this lineage has halved (cap 3)
var _staff_range := STAFF_RANGE                      # melee reach (Boss1 gets 2.5x — set in configure_type)
var _flame_active := false      # true while Solar is burning the player (drives the cone draw)
var _flame_angle := 0.0

var health: int
var _dead := false # set on death so a second same-frame hit can't emit died() twice
var _force_pushed := false # true while flying from a Force Push Bracelet — slams into the wall
var _state  := State.IDLE
var _player: Node2D = null
var _attack_timer := 0.0
var _knockback_vel := Vector2.ZERO
var _stun_timer := 0.0
var _stun_flash_timer := 0.0
var _stun_flash_on := false
var _stun_flash_color := Color(1.0, 1.0, 1.0)
var _freeze_pending_thaw := false # true while the current stun was caused by a freeze effect,
                                   # so _tick_stun knows to start the thaw-slow when it expires
var _slow_timer := 0.0
var _slow_multiplier := 1.0
var _burn_timer := 0.0
var _burn_tick_timer := 0.0
var _burn_damage := 0
var _burn_flash_timer := 0.0
var _burn_flash_on := false
var _confuse_timer := 0.0
var _confuse_flash_timer := 0.0
var _confuse_flash_on := false
var _distract_timer := 0.0
var _distract_target := Vector2.ZERO
var _blind_timer := 0.0
var _blind_flash_timer := 0.0
var _blind_flash_on := false
var _sandbox_patrol_dir := 1.0
var _sandbox_shoot_timer := 0.0
var _being_pulled := false # true while a grapple pull tween owns global_position directly

func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	# Give each enemy its own collision circle sized to its body radius (bigger units are
	# physically bigger), rather than sharing the scene's fixed 18px shape.
	_update_collision_radius()

# Resizes the collision circle to the current _radius (called at spawn and when a final-boss split
# shrinks the body).
func _update_collision_radius() -> void:
	var cs := get_node_or_null("CollisionShape2D")
	if cs != null:
		var shape := CircleShape2D.new()
		shape.radius = _radius
		cs.shape = shape

# Applies one of the TYPES rows (see the Enemy Data sheet) — HP, radius, weapon, special, gold,
# color. Call before add_child(); _ready() then sizes the collision shape and inits health.
func configure_type(type_key: String) -> void:
	if not TYPES.has(type_key):
		return
	var t: Dictionary = TYPES[type_key]
	type_name = type_key
	max_health = t["hp"]
	health = t["hp"]
	_radius = t["radius"]
	_body_color = t["color"]
	_weapon = t["weapon"]
	_special = t["special"]
	_gold = t["gold"]
	_attack_dmg = WEAPON_DMG[_weapon]
	_attack_cd = WEAPON_CD[_weapon]
	if _special == "fast_swing" or _special == "fast_fire":
		_attack_cd *= 0.5
	elif _special == "boss2":
		_attack_cd /= 6.0 # Boss2's base fire rate is 6x (ramps to 20x for 2s after each teleport)
	elif _special == "boss_final":
		_attack_cd /= 6.0 # Final boss fires at 6x
	if _special == "boss1":
		_attack_dmg = 5 # Boss1 swings at base speed but hits for 5
	_staff_range = STAFF_RANGE * 2.5 if _special == "boss1" else STAFF_RANGE # Boss1 has extra reach
	# Melee (STAFF) enemies move faster so they can close the gap and swing.
	_move_speed = SPEED * MELEE_SPEED_MULT if _weapon == Weapon.STAFF else SPEED

func _physics_process(delta: float) -> void:
	_resolve_player()
	_tick_stun(delta)
	_tick_burn(delta)
	_tick_confuse(delta)
	_tick_slow(delta)
	_tick_blind(delta)
	if _swing_flash_timer > 0.0:
		_swing_flash_timer -= delta
		queue_redraw() # animate/clear the melee swing telegraph
	_tick_specials(delta)
	_tick(delta)
	if _confuse_timer > 0.0:
		velocity = -velocity
	if _slow_timer > 0.0:
		velocity *= _slow_multiplier
	_apply_knockback(delta)
	move_and_slide()
	# Force Push Bracelet: while being flung, slam into the wall in that direction for damage + a
	# brief stun; if the shove decays without reaching a wall, just stop tracking it.
	if _force_pushed:
		if is_on_wall():
			_force_pushed = false
			take_damage(STAFF_WALL_SLAM_DMG, Vector2.ZERO, 0.0, 0.5)
		elif _knockback_vel.length() <= 1.0:
			_force_pushed = false
	_apply_separation()
	_clamp_to_play_area()

# Called by player.gd's Force Push Bracelet: fling this enemy in `dir` at `speed`, marking it so
# it takes damage + a stun when it hits the wall. Ignored while stunned (e.g. mid-slam), so a held
# push can't chain-slam it every frame.
func force_push(dir: Vector2, speed: float) -> void:
	if _stun_timer > 0.0:
		return
	_knockback_vel = dir * speed
	_force_pushed = true

# Pushes apart any enemies whose bodies overlap, so a gravity well (Void/Magnetic Grenade) or a
# Distraction Grenade pulling several onto the same point can't stack them into a single blob —
# they settle side by side instead, staying countable. Position-based so it corrects even against
# a strong pull; runs before the play-area clamp so the nudge can't push anyone out of bounds.
func _apply_separation() -> void:
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self:
			continue
		var d: Vector2 = global_position - other.global_position
		var dist := d.length()
		var min_dist: float = _radius + other._radius
		if dist < min_dist and dist > 0.01:
			global_position += d.normalized() * (min_dist - dist) * 0.5

# Hard bound: keep the whole body inside the room's playable area every frame, so nothing —
# a Warp teleport, knockback, or a gravity-well/force-push shove — can ever leave it (walls only
# stop normal movement; direct position changes bypass them).
func _clamp_to_play_area() -> void:
	var r: Rect2 = GameManager.play_rect
	global_position.x = clampf(global_position.x, r.position.x + _radius, r.end.x - _radius)
	global_position.y = clampf(global_position.y, r.position.y + _radius, r.end.y - _radius)

# While stunned, the AI state machine is skipped entirely (see _tick's early return) and
# a white flash pulses every STUN_FLASH_INTERVAL to telegraph it, independent of knockback. If
# this stun was caused by a freeze effect (_freeze_pending_thaw), expiring here ("thawing")
# starts the movement-speed slow below instead of returning to normal speed immediately.
func _tick_stun(delta: float) -> void:
	if _stun_timer <= 0.0:
		return
	_stun_timer -= delta
	_stun_flash_timer -= delta
	if _stun_flash_timer <= 0.0 or _stun_timer <= 0.0:
		_stun_flash_timer = STUN_FLASH_INTERVAL
		_stun_flash_on = _stun_timer > 0.0 and not _stun_flash_on
		queue_redraw()
	if _stun_timer <= 0.0 and _freeze_pending_thaw:
		_freeze_pending_thaw = false
		_slow_timer = THAW_SLOW_DURATION
		_slow_multiplier = THAW_SLOW_MULTIPLIER

func _tick_slow(delta: float) -> void:
	if _slow_timer <= 0.0:
		return
	_slow_timer -= delta
	if _slow_timer <= 0.0:
		_slow_multiplier = 1.0

# Applies/restarts a burn DOT: damage ticks once every BURN_TICK_INTERVAL for duration
# seconds, independent of and unaffected by any active stun/knockback, flashing orange every
# BURN_FLASH_INTERVAL to telegraph it (same pulse pattern as stun's white/blue flash). Called
# when a beam weapon (e.g. Flamethrower) stops touching this enemy — see
# player.gd::_tick_beam/_stop_beam.
func apply_burn(damage: int, duration: float) -> void:
	_burn_damage = damage
	_burn_timer = duration
	_burn_tick_timer = BURN_TICK_INTERVAL
	_burn_flash_timer = BURN_FLASH_INTERVAL
	_burn_flash_on = true
	queue_redraw()

# Cancels any in-progress burn immediately — called every frame a beam is actively touching
# this enemy, since burn is only meant to apply once the hitbox is fully off (not layered on
# top of live beam damage if the beam re-touches before the burn would've finished).
func clear_burn() -> void:
	if _burn_timer <= 0.0:
		return
	_burn_timer = 0.0
	_burn_flash_on = false
	queue_redraw()

func _tick_burn(delta: float) -> void:
	if _burn_timer <= 0.0:
		return
	_burn_timer -= delta
	_burn_tick_timer -= delta
	if _burn_tick_timer <= 0.0:
		_burn_tick_timer += BURN_TICK_INTERVAL
		take_damage(_burn_damage)
	_burn_flash_timer -= delta
	if _burn_flash_timer <= 0.0 or _burn_timer <= 0.0:
		_burn_flash_timer = BURN_FLASH_INTERVAL
		_burn_flash_on = _burn_timer > 0.0 and not _burn_flash_on
		queue_redraw()

# Smoke Grenade: for duration seconds, whatever velocity the AI/sandbox logic computes each
# frame gets reversed (see _physics_process) so the enemy moves the opposite way — applied as a
# post-process step rather than a separate state, so it works uniformly regardless of which
# state/sandbox_action produced the velocity. Flashes white every CONFUSE_FLASH_INTERVAL,
# same pulse pattern as burn/stun.
func apply_confuse(duration: float) -> void:
	_confuse_timer = duration
	_confuse_flash_timer = CONFUSE_FLASH_INTERVAL
	_confuse_flash_on = true
	queue_redraw()

func _tick_confuse(delta: float) -> void:
	if _confuse_timer <= 0.0:
		return
	_confuse_timer -= delta
	_confuse_flash_timer -= delta
	if _confuse_flash_timer <= 0.0 or _confuse_timer <= 0.0:
		_confuse_flash_timer = CONFUSE_FLASH_INTERVAL
		_confuse_flash_on = _confuse_timer > 0.0 and not _confuse_flash_on
		queue_redraw()

# Grapple Hook: drags this enemy directly to target over duration seconds. Suspends the AI
# state machine for that long (_being_pulled, checked in _tick) so it doesn't fight the pull
# — a plain Tween on global_position, not a velocity/knockback effect, since the destination
# is a fixed point rather than a direction/force.
# Distraction Grenade: overrides normal AI/sandbox targeting entirely for duration seconds,
# making this enemy walk straight toward target_pos regardless of where it is on the map
# (called on every enemy in the group when the grenade explodes — see grenade.gd's _explode
# distract branch) — then resumes its normal state machine once the timer runs out. No damage,
# pure crowd control. Checked in _tick() below, ahead of the sandbox_mode/state-machine
# branches, so it overrides those too (useful for seeing the effect clearly in sandbox tests).
func apply_distract(target_pos: Vector2, duration: float) -> void:
	_distract_target = target_pos
	_distract_timer = duration

# Flash Grenade: for duration seconds this enemy's own attacks miss the player entirely — its
# melee swing (State.ATTACK, once actual melee attacks exist) skips dealing damage, and any
# bullet it fires while blinded is spawned with a mask that can never hit the player (see
# GameManager.spawn_enemy_bullet's will_miss param and _tick_sandbox_shooting below), so it
# visually "goes around" instead of connecting. Whether a shot misses is decided at the moment
# it's fired — a bullet already in flight isn't retroactively affected if the blind wears off
# mid-flight. Flashes yellow every BLIND_FLASH_INTERVAL, same pulse pattern as burn/stun/confuse.
func apply_blind(duration: float) -> void:
	_blind_timer = duration
	_blind_flash_timer = BLIND_FLASH_INTERVAL
	_blind_flash_on = true
	queue_redraw()

func _tick_blind(delta: float) -> void:
	if _blind_timer <= 0.0:
		return
	_blind_timer -= delta
	_blind_flash_timer -= delta
	if _blind_flash_timer <= 0.0 or _blind_timer <= 0.0:
		_blind_flash_timer = BLIND_FLASH_INTERVAL
		_blind_flash_on = _blind_timer > 0.0 and not _blind_flash_on
		queue_redraw()

func is_blinded() -> bool:
	return _blind_timer > 0.0

# Special behaviors that run independently of the attack state machine: Warp teleports on a
# timer, Nova lobs a blast grenade on a timer. Suspended while crowd-controlled so CC still
# reads clearly.
func _tick_specials(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _being_pulled or _stun_timer > 0.0 or _distract_timer > 0.0:
		return
	if _special == "teleport":
		_teleport_timer -= delta
		if _teleport_timer <= 0.0:
			_teleport_timer = TELEPORT_INTERVAL
			var tr: Rect2 = GameManager.play_rect
			var mr := _radius + 8.0
			global_position = Vector2(randf_range(tr.position.x + mr, tr.end.x - mr), randf_range(tr.position.y + mr, tr.end.y - mr))
			queue_redraw()
	elif _special == "grenade":
		_grenade_timer -= delta
		if _grenade_timer <= 0.0:
			_grenade_timer = GRENADE_INTERVAL
			if not is_blinded():
				_throw_grenade_at_player()
	elif _special == "boss2":
		# Every 10s blink to a random spot, then rapid-fire at 20x for 2s before dropping back to 8x.
		_boss2_teleport_timer -= delta
		if _boss2_teleport_timer <= 0.0:
			_boss2_teleport_timer = BOSS2_TELEPORT_INTERVAL
			var tr: Rect2 = GameManager.play_rect
			var mr := _radius + 8.0
			global_position = Vector2(randf_range(tr.position.x + mr, tr.end.x - mr), randf_range(tr.position.y + mr, tr.end.y - mr))
			_boss2_rapid_timer = BOSS2_RAPID_DURATION
			_attack_cd = WEAPON_CD[Weapon.LASER] / 20.0
			queue_redraw()
		if _boss2_rapid_timer > 0.0:
			_boss2_rapid_timer -= delta
			if _boss2_rapid_timer <= 0.0:
				_attack_cd = WEAPON_CD[Weapon.LASER] / 6.0
	elif _special == "boss_final":
		# Lob a random grenade at the player every 5s.
		_bossf_grenade_timer -= delta
		if _bossf_grenade_timer <= 0.0:
			_bossf_grenade_timer = BOSSF_GRENADE_INTERVAL
			if not is_blinded():
				_throw_boss_grenade()
		# Phase 2: split in two every 10s (each half HP) until too small.
		if _bossf_split_enabled:
			_bossf_split_timer -= delta
			if _bossf_split_timer <= 0.0:
				_bossf_split_timer = BOSSF_SPLIT_INTERVAL
				if _split_generation < BOSSF_MAX_SPLITS: # only 3 halvings deep
					_split_generation += 1
					var half: int = int(health / 2)
					health = half
					max_health = half
					_radius *= 0.5 # each halving also shrinks the body by half
					_update_collision_radius()
					queue_redraw()
					boss_split.emit(global_position, half, _radius, _split_generation)

# Phase 2: called by world.gd right after configure_type so this boss (and its split children)
# start dividing every 10s.
func enable_boss_split() -> void:
	_bossf_split_enabled = true
	_bossf_split_timer = BOSSF_SPLIT_INTERVAL

# Final boss grenade: one of molitov/mesh/freeze/sticky lobbed at the player. See grenade.gd's
# configure_enemy_grenade for how each kind lands on the player.
func _throw_boss_grenade() -> void:
	var parent := get_parent()
	if parent == null or _player == null:
		return
	var kind: String = BOSSF_GRENADE_KINDS[randi() % BOSSF_GRENADE_KINDS.size()]
	var g: Node2D = GRENADE_SCENE.instantiate()
	parent.add_child(g)
	g.configure_enemy_grenade(kind, global_position, _player.global_position, ENEMY_GRENADE_DMG, ENEMY_GRENADE_RADIUS)

func _throw_grenade_at_player() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var g: Node2D = GRENADE_SCENE.instantiate()
	parent.add_child(g)
	var tex: Texture2D = load("res://assets/icons/Blast_Grenade_Asset.png")
	g.configure_enemy_blast(tex, global_position, _player.global_position, ENEMY_GRENADE_DMG, ENEMY_GRENADE_RADIUS, 0.25)

func grapple_pull_to(target: Vector2, duration: float) -> void:
	_being_pulled = true
	var tween := create_tween()
	tween.tween_property(self, "global_position", target, duration)
	tween.finished.connect(func(): _being_pulled = false)

# Knockback is an additive impulse on top of the state-machine velocity so a melee hit
# can shove the enemy back without interrupting/overriding its chase or attack logic.
func _apply_knockback(delta: float) -> void:
	if _knockback_vel.length() <= 1.0:
		_knockback_vel = Vector2.ZERO
		return
	velocity += _knockback_vel
	_knockback_vel = _knockback_vel.move_toward(Vector2.ZERO, KNOCKBACK_FRICTION * delta)

func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var hits := get_tree().get_nodes_in_group("player")
	_player = hits[0] if hits.size() > 0 else null

func _tick(delta: float) -> void:
	if _being_pulled:
		velocity = Vector2.ZERO
		return
	if _stun_timer > 0.0:
		velocity = Vector2.ZERO
		return
	if _distract_timer > 0.0:
		_distract_timer -= delta
		var to_target := _distract_target - global_position
		velocity = to_target.normalized() * _move_speed if to_target.length() > 1.0 else Vector2.ZERO
		if to_target.length() > 1.0:
			look_at(_distract_target)
		return
	if sandbox_mode and sandbox_action == SandboxAction.NEUTRAL:
		velocity = Vector2.ZERO
		return
	if sandbox_mode and sandbox_action == SandboxAction.MOVING:
		_tick_sandbox_moving()
		return
	if sandbox_mode and sandbox_action == SandboxAction.SHOOTING:
		velocity = Vector2.ZERO
		_tick_sandbox_shooting(delta)
		return
	# ATTACKING (sandbox) falls through to the same chase/attack state machine below that
	# real (non-sandbox) enemies use, to actually "simulate the real attacking in game"
	# rather than a separate simplified copy of it.
	if _player == null:
		velocity = Vector2.ZERO
		return

	var dist := global_position.distance_to(_player.global_position)

	# The engage range depends on the weapon: STAFF strikes at its cone hitbox reach, FLAME burns
	# at short range, and the projectile weapons hold at SHOOT_RANGE.
	var engage := _staff_range
	if _weapon == Weapon.FLAME:
		engage = FLAME_RANGE
	elif _weapon != Weapon.STAFF:
		engage = SHOOT_RANGE

	_flame_active = false
	match _state:
		State.IDLE:
			velocity = Vector2.ZERO
			if dist < DETECT_DIST:
				_state = State.CHASE
				queue_redraw()

		State.CHASE:
			if dist <= engage:
				_state = State.ATTACK
				velocity = Vector2.ZERO
				_attack_timer = 0.4 # brief windup on entering range
				queue_redraw()
			elif dist > DETECT_DIST * 1.5:
				_state = State.IDLE
				queue_redraw()
			else:
				var dir := (_player.global_position - global_position).normalized()
				velocity = dir * _move_speed
				look_at(_player.global_position)

		State.ATTACK:
			velocity = Vector2.ZERO
			look_at(_player.global_position)
			if _weapon == Weapon.FLAME:
				_flame_attack(delta, dist)
			elif _weapon == Weapon.STAFF:
				_melee_attack(delta, dist)
			else:
				_ranged_attack(delta)
			# Leave ATTACK once the player is well outside this weapon's engage band.
			if dist > engage * (2.0 if _weapon == Weapon.STAFF else 1.25):
				_state = State.CHASE
				queue_redraw()

func _melee_attack(delta: float, dist: float) -> void:
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		# Strike when the player is within the staff's cone hitbox reach.
		if dist <= _staff_range and _player.has_method("take_damage") and _blind_timer <= 0.0:
			_player.take_damage(_attack_dmg, Vector2.ZERO, 0.0, 0.0, Color(1.0, 1.0, 1.0), false, self)
		# Swing arc telegraph fires whether the strike landed or whiffed (blind).
		_swing_angle = (_player.global_position - global_position).angle()
		_swing_flash_timer = SWING_FLASH_DURATION
		queue_redraw()
		_attack_timer = _attack_cd

func _ranged_attack(delta: float) -> void:
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = _attack_cd
		var angle := (_player.global_position - global_position).angle()
		var freeze := 1.5 if _weapon == Weapon.FREEZE else 0.0
		var wave := WAVE_BULLET_WIDTH if _weapon == Weapon.WAVE else 0.0
		GameManager.spawn_enemy_bullet(SANDBOX_BULLET_SCENE, global_position, angle, _attack_dmg, is_blinded(), self, freeze, wave)

# Solar's flamethrower: continuous damage while the player is inside the short-range cone,
# ticking every _attack_cd. Draws the cone (see _draw) while _flame_active.
func _flame_attack(delta: float, dist: float) -> void:
	_flame_angle = (_player.global_position - global_position).angle()
	if dist <= FLAME_RANGE and not is_blinded():
		_flame_active = true
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack_timer = _attack_cd
			if _player.has_method("take_damage"):
				_player.take_damage(_attack_dmg, Vector2.ZERO, 0.0, 0.0, Color(1.0, 1.0, 1.0), false, self)
	queue_redraw()

# "Moving": patrols left-to-right along the top of the room, bouncing off the margins near
# each wall. Y is force-locked to the patrol lane every frame so it stays "on the top of the
# screen" regardless of where the dummy was originally spawned.
func _tick_sandbox_moving() -> void:
	global_position.y = SANDBOX_PATROL_Y
	if global_position.x >= SANDBOX_ROOM_WIDTH - SANDBOX_PATROL_MARGIN:
		_sandbox_patrol_dir = -1.0
	elif global_position.x <= SANDBOX_PATROL_MARGIN:
		_sandbox_patrol_dir = 1.0
	velocity = Vector2(_sandbox_patrol_dir * SPEED, 0.0)

# "Shooting": stands still and fires straight down at Laser Blaster-equivalent stats, via a
# dedicated enemy-bullet path (see GameManager.spawn_enemy_bullet) since the normal bullet
# system only ever damages the "enemies" group.
func _tick_sandbox_shooting(delta: float) -> void:
	_sandbox_shoot_timer -= delta
	if _sandbox_shoot_timer <= 0.0:
		_sandbox_shoot_timer = SANDBOX_SHOOT_INTERVAL
		GameManager.spawn_enemy_bullet(SANDBOX_BULLET_SCENE, global_position, PI / 2.0, SANDBOX_SHOOT_DAMAGE, is_blinded(), self)

# _attacker exists only so bullet.gd/player.gd's melee ATTACK state can call take_damage()
# uniformly whether or not the player has a Reflect Shield — enemies have no reflect mechanic
# of their own (yet), so it's accepted and ignored here.
func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO, knockback_force: float = 0.0, stun_duration: float = 0.0, stun_color: Color = Color(1.0, 1.0, 1.0), is_freeze: bool = false, _attacker: Node2D = null) -> void:
	# Once dead, ignore further hits — queue_free is deferred, so a second hit landing the same
	# frame (dual-barrel, wave, AOE grenade, or a bullet's ray-sweep + Area2D overlap) would
	# otherwise emit died() again and drop _enemies_alive twice, clearing the room early.
	if _dead:
		return
	# Run stats (real runs only): count the effective damage dealt to enemies this floor.
	if not sandbox_mode:
		GameManager.record_damage(mini(amount, maxi(health, 0)))
	health -= amount
	if knockback_force > 0.0:
		_knockback_vel = knockback_dir * knockback_force
	if stun_duration > 0.0:
		_stun_timer = stun_duration
		_stun_flash_timer = STUN_FLASH_INTERVAL
		_stun_flash_on = true
		_stun_flash_color = stun_color
		_freeze_pending_thaw = is_freeze
	queue_redraw()
	if health <= 0:
		_dead = true
		if not sandbox_mode:
			GameManager.record_kill()
		_drop_coins()
		died.emit()
		queue_free()

# Bursts _gold worth of coins outward from the death spot (each coin is worth Coin.VALUE, so a
# higher-gold enemy pops more of them). Added as siblings so they persist after this node frees.
func _drop_coins() -> void:
	if _gold <= 0:
		return
	var parent := get_parent()
	if parent == null:
		return
	# Make change for _gold in credit denominations (25/10/5/1 — coin.gd colours each), so the
	# dropped coins sum to EXACTLY the enemy-data gold. Capped at 24 coins for safety.
	var values: Array = []
	var remaining: int = _gold
	for d in [25, 10, 5, 1]:
		while remaining >= d and values.size() < 24:
			values.append(d)
			remaining -= d
	if remaining > 0 and not values.is_empty():
		values[values.size() - 1] += remaining # dump any capped remainder onto the last coin
	elif values.is_empty():
		values.append(_gold)
	var count: int = values.size()
	for i in count:
		var c: Node2D = COIN_SCENE.instantiate()
		parent.add_child(c)
		var a := TAU * float(i) / float(count) + randf_range(-0.4, 0.4)
		c.burst(global_position, Vector2.RIGHT.rotated(a), randf_range(70.0, 140.0), values[i])

func _draw() -> void:
	# Flame cone (drawn behind the body) while Solar is burning the player.
	if _flame_active:
		var pts := PackedVector2Array([Vector2.ZERO])
		const SEG := 10
		for i in range(SEG + 1):
			var a := _flame_angle - FLAME_ARC + (2.0 * FLAME_ARC) * (float(i) / float(SEG))
			pts.append(Vector2(FLAME_RANGE, 0.0).rotated(a))
		draw_colored_polygon(pts, Color(FLAME_COLOR, 0.35))

	var col := _body_color
	if _state == State.ATTACK:
		col = col.lerp(Color(1, 1, 1), 0.25) # brighten while attacking
	if _burn_flash_on:
		col = BURN_FLASH_COLOR
	if _confuse_flash_on:
		col = CONFUSE_FLASH_COLOR
	if _blind_flash_on:
		col = BLIND_FLASH_COLOR
	if _stun_flash_on:
		col = _stun_flash_color
	draw_circle(Vector2.ZERO, _radius, col)
	# Melee swing telegraph: the staff's cone hitbox (filled wedge + outline) in the strike
	# direction each attack, so what's shown matches the reach that actually connects.
	if _swing_flash_timer > 0.0:
		var half_arc := deg_to_rad(STAFF_ARC_DEGREES / 2.0)
		const SEG := 14
		var pts := PackedVector2Array([Vector2.ZERO])
		for i in range(SEG + 1):
			var a := _swing_angle - half_arc + (2.0 * half_arc) * (float(i) / float(SEG))
			pts.append(Vector2(_staff_range, 0.0).rotated(a))
		draw_colored_polygon(pts, Color(1.0, 0.85, 0.5, 0.28))
		for i in range(pts.size() - 1):
			draw_line(pts[i], pts[i + 1], Color(1.0, 0.9, 0.6, 0.8), 2.0)
	# Health bar. Bosses get a bigger red bar ABOVE the body (with "hp / max"); regular enemies a
	# small green one below with just the current HP.
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	if _special.begins_with("boss"):
		var bw := maxf(_radius * 2.0, 130.0)
		var bh := 9.0
		var by := -_radius - 24.0
		var x := -bw / 2.0
		draw_rect(Rect2(x, by, bw, bh), Color(0.08, 0.05, 0.05, 0.9))
		draw_rect(Rect2(x, by, bw * ratio, bh), Color(0.95, 0.20, 0.22))
		draw_rect(Rect2(x, by, bw, bh), Color(1, 1, 1, 0.75), false, 1.5)
		draw_string(ThemeDB.fallback_font, Vector2(x, by - 4.0),
			"%d / %d" % [maxi(health, 0), max_health], HORIZONTAL_ALIGNMENT_CENTER, bw, 12, Color(1, 0.9, 0.9))
	else:
		var bw := _radius * 2.0
		var by := _radius + 6.0
		draw_rect(Rect2(-_radius, by, bw, 5), Color(0.2, 0.2, 0.2))
		draw_rect(Rect2(-_radius, by, bw * ratio, 5), Color(0.2, 0.9, 0.2))
		draw_string(ThemeDB.fallback_font, Vector2(-_radius, by + 19.0), str(maxi(health, 0)),
			HORIZONTAL_ALIGNMENT_CENTER, bw, 10, Color(1, 1, 1))
