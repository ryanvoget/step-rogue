extends Node

signal health_changed(current: int, maximum: int)
signal floor_changed(floor_num: int)
signal room_cleared
signal player_died
signal deploy_equipment_requested(angle: float, throw_fraction: float) # angle/throw_fraction only meaningful for throwables (see mobile_controls.gd); throw_fraction is how far the throw joystick was dragged (0-1 of THROW_RADIUS), only actually used by scaleable_throw items
signal sniper_fire_requested(target_pos: Vector2) # emitted by mobile_controls.gd's fire-tap; target_pos is a raw touch position (viewport space == world space, no camera scroll)
signal thrown_melee_throw_requested(angle: float) # emitted by mobile_controls.gd when the aim joystick is released past the dead zone, for thrown-melee weapons (e.g. Throwable Beam Sword)
signal heal_item_requested # emitted by mobile_controls.gd's blue heal button tap
signal battery_activate_requested # emitted by mobile_controls.gd's battery button tap (READY state only)

var current_floor: int = 1

# Live room dimensions in canvas pixels, published by room.gd once it fits itself to the actual
# screen (see room.gd's _fit_to_viewport). room_w = full width; play_h = playable height (above
# the bottom control strip). Everything that needs the room bounds — enemy clamping/teleport,
# heal-dispenser vial spread, the Teleportation Bracelet's target clamp — reads these so it all
# scales to whatever device the game is running on. Defaults match the base landscape canvas.
var room_w: float = 854.0
var play_h: float = 380.0

# Set by mobile_controls when the right aim-joystick is pushed; zero when idle.
var mobile_aim_dir: Vector2 = Vector2.ZERO

# Set by player.gd whenever the equipped weapon changes; read by mobile_controls to swap
# the right-side control from an aim joystick to a plain attack button for melee weapons.
var melee_equipped: bool = false

# Set by world.gd at run start from SaveManager.equipped_equipment; read by mobile_controls
# to show/hide its deploy button (shown when either is true). equipment_deployed flips true
# once used (one-shot per run) — sandbox.gd may choose not to set it for repeat testing.
var equipment_placeable: bool = false
var equipment_throwable: bool = false
var equipment_deployed: bool = false

# Grenade throwables (world mode) get multiple uses instead of one-shot: equipment_is_grenade
# tells the HUD to show the top-left count, grenade_charges is how many throws remain. world.gd
# only flips equipment_deployed (which hides the throw joystick) once charges hit zero. See
# world.gd's _apply_loadout/_consume_grenade_charge.
var equipment_is_grenade: bool = false
var grenade_charges: int = 0
# Placeable turrets (Turret / Advanced Turret) also get multiple uses instead of one-shot — how
# many deploys remain this run. equipment_placeable (above) tells the HUD to show the counter.
var placeable_charges: int = 0

# Set alongside equipment_throwable for grapple-type equipment (e.g. Grapple Hook) — its
# release behavior specifically (dash to a wall / drag an enemy in), read by world.gd/
# sandbox.gd's _use_equipment to route to _use_grapple.
var equipment_grapple: bool = false

# Set by world.gd/sandbox.gd for any green-joystick equipment that wants the live
# dotted-line aim preview (Grapple Hook, Sticky Grenade, ...) — read by mobile_controls.gd to
# relay the live aim direction while dragging (not just the final angle on release, since the
# preview line needs to update continuously) and by player.gd to draw it. Distance is
# per-item since Grapple Hook is effectively uncapped but Sticky Grenade is bounded by its
# own throw_distance.
var equipment_aim_preview: bool = false
# True only while a finger is actually down on the equipment joystick — set/cleared by
# mobile_controls.gd's press/release handlers directly (not inferred from aim_preview_dir
# being non-zero), so an interrupted touch that never fires a clean release can't leave the
# preview line stuck showing. player.gd requires this AND a non-zero aim_preview_dir to draw.
var aim_preview_active: bool = false
var aim_preview_dir: Vector2 = Vector2.ZERO
var aim_preview_max_distance: float = 0.0

# "Scaleable throwing" (e.g. Distraction Grenade): marks throwable equipment whose actual
# throw distance scales with how far the throw joystick was dragged (0 to THROW_RADIUS),
# instead of always landing at the item's full throw_distance. aim_preview_fraction mirrors
# the live drag amount (0-1) while dragging, same lifecycle as aim_preview_dir, so the dotted
# preview line can shrink/grow with the drag and never "lie" about where it'll actually land —
# see player.gd's _draw_aim_preview and world.gd/sandbox.gd's _throw_grenade.
var equipment_scaleable_throw: bool = false
var aim_preview_fraction: float = 0.0

# Teleportation Bracelet (equipment): tells player.gd's _draw() to preview a floating dotted
# circle (get_teleport_target, free-floating — not stopped by walls/enemies) instead of the
# usual raycasted dotted line. See item_registry.gd's teleport field docs.
var equipment_teleport: bool = false

# Sniper Rifle Blaster charge/arm/fire state (see player.gd's set_sniper_stats/_fire_sniper
# and mobile_controls.gd's charge-bar drawing + touch handling). sniper_charge ticks up to
# sniper_charge_time in player.gd; once full, tapping the bar (mobile_controls) sets
# sniper_armed, which locks player movement and makes the next tap anywhere fire instead.
var sniper_equipped: bool = false
var sniper_charge: float = 0.0
var sniper_charge_time: float = 2.0
var sniper_armed: bool = false

# Set by player.gd's set_thrown_stats; read by mobile_controls to make the main aim joystick
# aim-and-release-to-throw (like the equipment throw joystick) instead of hold-to-fire.
var thrown_melee_equipped: bool = false

# Set by world.gd/sandbox.gd from whichever defensive item is equipped (heal_item field on
# its ItemRegistry row); read by mobile_controls to show/hide the blue heal button between
# the move and aim joysticks. heal_item_deployed flips true once used (one-shot per run in
# world.gd; sandbox.gd may not, to allow repeat testing, same as equipment_deployed).
var heal_item_equipped: bool = false
var heal_item_deployed: bool = false

# Shield Barrier (Light/Medium/Heavy, a heal_item) — see item_registry.gd's shield field docs
# and player.gd's configure_shield/toggle_shield, which owns this state. Repeatable on/off
# toggle, not a one-shot: unlike every other heal_item, mobile_controls.gd's _heal_active keys
# the button/bar's visibility off shield_broken instead of heal_item_deployed, so they stay up
# for as long as the shield hasn't broken rather than disappearing after the first tap.
var shield_equipped: bool = false
var shield_active: bool = false
var shield_broken: bool = false
var shield_hp: float = 0.0
var shield_hp_max: float = 0.0
var shield_color: Color = Color(0.4, 0.8, 1.0) # tint of the active-shield player outline + HUD bar

# Speed Boost Battery (equipment) activate/deplete/recharge cycle — see item_registry.gd's
# battery field docs and player.gd's configure_battery/activate_battery/_tick_battery, which
# owns this state and keeps it in sync every physics frame. Plain int state (not a shared enum
# type) mirroring enemy_basic.gd's SandboxAction/sandbox.gd's _enemy_action convention, since
# mobile_controls.gd only needs to compare/branch on it, not resolve its type.
const BATTERY_READY := 0
const BATTERY_ACTIVE := 1
const BATTERY_RECHARGING := 2 # kept for compatibility; no longer used (batteries don't recharge)
var equipment_battery: bool = false
var battery_state: int = BATTERY_READY
var battery_charge: float = 1.0 # 1.0 = ready/full; drains toward 0.0 during ACTIVE
# Batteries now have a fixed number of activations per run instead of recharging — how many are
# left. equipment_battery tells the HUD to show the counter (see hud.gd).
var battery_charges: int = 0

# Detonator Mine (equipment) two-tap place/detonate cycle — see item_registry.gd's mine field
# docs. Same plain-int-state convention as battery_state above.
const MINE_READY := 0
const MINE_ARMED := 1
var equipment_mine: bool = false
var mine_state: int = MINE_READY
# Detonator Mines get multiple uses per run (decremented on each detonation) — how many remain.
var mine_charges: int = 0

# Force Push Bracelet (equipment) hold-to-channel joystick state — see item_registry.gd's
# force_push field docs. force_push_held/force_push_dir are set directly by mobile_controls.gd's
# press/drag/release handlers (like aim_preview_active, not inferred from anything else) —
# held is true only while dragged past the dead zone, dir is that drag's normalized direction
# (Vector2.ZERO otherwise). Polled every physics frame by player.gd's _tick_force_push, which
# owns force_push_mana and keeps it in sync for the UI.
var equipment_force_push: bool = false
var force_push_held: bool = false
var force_push_dir: Vector2 = Vector2.ZERO
var force_push_mana: float = 100.0
var force_push_mana_max: float = 100.0

# Deployable Barrier Wall (equipment) two-tap trail-placement cycle — see item_registry.gd's
# barrier field docs. Same plain-int-state convention as battery_state/mine_state above.
const BARRIER_READY := 0
const BARRIER_PLACING := 1
var equipment_barrier: bool = false
var barrier_state: int = BARRIER_READY

# Hoverboard (equipment) mounted/unmounted toggle — see item_registry.gd's hoverboard field
# docs and player.gd's configure_hoverboard/toggle_hoverboard, which owns this state. Plain
# bool, not a two-state int like mine/barrier/battery above, since there's no third state.
var equipment_hoverboard: bool = false
var hoverboard_active: bool = false
# The hoverboard lasts a budget of HOVERBOARD_MAX_ROOMS rooms of active use (including the room
# it's activated in). Decremented on each room transition while mounted (see world.gd's
# _go_through_door); at zero it auto-dismounts and can't be remounted. Shown in the HUD top-right.
const HOVERBOARD_MAX_ROOMS: int = 5
var hoverboard_rooms_remaining: int = HOVERBOARD_MAX_ROOMS

# Temporary Invincible Battery (equipment) tap-toggle drain — see item_registry.gd's
# invincible field docs and player.gd's configure_invincible/toggle_invincible/
# _tick_invincible, which owns this state. Same non-regenerating-mana pattern as Force Push
# Bracelet, but a plain on/off tap button instead of a hold joystick.
var equipment_invincible: bool = false
var invincible_active: bool = false
var invincible_mana: float = 100.0
var invincible_mana_max: float = 100.0

# Dennis (equipment) summon button — see item_registry.gd's summon field docs. One-shot per
# run in world.gd (like Turret's equipment_deployed), so it uses the same one-shot group as
# placeable/throwable/mine/barrier in mobile_controls.gd's _deploy_active, just drawn as a
# gold button with summon_label's text instead of a plain colored circle.
var equipment_summon: bool = false
var summon_label: String = "SUMMON"

# True while a full-screen game popup (e.g. world.gd's every-5-rooms reward choice) is open —
# mobile_controls.gd ignores new touches/drags while set, so tapping a popup button can't also
# fire a joystick or the heal button underneath it.
var ui_popup_open: bool = false

var step_bank: int:
	get: return SaveManager.step_bank
	set(v): SaveManager.step_bank = v

# Coins are run-scoped (NOT persisted): dropped by defeated enemies (see coin.gd), spent at
# shops that appear every 10 floors (see world.gd's _show_shop). Reset to 0 at run start in
# world.gd's _ready and on reset() below.
var coins: int = 0

func add_coins(n: int) -> void:
	coins += n

# ── Run statistics (shown on the game-over → Statistics screen; reset each run in world._ready) ──
var stat_damage_by_floor: Dictionary = {} # floor number -> damage dealt to enemies that floor
var stat_total_damage: int = 0
var stat_enemies_slain: int = 0
var stat_floors_cleared: int = 0
var stat_shots_fired: int = 0   # player-fired bullets (lasers); see bullet.from_player
var stat_shots_hit: int = 0     # of those, how many connected with an enemy
var stat_melee_attempts: int = 0 # melee swings + thrown-melee throws
var stat_melee_hits: int = 0     # of those, how many connected

func reset_run_stats() -> void:
	stat_damage_by_floor = {}
	stat_total_damage = 0
	stat_enemies_slain = 0
	stat_floors_cleared = 0
	stat_shots_fired = 0
	stat_shots_hit = 0
	stat_melee_attempts = 0
	stat_melee_hits = 0

func record_damage(amount: int) -> void:
	if amount <= 0:
		return
	stat_total_damage += amount
	stat_damage_by_floor[current_floor] = int(stat_damage_by_floor.get(current_floor, 0)) + amount

func record_kill() -> void:
	stat_enemies_slain += 1

func record_floor_cleared() -> void:
	stat_floors_cleared += 1

func record_shot_fired() -> void:
	stat_shots_fired += 1

func record_shot_hit() -> void:
	stat_shots_hit += 1

func record_melee_attempt() -> void:
	stat_melee_attempts += 1

func record_melee_hit() -> void:
	stat_melee_hits += 1

var _bullets_container: Node = null

func register_bullets_container(node: Node) -> void:
	_bullets_container = node

func spawn_bullet(scene: PackedScene, pos: Vector2, angle: float, damage: int = -1, speed: float = -1.0, freeze_duration: float = -1.0, knockback_force: float = -1.0, wave_max_width: float = -1.0, from_player: bool = false) -> void:
	if _bullets_container == null:
		return
	var b = scene.instantiate()
	b.global_position = pos
	b.rotation = angle
	if damage >= 0:
		b.damage = damage
	if speed >= 0.0:
		b.speed = speed
	if freeze_duration >= 0.0:
		b.freeze_duration = freeze_duration
	if knockback_force >= 0.0:
		b.knockback_force = knockback_force
	if wave_max_width >= 0.0:
		b.wave_max_width = wave_max_width
	# Only bullets the player fired count toward shot accuracy (not turret/sidekick/Dennis shots).
	b.from_player = from_player
	if from_player:
		record_shot_fired()
	_bullets_container.add_child(b)
	AudioManager.play_laser()

# Mirrors spawn_bullet but for enemy-fired projectiles (currently sandbox-only — see
# enemy_basic.gd's SHOOTING sandbox action): targets the player's group and collision layer
# (1) instead of the enemies' group/layer (2) spawn_bullet's bullets normally target.
# will_miss (Flash Grenade, see enemy_basic.gd's apply_blind/is_blinded) fires the bullet with
# no collision mask at all, so it still visually travels but can never register a hit on the
# player — "goes around" them — decided once at spawn time, not re-checked mid-flight.
# shooter is passed straight to the bullet so a Reflect Shield knows who to hit back — see
# bullet.gd's shooter field.
func spawn_enemy_bullet(scene: PackedScene, pos: Vector2, angle: float, damage: int, will_miss: bool = false, shooter: Node2D = null, freeze_duration: float = 0.0, wave_max_width: float = 0.0) -> void:
	if _bullets_container == null:
		return
	var b = scene.instantiate()
	b.global_position = pos
	b.rotation = angle
	b.damage = damage
	b.target_group = "player"
	b.collision_mask = 0 if will_miss else 1
	b.shooter = shooter
	# Cryo Unit fires freeze bolts (blue, slows the player); Nebula Unit fires expanding waves.
	if freeze_duration > 0.0:
		b.freeze_duration = freeze_duration
	if wave_max_width > 0.0:
		b.wave_max_width = wave_max_width
	_bullets_container.add_child(b)
	AudioManager.play_laser()

# Reuses the same shared bullets container as spawn_bullet — player.gd has no direct
# reference to the world/sandbox root to add a world-space child to otherwise. Must add to
# the tree before configure()/launch() since the thrown weapon's wall raycast needs a valid
# World2D.
func spawn_thrown_weapon(scene: PackedScene, tex: Texture2D, origin: Vector2, direction: Vector2,
		player: Node2D, damage: int, radius: float, speed: float) -> Node:
	if _bullets_container == null:
		return null
	var w = scene.instantiate()
	_bullets_container.add_child(w)
	w.configure(tex, damage, radius, speed)
	w.launch(origin, direction, player)
	return w

# Reuses the same shared bullets container as spawn_bullet — player.gd has no direct
# reference to the world/sandbox root otherwise. For a launched-weapon grenade (e.g. Void
# Grenade Launcher), unlike the equipment Blast Grenade which world.gd/sandbox.gd spawn
# directly: same grenade.tscn/configure(), just fired from player.gd's normal attack path
# instead of the equipment deploy/throw flow.
func spawn_launched_grenade(scene: PackedScene, tex: Texture2D, origin: Vector2, landing_pos: Vector2,
		damage: int, radius: float, explode_delay: float,
		gravity_duration: float = 0.0, gravity_tick_interval: float = 0.5) -> void:
	if _bullets_container == null:
		return
	var g = scene.instantiate()
	g._explode_on_impact = true # launched grenades detonate on hitting an enemy (don't pass through)
	_bullets_container.add_child(g)
	g.configure(tex, origin, landing_pos, damage, radius, explode_delay, gravity_duration, gravity_tick_interval)

func next_floor() -> void:
	current_floor += 1
	floor_changed.emit(current_floor)

func reset() -> void:
	current_floor = 1
	coins = 0 # run-scoped — reset when a run ends
	SceneManager.go_to_menu()
