extends Node2D

const PLAYER_SCENE     := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE      := preload("res://scenes/enemies/enemy_basic.tscn")
const ENEMY_SCRIPT     := preload("res://scenes/enemies/enemy_basic.gd")
const BULLET_SCENE     := preload("res://scenes/bullets/bullet.tscn")
const TURRET_SCENE     := preload("res://scenes/turret/turret.tscn")
const GRENADE_SCENE    := preload("res://scenes/grenade/grenade.tscn")
const BARRIER_SCENE    := preload("res://scenes/barrier_wall/barrier_wall.tscn")
const SIDEKICK_SCENE   := preload("res://scenes/sidekick_robot/sidekick_robot.tscn")
const DENNIS_SCENE     := preload("res://scenes/dennis/dennis.tscn")
const HEAL_DISPENSER_SCENE := preload("res://scenes/heal_dispenser/heal_dispenser.tscn")
const SHOP_NPC_SCENE   := preload("res://scenes/shop_npc/shop_npc.tscn")

# Grid directions per door side — indices match room.gd's SIDE_TOP/BOTTOM/LEFT/RIGHT (0/1/2/3).
const SIDE_OFFSETS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

# Hallway art variants and the door sides baked into each PNG (0=top,1=bottom,2=left,3=right). When
# a room is created we pick a variant whose doors INCLUDE the entry side, so the art always lines up
# with where the player came from; that variant's other doors become the room's exits.
const HALLWAY_VARIANTS := [
	{"tex": "res://assets/Sprites/Floor Types/Hallway v2.png", "doors": [0, 2, 3]},    # top, left, right
	{"tex": "res://assets/Sprites/Floor Types/Hallway v3.png", "doors": [0, 1, 2, 3]}, # all four
	{"tex": "res://assets/Sprites/Floor Types/Hallway v4.png", "doors": [0, 1, 3]},    # top, bottom, right
	{"tex": "res://assets/Sprites/Floor Types/Hallway v5.png", "doors": [0, 2, 3]},    # top, left, right
	{"tex": "res://assets/Sprites/Floor Types/Hallway v6.png", "doors": [0, 1, 2]},    # top, bottom, left
]
const GRENADE_CHARGES := 5 # throwable grenades get this many uses per run instead of one-shot
const TURRET_CHARGES := 5   # placeable turrets get this many deploys per run instead of one-shot
const MINE_CHARGES := 5     # detonator mines get this many uses per run instead of one-shot
const SHOP_EVERY_N_FLOORS := 10 # every 10th room is a shop room (no enemies, a shop-keeper NPC)
const SHOP_TALK_RANGE := 66.0 # walk within this of the NPC to open the shop dialog
const SHOP_HEAL_COST := 100
const SHOP_CRATE_COST := 100
const SHOP_UPGRADE_COST := 250
const WEAPON_UPGRADE_MAX := 2 # 1st upgrade = 1.5x damage, 2nd = 1.5x fire rate

@onready var _room:    Node2D = $Room
@onready var _enemies: Node   = $Enemies
@onready var _bullets: Node   = $Bullets
@onready var _hud = $HUD

var _player: CharacterBody2D = null
var _enemies_alive  := 0
var _clearing       := false
var _placed_mine: Node2D = null
var _active_barrier: Node2D = null
var _active_sidekick: Node2D = null
var _shop_npc: Node2D = null      # the shop-keeper in the current room (shop rooms only)
var _shop_npc_active := false     # true while the player is standing in talk range — debounces
                                  # so the dialog only opens on approach, not every frame, and
                                  # can be reopened by stepping away and back after Leaving
var _props: Node2D = null # room-scoped spawned objects (turrets, mines, thrown grenades,
                           # barriers, dispensers) — freed on every room transition, since all
                           # rooms share the same physical screen space. Companions (Sidekick,
                           # Dennis) are world children instead, so they persist across rooms.

# Room graph: every room lives at a grid coordinate; walking through a door on side S moves
# you to the adjacent cell. Each room's state records whether it's been cleared, which sides
# its exit doors are on (rolled when first cleared), the side leading back where you came from,
# and its difficulty number (the count of distinct rooms discovered when it was first entered —
# revisiting an old room never spawns anything new, per design).
var _rooms := {}                  # Vector2i -> {"cleared", "doors", "entry_side", "number"}
var _current_pos := Vector2i.ZERO
var _current_entry_side := -1     # the door THIS visit came in through (drawn blue once
                                   # unlocked, and always the way back) — per-visit, unlike the
                                   # room state's entry_side which records the first visit
var _rooms_entered := 1           # distinct rooms discovered so far = current difficulty
var _rooms_cleared := 0           # total rooms cleared (informational)
var _reward_popup: Control = null
# Weapon upgrades bought at shops, keyed by weapon name -> level (0..WEAPON_UPGRADE_MAX).
# Level 1 = 1.5x damage, level 2 also = 1.5x fire rate. Applied in _reequip_weapon.
var _weapon_upgrades := {}
var _return_to_shop := false      # true while a crate spin was launched from the shop, so the
                                  # equip/keep result returns to the shop instead of closing
# Crate-spin tick state: while _crate_track is set, _process plays a tick each time a new card
# scrolls under the center marker (naturally slowing as the spin decelerates).
var _crate_track: Control = null
var _crate_stage: Control = null
var _crate_last_tick := -1

func _ready() -> void:
	GameManager.register_bullets_container(_bullets)
	GameManager.coins = 0 # run-scoped currency — start every run at zero
	GameManager.reset_run_stats() # fresh statistics for the new run (shown on the game-over screen)
	_weapon_upgrades.clear()
	GameManager.ui_popup_open = false # persistent autoload — never inherit a stale popup lock
	GameManager.deploy_equipment_requested.connect(_use_equipment)
	GameManager.heal_item_requested.connect(_use_heal_item)
	GameManager.battery_activate_requested.connect(_use_battery)
	_props = Node2D.new()
	add_child(_props)
	_spawn_player()
	_apply_loadout()
	_grant_room_invincibility() # Invincible+ artifact — the start room counts as the first room
	# Exit doors are rolled at room creation (not on clear) so they're visible — red and
	# locked — for the whole fight, then unlock in place once the room is cleared.
	_rooms[Vector2i.ZERO] = _make_room(-1, false, 1)
	_refresh_doors()
	GameManager.current_floor = 1
	GameManager.floor_changed.emit(1)
	_hud.game_started.connect(_spawn_enemies_for_room)
	if OS.has_feature("ios") or OS.has_feature("android") or OS.has_feature("editor"):
		add_child(preload("res://scenes/ui/mobile_controls.tscn").instantiate())

func _spawn_player() -> void:
	var p: CharacterBody2D = PLAYER_SCENE.instantiate()
	p.bullet_scene = BULLET_SCENE
	add_child(p)
	p.global_position = _room.player_spawn_pos
	_player = p
	_setup_camera()

# Fixed camera centered on the (screen-sized) 1040x480 room at 1x zoom (the map/player sprites bake
# in the 2x, so the world scale matches the pre-map game). No scrolling. HUD/joysticks are on
# CanvasLayers, unaffected.
func _setup_camera() -> void:
	var cam := Camera2D.new()
	cam.position = Vector2(GameManager.room_w * 0.5, GameManager.room_h * 0.5)
	add_child(cam)
	cam.make_current()

# Re-pulls each equipped item's stats from the current ItemRegistry by name. Equipped items are
# stored as a frozen snapshot from equip time, so balance changes (damage, rarity, etc.) wouldn't
# otherwise reach an item that's already equipped — this keeps a live run in sync with the registry.
func _refresh_equipped_from_registry() -> void:
	for key in ["equipped_weapon", "equipped_equipment", "equipped_defensive"]:
		var nm: String = SaveManager.get_slot(key).get("name", "")
		if nm != "":
			var fresh: Dictionary = ItemRegistry.get_item_by_name(nm)
			if not fresh.is_empty():
				SaveManager.set_slot(key, fresh.duplicate(true))
	var an: String = SaveManager.equipped_artifact.get("name", "")
	if an != "":
		var fa: Dictionary = ItemRegistry.get_artifact_by_name(an)
		if not fa.is_empty():
			SaveManager.set_slot("equipped_artifact", fa.duplicate(true))

# Applies the full equipped loadout (weapon + equipment + defensive) to GameManager state and
# the live player. Runs at spawn AND again after the every-5-rooms crate reward swaps an item
# mid-run — so everything here must be safe to re-run, resetting the not-equipped branches too
# (same defensive pattern sandbox.gd uses on dropdown switches) so a swapped-away item's state
# can't linger.
func _apply_loadout() -> void:
	_refresh_equipped_from_registry()
	GameManager.equipment_placeable = SaveManager.equipped_equipment.get("placeable", false)
	GameManager.placeable_charges = TURRET_CHARGES if GameManager.equipment_placeable else 0
	GameManager.equipment_throwable = SaveManager.equipped_equipment.get("throwable", false)
	GameManager.equipment_grapple   = SaveManager.equipped_equipment.get("grapple", false)
	GameManager.equipment_aim_preview = SaveManager.equipped_equipment.get("aim_preview", false)
	GameManager.aim_preview_max_distance = SaveManager.equipped_equipment.get("throw_distance", 1200.0)
	GameManager.aim_preview_active = false # GameManager is a persistent autoload — don't inherit a stale "touching" state from a previous scene/item
	GameManager.aim_preview_fraction = 0.0
	GameManager.equipment_scaleable_throw = SaveManager.equipped_equipment.get("scaleable_throw", false)
	GameManager.equipment_deployed  = false
	GameManager.heal_item_equipped = SaveManager.equipped_defensive.get("heal_item", false)
	GameManager.heal_item_deployed = false
	GameManager.shield_equipped = SaveManager.equipped_defensive.get("shield", false)
	GameManager.equipment_battery = SaveManager.equipped_equipment.get("battery", false)
	GameManager.equipment_mine = SaveManager.equipped_equipment.get("mine", false)
	GameManager.mine_state = GameManager.MINE_READY
	GameManager.mine_charges = MINE_CHARGES if GameManager.equipment_mine else 0
	GameManager.equipment_force_push = SaveManager.equipped_equipment.get("force_push", false)
	GameManager.force_push_held = false
	GameManager.force_push_dir = Vector2.ZERO
	GameManager.equipment_barrier = SaveManager.equipped_equipment.get("barrier", false)
	GameManager.barrier_state = GameManager.BARRIER_READY
	GameManager.equipment_hoverboard = SaveManager.equipped_equipment.get("hoverboard", false)
	GameManager.hoverboard_rooms_remaining = GameManager.HOVERBOARD_MAX_ROOMS # fresh budget on equip
	GameManager.equipment_teleport = SaveManager.equipped_equipment.get("teleport", false)
	GameManager.equipment_invincible = SaveManager.equipped_equipment.get("invincible", false)
	GameManager.equipment_summon = SaveManager.equipped_equipment.get("summon", false)
	GameManager.summon_label = SaveManager.equipped_equipment.get("summon_label", "SUMMON")
	# Grenade throwables get GRENADE_CHARGES uses instead of one-shot (see _consume_grenade_charge).
	GameManager.equipment_is_grenade = _is_grenade(SaveManager.equipped_equipment)
	GameManager.grenade_charges = GRENADE_CHARGES if GameManager.equipment_is_grenade else 0

	_reequip_weapon()

	var equip: Dictionary = SaveManager.equipped_equipment
	if GameManager.equipment_battery:
		_player.configure_battery(equip.get("speed_boost_multiplier", 1.5),
			equip.get("battery_active_duration", 10.0), equip.get("battery_recharge_duration", 10.0))
	else:
		_player.configure_battery(1.5, 10.0, 10.0)
	if GameManager.equipment_force_push:
		_player.configure_force_push(equip.get("force_push_range", 192.0), equip.get("force_push_arc_degrees", 100.0),
			equip.get("force_push_mana_max", 100.0), equip.get("force_push_mana_drain_rate", 10.0))
	else:
		_player.configure_force_push(192.0, 100.0, 100.0, 10.0)
	if GameManager.equipment_hoverboard:
		var tex: Texture2D = load("res://assets/icons/" + equip["file"])
		_player.configure_hoverboard(tex, equip.get("hoverboard_speed_multiplier", 1.5))
	else:
		_player.configure_hoverboard(null, 1.5)
	if GameManager.equipment_invincible:
		_player.configure_invincible(equip.get("invincible_mana_max", 100.0), equip.get("invincible_mana_drain_rate", 10.0))
	else:
		_player.configure_invincible(100.0, 10.0)
	if GameManager.shield_equipped:
		var scol := _shield_color_for(SaveManager.equipped_defensive)
		GameManager.shield_color = scol
		# Artifact Defense+ gives shields more HP (their block value doubles as the absorb pool).
		var block: float = float(SaveManager.equipped_defensive.get("block", 10.0)) * ItemRegistry.artifact_num("shield_mult", 1.0)
		_player.configure_shield(block,
			SaveManager.equipped_defensive.get("shield_reflect", false), scol)
	else:
		_player.configure_shield(10.0, false)
	# Artifact Health+ adds bonus max HP (idempotent — safe to re-run when the loadout re-applies).
	_player.apply_bonus_max_health(int(ItemRegistry.artifact_num("bonus_hp", 0.0)))
	if SaveManager.equipped_equipment.get("sidekick", false):
		if _active_sidekick == null or not is_instance_valid(_active_sidekick):
			_spawn_sidekick(SaveManager.equipped_equipment)
	elif _active_sidekick != null and is_instance_valid(_active_sidekick):
		_active_sidekick.queue_free()
		_active_sidekick = null

# Colour for a shield type's player outline + HUD bar: Reflect = gold, and the Light/Medium/Heavy
# barriers step cyan → blue → violet by their block value.
func _shield_color_for(item: Dictionary) -> Color:
	if item.get("shield_reflect", false):
		return Color(1.0, 0.72, 0.2)
	var block: float = float(item.get("block", 10))
	if block <= 10.0:
		return Color(0.40, 0.85, 1.0)
	elif block <= 25.0:
		return Color(0.35, 0.50, 1.0)
	return Color(0.62, 0.42, 1.0)

# Equips the current weapon, applying any shop upgrades bought for it. Level 1 multiplies
# damage by 1.5, level 2 also divides fire_rate by 1.5 (faster). Works on a duplicated dict so
# the persisted SaveManager item is never mutated — upgrades are tracked separately in
# _weapon_upgrades and re-derived fresh each equip. Safe to re-run (called from _apply_loadout
# and after a shop upgrade purchase).
func _reequip_weapon() -> void:
	if SaveManager.equipped_weapon.is_empty():
		return
	var w: Dictionary = SaveManager.equipped_weapon.duplicate(true)
	var level: int = _weapon_upgrades.get(w.get("name", ""), 0)
	if level >= 1 and w.get("damage") != null:
		w["damage"] = int(round(float(w["damage"]) * 1.5))
	if level >= 2 and w.get("fire_rate") != null:
		w["fire_rate"] = float(w["fire_rate"]) / 1.5
	# Artifacts: Damage+ scales base weapon damage, Rate of Fire+ speeds up its fire rate.
	if w.get("damage") != null:
		w["damage"] = int(round(float(w["damage"]) * ItemRegistry.artifact_num("dmg_mult", 1.0)))
	if w.get("fire_rate") != null:
		w["fire_rate"] = float(w["fire_rate"]) / ItemRegistry.artifact_num("fire_rate_mult", 1.0)
	# Knockback+ artifact adds knockback to melee weapons only.
	if w.get("melee_range") != null:
		var add_kb := ItemRegistry.artifact_num("melee_knockback_add", 0.0)
		if add_kb > 0.0:
			var base_kb: float = float(w["knockback"]) if w.get("knockback") != null else 0.0
			w["knockback"] = base_kb + add_kb
	ItemRegistry.equip_on_player(_player, w)

# Uses the equipped equipment (Turret/Advanced Turret = deploy in place; Blast Grenade =
# throw in the direction the throw joystick was released, from mobile_controls). One-time
# per run — mobile_controls hides its button after this fires once — EXCEPT grenades, which get
# GRENADE_CHARGES uses (see _consume_grenade_charge).
func _use_equipment(angle: float, throw_fraction: float = 1.0) -> void:
	if GameManager.equipment_deployed:
		return
	var item: Dictionary = SaveManager.equipped_equipment
	if item.is_empty():
		return
	if item.get("placeable", false):
		_deploy_turret(item)
		_consume_placeable_charge()
	elif item.get("grapple", false):
		# Grapple Hook is reusable — never marks itself deployed, so it doesn't break and carries
		# across floors (same as the Teleportation Bracelet).
		_use_grapple(angle, throw_fraction)
	elif item.get("sticky", false):
		_use_sticky_grenade(item, angle, throw_fraction)
		_consume_grenade_charge()
	elif item.get("teleport", false):
		# Teleportation Bracelet is reusable — it never sets equipment_deployed, so it stays
		# available and carries into the next rooms (doesn't "break" after one use).
		_use_teleport(item, angle, throw_fraction)
	elif item.get("throwable", false):
		_throw_grenade(item, angle, throw_fraction)
		_consume_grenade_charge()
	elif item.get("mine", false):
		_use_mine(item)
	elif item.get("barrier", false):
		_use_barrier(item)
	elif item.get("hoverboard", false):
		# Can't (re)mount once the 5-room budget is spent; dismounting is always allowed.
		if GameManager.hoverboard_active or GameManager.hoverboard_rooms_remaining > 0:
			_player.toggle_hoverboard()
	elif item.get("invincible", false):
		_player.toggle_invincible()
	elif item.get("summon", false):
		GameManager.equipment_deployed = true
		_spawn_dennis(item)

# A grenade is any throwable equipment whose name ends in "Grenade" (Blast/Smoke/Molotov/
# Magnetic/Distraction/Ice/Flash/Mesh/Sticky) — same rule ItemRegistry.random_grenade uses.
# Grapple Hook and Teleportation Bracelet are throwable but not grenades, so they stay one-shot.
func _is_grenade(item: Dictionary) -> bool:
	return item.get("throwable", false) and String(item.get("name", "")).ends_with("Grenade")

# Decrements the shared grenade counter; once it hits zero, flip equipment_deployed so
# mobile_controls hides the throw joystick — the same gate every one-shot item uses.
func _consume_grenade_charge() -> void:
	GameManager.grenade_charges = max(0, GameManager.grenade_charges - 1)
	if GameManager.grenade_charges <= 0:
		GameManager.equipment_deployed = true

# Placeable turrets get TURRET_CHARGES deploys per run; only once they're spent does the deploy
# button go away (same one-shot gate every other equipment uses at zero).
func _consume_placeable_charge() -> void:
	GameManager.placeable_charges = max(0, GameManager.placeable_charges - 1)
	if GameManager.placeable_charges <= 0:
		GameManager.equipment_deployed = true

# Re-raycasts (via player.gd's get_aim_target, the same one the live preview line uses) using
# the final released angle, then either dashes the player to a wall or drags an enemy in
# close — see item_registry.gd's grapple field docs. Scaleable throwing (Grapple Hook has no
# throw_distance of its own, so this scales GRAPPLE_MAX_DISTANCE instead — same cap the live
# preview already uses via aim_preview_max_distance's throw_distance fallback of 1200.0).
func _use_grapple(angle: float, throw_fraction: float = 1.0) -> void:
	var direction := Vector2.RIGHT.rotated(angle)
	var max_distance: float = _player.GRAPPLE_MAX_DISTANCE
	if GameManager.equipment_scaleable_throw:
		max_distance *= clampf(throw_fraction, 0.0, 1.0)
	var target: Dictionary = _player.get_aim_target(direction, max_distance)
	if target["is_enemy"]:
		var drag_to: Vector2 = _player.global_position + direction * 20.0
		target["collider"].grapple_pull_to(drag_to, 0.2)
	else:
		var dash_to: Vector2 = target["position"] - direction * _player.GRAPPLE_WALL_CLEARANCE
		_player.start_grapple_dash(dash_to)

# Free-floating target (get_teleport_target, not a raycast — see item_registry.gd's teleport
# field docs), scaled by throw_fraction the same way as any other scaleable_throw item, then
# the player is moved there directly.
func _use_teleport(item: Dictionary, angle: float, throw_fraction: float = 1.0) -> void:
	var direction := Vector2.RIGHT.rotated(angle)
	var max_distance: float = item.get("throw_distance", 1200.0)
	if item.get("scaleable_throw", false):
		# Squared, not linear — matches player.gd's TELEPORT_SENSITIVITY_CURVE in
		# _draw_teleport_preview, so release always lands exactly where the dotted circle showed.
		max_distance *= pow(clampf(throw_fraction, 0.0, 1.0), 2.0)
	var target: Vector2 = _player.get_teleport_target(direction, max_distance)
	_player.teleport_to(target)

# Same live-preview raycast, capped at the item's own throw_distance (scaled by throw_fraction
# for scaleable_throw items) — sticks to a directly hit enemy, otherwise explodes as a normal
# (smaller) AOE burst wherever it lands.
func _use_sticky_grenade(item: Dictionary, angle: float, throw_fraction: float = 1.0) -> void:
	var direction := Vector2.RIGHT.rotated(angle)
	var max_distance: float = item["throw_distance"]
	if item.get("scaleable_throw", false):
		max_distance *= clampf(throw_fraction, 0.0, 1.0)
	var target: Dictionary = _player.get_aim_target(direction, max_distance)
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	var origin: Vector2 = _player.global_position
	var grenade: Node2D = GRENADE_SCENE.instantiate()
	_props.add_child(grenade)
	if target["is_enemy"]:
		grenade.configure_stick(tex, origin, target["collider"], item["sticky_damage"], item["sticky_delay"])
	else:
		grenade.configure(tex, origin, target["position"], item["damage"], item["aoe_radius"], item["explode_delay"])

func _deploy_turret(item: Dictionary) -> void:
	var turret: Node2D = TURRET_SCENE.instantiate()
	_props.add_child(turret)
	turret.global_position = _player.global_position
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	turret.configure(tex, item["damage"], item["fire_rate"], item["bullet_speed"])

# Sidekick Robot: no green button, active for the whole run — spawned directly from _ready()
# once, right after the player, instead of through the deploy_equipment_requested flow every
# other piece of equipment uses. See item_registry.gd's sidekick field docs.
func _spawn_sidekick(item: Dictionary) -> void:
	_active_sidekick = SIDEKICK_SCENE.instantiate()
	add_child(_active_sidekick)
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	_active_sidekick.configure(tex, item["damage"], item["fire_rate"], item["bullet_speed"], _player)

# Dennis: reads Assault Rifle Blaster's own damage/fire_rate/bullet_speed live (rather than
# storing a copy on Dennis's own row) so the two can never drift out of sync — see
# item_registry.gd's summon field docs and ItemRegistry.get_item_by_name.
func _spawn_dennis(item: Dictionary) -> void:
	var stats: Dictionary = ItemRegistry.get_item_by_name("Assault Rifle Blaster")
	var dmg: int = stats["damage"] if stats.get("damage") != null else 1
	var rate: float = stats["fire_rate"] if stats.get("fire_rate") != null else 0.0625
	var bspeed: float = stats["bullet_speed"] if stats.get("bullet_speed") != null else 520.0
	var dennis: Node2D = DENNIS_SCENE.instantiate()
	add_child(dennis)
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	dennis.configure(tex, dmg, rate, bspeed, _player.global_position)

func _throw_grenade(item: Dictionary, angle: float, throw_fraction: float = 1.0) -> void:
	var grenade: Node2D = GRENADE_SCENE.instantiate()
	_props.add_child(grenade)
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	var origin: Vector2 = _player.global_position
	# "Scaleable throwing" (e.g. Distraction Grenade): actual distance scales with how far the
	# throw joystick was dragged, capped at the item's full throw_distance — see
	# item_registry.gd's scaleable_throw field docs.
	var max_distance: float = item["throw_distance"]
	var distance: float = max_distance * clampf(throw_fraction, 0.0, 1.0) if item.get("scaleable_throw", false) else max_distance
	var landing: Vector2 = origin + Vector2.RIGHT.rotated(angle) * distance
	var dmg: int = item["damage"] if item.get("damage") != null else 0
	var g_duration: float = item.get("gravity_duration", 0.0)
	var g_interval: float = item.get("gravity_tick_interval", 0.5)
	var g_pull_speed: float = item.get("gravity_pull_speed", 90.0)
	var confuse_duration: float = item.get("confuse_duration", 0.0)
	var linger_duration: float = item.get("linger_duration", 0.0)
	var linger_burn_damage: int = item.get("linger_burn_damage", 0)
	var linger_burn_duration: float = item.get("linger_burn_duration", 0.0)
	var distract_duration: float = item.get("distract_duration", 0.0)
	var freeze_duration: float = item.get("freeze_duration", 0.0)
	var flash_duration: float = item.get("flash_duration", 0.0)
	var mesh_count: int = item.get("mesh_count", 0)
	var mesh_radius_ratio: float = item.get("mesh_radius_ratio", 0.25)
	var mesh_damage: int = item.get("mesh_damage", 0)
	grenade.configure(tex, origin, landing, dmg, item["aoe_radius"], item["explode_delay"],
		g_duration, g_interval, g_pull_speed, confuse_duration,
		linger_duration, linger_burn_damage, linger_burn_duration, distract_duration, freeze_duration, flash_duration,
		mesh_count, mesh_radius_ratio, mesh_damage)

# Detonator Mine's two-tap cycle (see item_registry.gd's mine field docs): first tap (READY)
# drops it at the player's current position and arms it; second tap (ARMED) detonates it in
# place — wherever that ended up being, even if the player has since moved away. Sets
# equipment_deployed only on detonation (not on placement), so mobile_controls keeps showing
# the (now-armed) button for that second tap instead of hiding it early.
func _use_mine(item: Dictionary) -> void:
	if GameManager.mine_state == GameManager.MINE_READY:
		var tex: Texture2D = load("res://assets/icons/" + item["file"])
		_placed_mine = GRENADE_SCENE.instantiate()
		_props.add_child(_placed_mine)
		_placed_mine.configure_mine(tex, _player.global_position, item["damage"], item["aoe_radius"])
		GameManager.mine_state = GameManager.MINE_ARMED
	else:
		if _placed_mine != null and is_instance_valid(_placed_mine):
			_placed_mine.detonate()
		_placed_mine = null
		GameManager.mine_state = GameManager.MINE_READY
		# 5 uses per run — only hide the button once they're all spent.
		GameManager.mine_charges = max(0, GameManager.mine_charges - 1)
		if GameManager.mine_charges <= 0:
			GameManager.equipment_deployed = true

# Deployable Barrier Wall's two-tap cycle (see item_registry.gd's barrier field docs): first
# tap (READY) starts the trail-placement scene tracking the player's movement; second tap
# (PLACING) ends it early. Either that or the scene's own length cap finalizes it and emits
# finished, which _on_barrier_finished handles uniformly either way.
func _use_barrier(item: Dictionary) -> void:
	if GameManager.barrier_state == GameManager.BARRIER_READY:
		_active_barrier = BARRIER_SCENE.instantiate()
		_props.add_child(_active_barrier)
		_active_barrier.finished.connect(_on_barrier_finished)
		_active_barrier.start(_player, item.get("barrier_max_length", 200.0), item.get("barrier_thickness", 12.0))
		GameManager.barrier_state = GameManager.BARRIER_PLACING
	elif _active_barrier != null and is_instance_valid(_active_barrier):
		_active_barrier.stop_and_finalize()

func _on_barrier_finished() -> void:
	_active_barrier = null
	GameManager.barrier_state = GameManager.BARRIER_READY
	GameManager.equipment_deployed = true

# Applies whatever effect(s) the equipped defensive item's ItemRegistry row specifies (see
# item_registry.gd's heal_item field docs) — fully data-driven, so a new heal item needs no
# changes here. One-time per run for everything except shield — mobile_controls hides its
# button after this fires once, EXCEPT for a Shield Barrier, which is a repeatable on/off
# toggle (see player.gd's toggle_shield) and so bypasses the one-shot heal_item_deployed gate
# entirely; the HP it's already absorbed still applies across toggles, it just isn't draining
# while switched off.
func _use_heal_item() -> void:
	var item: Dictionary = SaveManager.equipped_defensive
	if item.is_empty() or not item.get("heal_item", false):
		return
	if item.get("shield", false):
		_player.toggle_shield()
		return
	if GameManager.heal_item_deployed:
		return
	GameManager.heal_item_deployed = true
	if item.get("heal_full", false):
		_player.heal_full()
	elif item.get("heal_instant") != null:
		_player.heal(item["heal_instant"])
	if item.get("heal_regen_amount") != null:
		_player.start_regen(item["heal_regen_amount"], item.get("heal_regen_interval", 1.0), item["heal_regen_duration"])
	if item.get("speed_boost_multiplier") != null:
		_player.apply_speed_boost(item["speed_boost_multiplier"], item.get("speed_boost_duration", 0.0))
	if item.get("heal_dispenser", false):
		_spawn_heal_dispenser(item)

# Places a heal_dispenser.tscn instance at the player's current position — see
# item_registry.gd's heal_dispenser field docs.
func _spawn_heal_dispenser(item: Dictionary) -> void:
	var dispenser: Node2D = HEAL_DISPENSER_SCENE.instantiate()
	_props.add_child(dispenser)
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	dispenser.configure(tex, _player.global_position, item.get("dispenser_interval", 5.0),
		item.get("dispenser_duration", 20.0), item.get("dispenser_heal_amount", 5))

# Speed Boost Battery: activates the boost if the button's ready — player.gd's activate_battery
# is the authoritative ready-state guard, this just relays the tap. Unlike the one-shot
# equipment/heal-item flows above, this is repeatable indefinitely (see item_registry.gd's
# battery field docs), so there's no *_deployed flag to set here.
func _use_battery() -> void:
	_player.activate_battery()

# ── Rooms, doors, and progression ───────────────────────────────────────────────────────────

# Enemy roster tiers by floor (see the Enemy Data sheet / enemy_basic.gd TYPES): basics appear
# anywhere; tier-2 units join at floor 10, tier-3 at floor 20.
const BASIC_TYPES := ["M", "L"]
const TIER2_TYPES := ["Void", "Warp", "Crater"]
const TIER3_TYPES := ["Cryo", "Solar", "Nebula", "Nova"]
# Boss floors: only the boss spawns (no other enemies) — see _spawn_enemies_for_room.
const BOSS_BY_FLOOR := {15: "Boss1", 25: "Boss2"}
const FINAL_BOSS_FLOOR := 35    # two-phase final boss + "I Got Soda" music (see _spawn_final_boss_*)
const FINAL_BOSS_MAX_COUNT := 8 # phase-2 split cap so it can't runaway-multiply
var _final_boss_phase := 0      # 0 = not fighting the final boss, 1/2 = which phase

# Enemy count ramps every two floors: 2 (1-2), 3 (3-4), 4 (5-6), 5 (7+) — never more than 5.
func _enemy_count_for_floor(n: int) -> int:
	if n <= 2:
		return 2
	elif n <= 4:
		return 3
	elif n <= 6:
		return 4
	return 5

# Spawns this room's enemies. The count scales by floor (capped at 5), and difficulty scales by
# swapping basic M/L units for tougher tier-2/tier-3 types the deeper you go — the enemies
# themselves have fixed per-type stats (no per-floor stat inflation).
func _spawn_enemies_for_room() -> void:
	var st: Dictionary = _rooms[_current_pos]
	var n: int = st["number"]
	# Final boss floor (35): its own two-phase fight + music.
	if n == FINAL_BOSS_FLOOR:
		_spawn_final_boss_phase1()
		return
	# Boss floors (15, 25): a single boss spawns in the centre, alone.
	if BOSS_BY_FLOOR.has(n):
		_spawn_boss(BOSS_BY_FLOOR[n])
		return
	# Drop only the spots RIGHT next to the door the player just entered (within DOOR_CLEARANCE),
	# then pick randomly from the rest — so enemies can be moderately close but never on top of the
	# entrance. Falls back to the farthest spots if too few remain.
	var entry_pos: Vector2 = _room.entry_position(_current_entry_side) if _current_entry_side != -1 else _room.player_spawn_pos
	const DOOR_CLEARANCE := 150.0
	var all_spawns: Array = _room.enemy_spawn_positions.duplicate()
	var count: int = mini(_enemy_count_for_floor(n), all_spawns.size())
	var spawns: Array = all_spawns.filter(func(p): return p.distance_to(entry_pos) >= DOOR_CLEARANCE)
	if spawns.size() >= count:
		spawns.shuffle()
	else:
		all_spawns.sort_custom(func(a, b): return a.distance_to(entry_pos) > b.distance_to(entry_pos))
		spawns = all_spawns

	# Which tougher types are available, and how many of the slots they take over (grows with
	# depth past floor 10, eventually replacing every basic unit).
	var hard_pool: Array = []
	if n >= 20:
		hard_pool = TIER2_TYPES + TIER3_TYPES
	elif n >= 10:
		hard_pool = TIER2_TYPES
	var hard: int = 0
	if not hard_pool.is_empty():
		hard = mini(count, 1 + int((n - 10) / 3))

	var types: Array = []
	for i in range(count):
		if i < hard:
			types.append(hard_pool[randi() % hard_pool.size()])
		else:
			types.append(BASIC_TYPES[randi() % BASIC_TYPES.size()])
	types.shuffle()

	_enemies_alive = count
	_clearing = false
	for i in range(count):
		var e: CharacterBody2D = ENEMY_SCENE.instantiate()
		e.configure_type(types[i])
		e.global_position = spawns[i]
		e.died.connect(_on_enemy_died)
		_enemies.add_child(e)

# Spawns a single boss (Boss1/Boss2) in the centre of the play area — the whole floor's fight.
func _spawn_boss(type_key: String) -> void:
	_enemies_alive = 1
	_clearing = false
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	e.configure_type(type_key)
	e.global_position = GameManager.play_rect.get_center()
	e.died.connect(_on_enemy_died)
	_enemies.add_child(e)

# ── Final boss (floor 35) ───────────────────────────────────────────────────────────────────
# Phase 1: a lone 500-HP boss; the "I Got Soda" track fades in and loops its first section. On
# death the room does NOT clear — a Continue prompt appears, and choosing it starts phase 2: the
# boss respawns (music restarts at 4:20) and now splits in two every 10s. Clearing phase 2 clears
# the room normally and restores the background music.
func _spawn_final_boss_phase1() -> void:
	_final_boss_phase = 1
	_enemies_alive = 1
	_clearing = false
	AudioManager.start_boss_music_phase1()
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	e.configure_type("BossF")
	e._gold = 0 # phase 1 "respawns" — the payout comes from phase 2
	e.global_position = GameManager.play_rect.get_center()
	e.died.connect(_on_final_boss_phase1_died)
	_enemies.add_child(e)

func _on_final_boss_phase1_died() -> void:
	_enemies_alive = 0
	GameManager.ui_popup_open = true
	_reward_popup = _build_popup_shell()
	var vbox: VBoxContainer = _reward_popup.get_meta("vbox")
	var title := Label.new()
	title.text = "☠  Phase 1 down!"
	title.add_theme_font_size_override("font_size", 19)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var msg := Label.new()
	msg.text = "The boss reforms, stronger — and now splits. Ready?"
	msg.add_theme_font_size_override("font_size", 14)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(msg)
	var btn := Button.new()
	btn.text = "Continue"
	btn.custom_minimum_size = Vector2(0, 48)
	btn.pressed.connect(_start_final_boss_phase2)
	vbox.add_child(btn)

func _start_final_boss_phase2() -> void:
	_close_reward_popup()
	_final_boss_phase = 2
	_enemies_alive = 1
	_clearing = false
	AudioManager.start_boss_music_phase2()
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	e.configure_type("BossF")
	e._gold = 0 # the 9999 payout is awarded once the whole phase-2 fight is won (see _on_enemy_died)
	e.enable_boss_split()
	e.global_position = GameManager.play_rect.get_center()
	e.died.connect(_on_enemy_died)
	e.boss_split.connect(_on_boss_split)
	_enemies.add_child(e)

# A phase-2 boss split in two: spawn its twin at half HP (capped so it can't runaway-multiply).
func _on_boss_split(pos: Vector2, hp: int) -> void:
	if _enemies.get_child_count() >= FINAL_BOSS_MAX_COUNT:
		return
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	e.configure_type("BossF")
	e._gold = 0 # only the original drops the payout
	e.max_health = hp # _ready() sets health = max_health
	e.enable_boss_split()
	e.global_position = pos + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * 70.0
	e.died.connect(_on_enemy_died)
	e.boss_split.connect(_on_boss_split)
	_enemies.add_child(e)
	_enemies_alive += 1

func _on_enemy_died() -> void:
	_enemies_alive -= 1
	if _enemies_alive <= 0 and not _clearing:
		if _final_boss_phase == 2:
			GameManager.add_coins(9999) # final-boss payout, awarded once phase 2 is fully cleared
		if _final_boss_phase != 0: # final boss defeated → back to normal music
			_final_boss_phase = 0
			AudioManager.stop_boss_music()
		_on_room_cleared()

# Restore the background track whenever the run is left (death → game over, or back to menu).
func _exit_tree() -> void:
	AudioManager.stop_boss_music()

# Places the shop-keeper NPC in the middle of a shop room. Room-scoped (added to _props so it's
# freed on the next transition). The shop dialog opens when the player walks up to it — see the
# proximity check in _physics_process.
func _spawn_shop_npc() -> void:
	var npc: Node2D = SHOP_NPC_SCENE.instantiate()
	npc.global_position = GameManager.play_rect.get_center() # corridor centre
	_props.add_child(npc)
	_shop_npc = npc
	_shop_npc_active = false

# Room cleared: the doors (rolled at creation, red until now) unlock in place — entry turns
# blue, exits green. (Shop rooms have no enemies, so they never reach here — they're marked
# cleared on creation and the shop is opened by walking up to the keeper instead.)
func _on_room_cleared() -> void:
	_clearing = true
	var st: Dictionary = _rooms[_current_pos]
	st["cleared"] = true
	_refresh_doors()
	_rooms_cleared += 1
	GameManager.record_floor_cleared()
	GameManager.room_cleared.emit()

# Every SHOP_EVERY_N_FLOORS'th room (floor 10, 20, ...) is a shop room instead of a fight.
func _is_shop_room(number: int) -> bool:
	return number > 0 and number % SHOP_EVERY_N_FLOORS == 0

# Picks a Hallway variant whose baked-in doors include the entry side (any variant for the starting
# room, entry_side -1), so the loaded art always has a door where the player came from. Returns the
# variant dict {tex, doors}.
func _pick_variant(entry_side: int) -> Dictionary:
	var candidates: Array = []
	for v in HALLWAY_VARIANTS:
		if entry_side == -1 or entry_side in v["doors"]:
			candidates.append(v)
	return candidates[randi() % candidates.size()]

# Builds a room state for the given entry side: picks a matching art variant and stores its FULL
# door set (which always contains the entry side). When the room is cleared every one of those doors
# is walkable — the current entry is drawn blue (the way back), the rest green.
func _make_room(entry_side: int, cleared: bool, number: int) -> Dictionary:
	var variant := _pick_variant(entry_side)
	return {"cleared": cleared, "doors": variant["doors"].duplicate(), "entry_side": entry_side, "number": number, "variant": variant["tex"]}

# Doors the player can currently walk through: none while the room is uncleared (every door,
# including the one they came in through, stays locked until the fight is won), then all of
# them — the 3 exits plus the blue back door.
func _active_door_sides() -> Array:
	var st: Dictionary = _rooms[_current_pos]
	if not st["cleared"]:
		return []
	var sides: Array = st["doors"].duplicate()
	if _current_entry_side != -1 and not sides.has(_current_entry_side):
		sides.append(_current_entry_side)
	return sides

func _refresh_doors() -> void:
	var st: Dictionary = _rooms[_current_pos]
	_room.set_map_texture(st["variant"]) # load the art whose doors match this room
	_room.set_doors(_current_entry_side, st["doors"], not st["cleared"])

# Door polling: walls stay physically solid behind the drawn gaps, so transitions trigger off
# the player overlapping a door's zone (which reaches slightly into the room) rather than
# actually passing through the wall.
func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or GameManager.ui_popup_open:
		return
	_tick_artifact_regen(_delta)
	# Shop keeper: open the shop when the player walks up. _shop_npc_active debounces so it fires
	# once on approach; after Leaving the shop the player must step out of range and back in.
	if _shop_npc != null and is_instance_valid(_shop_npc):
		var near := _player.global_position.distance_to(_shop_npc.global_position) <= SHOP_TALK_RANGE
		if near and not _shop_npc_active:
			_shop_npc_active = true
			_show_shop()
			return
		elif not near:
			_shop_npc_active = false
	for side in _active_door_sides():
		if _room.door_zone(side).has_point(_player.global_position):
			_go_through_door(side)
			return

# Crate-spin ticker: while the reward crate is spinning, play a tick each time a new card
# crosses the center marker. idx grows as the track scrolls left; it slows with the tween's
# cubic ease-out, so the ticks space out toward the end for the classic case-opening feel.
func _process(_delta: float) -> void:
	if _crate_track == null or not is_instance_valid(_crate_track):
		return
	var slot := float(CRATE_CARD_W + CRATE_CARD_GAP)
	var idx := int((_crate_stage.size.x * 0.5 - _crate_track.position.x) / slot)
	if idx != _crate_last_tick:
		_crate_last_tick = idx
		AudioManager.play_tick()

func _opposite(side: int) -> int:
	match side:
		0: return 1
		1: return 0
		2: return 3
		3: return 2
	return -1

# Walk through a door: room-scoped props and enemies are cleared (every room shares the same
# physical screen space), the grid position moves one cell, and the destination either spawns
# fresh scaled enemies (first visit, or re-entering a room fled from before clearing it) or
# sits empty (already cleared). The player arrives just inside the matching door on the far
# side, which immediately doubles as the way back.
func _go_through_door(side: int) -> void:
	# Finalize any in-progress barrier placement before its node is freed with the props,
	# otherwise the green button would be stuck in the PLACING state with nothing to finish.
	if _active_barrier != null and is_instance_valid(_active_barrier):
		_active_barrier.stop_and_finalize()
	for c in _props.get_children():
		c.queue_free()
	for c in _enemies.get_children():
		c.queue_free()
	_placed_mine = null
	_shop_npc = null
	_shop_npc_active = false
	_enemies_alive = 0

	# Hoverboard burns one room of its budget per room entered while mounted; auto-dismount at 0.
	if GameManager.equipment_hoverboard and GameManager.hoverboard_active:
		GameManager.hoverboard_rooms_remaining -= 1
		if GameManager.hoverboard_rooms_remaining <= 0:
			GameManager.hoverboard_rooms_remaining = 0
			_player.toggle_hoverboard() # dismount

	# Barrier Wall replenishes each floor — its one-shot deploy flag resets so it can be placed
	# again in the next room (only the barrier is the equipped item, so this affects nothing else).
	if GameManager.equipment_barrier:
		GameManager.equipment_deployed = false
		GameManager.barrier_state = GameManager.BARRIER_READY

	_current_pos += SIDE_OFFSETS[side]
	var entry := _opposite(side)
	_current_entry_side = entry
	if not _rooms.has(_current_pos):
		_rooms_entered += 1
		# Shop rooms carry no fight, so they start "cleared" — doors open immediately.
		var is_shop := _is_shop_room(_rooms_entered)
		_rooms[_current_pos] = _make_room(entry, is_shop, _rooms_entered)
		if is_shop:
			GameManager.record_floor_cleared() # shop floors count as cleared for run stats
	var st: Dictionary = _rooms[_current_pos]
	GameManager.current_floor = st["number"]
	GameManager.floor_changed.emit(st["number"])
	_player.global_position = _room.entry_position(entry)
	_grant_room_invincibility() # Invincible+ artifact — every room entry
	_refresh_doors()
	if _is_shop_room(st["number"]):
		_spawn_shop_npc()
	elif not st["cleared"]:
		_spawn_enemies_for_room()

# Invincible+ artifact: grant the room-entry invincibility window (no-op if not equipped).
func _grant_room_invincibility() -> void:
	if _player != null and is_instance_valid(_player):
		_player.grant_room_invincible(ItemRegistry.artifact_num("room_invincible_seconds", 0.0))

# Regen+ artifact: while a fight is ongoing (enemies still alive), heal the player 1 HP/sec.
var _regen_accum := 0.0
func _tick_artifact_regen(delta: float) -> void:
	var rate := ItemRegistry.artifact_num("regen_per_sec", 0.0)
	if rate <= 0.0 or _player == null or not is_instance_valid(_player) or _enemies_alive <= 0:
		_regen_accum = 0.0
		return
	if _player.health >= _player.max_health:
		return
	_regen_accum += rate * delta
	if _regen_accum >= 1.0:
		var whole := int(_regen_accum)
		_player.heal(whole)
		_regen_accum -= float(whole)

# ── Every-5-rooms reward: full heal, or open a crate and swap the matching equipped item ────

const SLOT_KEY_BY_TYPE := {"weapon": "equipped_weapon", "equipment": "equipped_equipment", "defensive": "equipped_defensive"}

# Crate spin visuals — mirrors open_crate.gd's card track (sized down to fit the popup panel).
const CRATE_CARD_W := 110
const CRATE_CARD_H := 110
const CRATE_CARD_GAP := 8
const CRATE_WINNER_IDX := 42
const CRATE_RARITY_COLORS := {
	"common":    Color(0.22, 0.22, 0.27),
	"uncommon":  Color(0.07, 0.32, 0.11),
	"rare":      Color(0.07, 0.14, 0.48),
	"epic":      Color(0.28, 0.07, 0.42),
	"legendary": Color(0.50, 0.35, 0.00),
}

# Shop (opens after clearing every 10th floor — see _on_room_cleared). The NPC offers a full
# heal, a crate spin, and an upgrade to the current weapon, all paid for with run-scoped coins.
# The player may buy as many as they can afford; the shop stays open (rebuilt after each purchase
# so balances/enabled-states refresh) until they Leave. Once left, it can't be reopened — the
# next shop is 10 floors later. Rebuilt fresh on every call, freeing any prior popup first.
# Shop+ artifact halves every shop price — display, afford-check and deduction all route through here.
func _shop_price(base: int) -> int:
	return int(round(float(base) * ItemRegistry.artifact_num("shop_mult", 1.0)))

func _show_shop() -> void:
	if _reward_popup != null and is_instance_valid(_reward_popup):
		_reward_popup.queue_free()
		_reward_popup = null
	_return_to_shop = false
	GameManager.ui_popup_open = true
	_reward_popup = _build_popup_shell()
	var vbox: VBoxContainer = _reward_popup.get_meta("vbox")

	var title := Label.new()
	title.text = "🛒  Shop"
	title.add_theme_font_size_override("font_size", 19)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var npc := Label.new()
	npc.text = "What would you like to buy?"
	npc.add_theme_font_size_override("font_size", 14)
	npc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	npc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(npc)

	var coins_lbl := Label.new()
	coins_lbl.text = "🪙 %d coins" % GameManager.coins
	coins_lbl.add_theme_font_size_override("font_size", 15)
	coins_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2))
	coins_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(coins_lbl)

	var can_heal: bool = _player != null and is_instance_valid(_player) and _player.health < _player.max_health
	var heal_btn := Button.new()
	heal_btn.text = "❤️  Full Heal — %d🪙" % _shop_price(SHOP_HEAL_COST)
	heal_btn.custom_minimum_size = Vector2(0, 48)
	heal_btn.disabled = GameManager.coins < _shop_price(SHOP_HEAL_COST) or not can_heal
	heal_btn.pressed.connect(_shop_buy_heal)
	vbox.add_child(heal_btn)

	var crate_btn := Button.new()
	crate_btn.text = "📦  Spin a Crate — %d🪙" % _shop_price(SHOP_CRATE_COST)
	crate_btn.custom_minimum_size = Vector2(0, 48)
	crate_btn.disabled = GameManager.coins < _shop_price(SHOP_CRATE_COST)
	crate_btn.pressed.connect(_shop_choose_crate)
	vbox.add_child(crate_btn)

	var wname: String = SaveManager.equipped_weapon.get("name", "")
	var level: int = _weapon_upgrades.get(wname, 0)
	var up_btn := Button.new()
	up_btn.custom_minimum_size = Vector2(0, 48)
	if wname == "":
		up_btn.text = "⬆️  No weapon to upgrade"
		up_btn.disabled = true
	elif level >= WEAPON_UPGRADE_MAX:
		up_btn.text = "⬆️  %s — Max upgrades" % wname
		up_btn.disabled = true
	else:
		var effect: String = "1.5× damage" if level == 0 else "1.5× fire rate"
		up_btn.text = "⬆️  Upgrade %s (%s) — %d🪙" % [wname, effect, _shop_price(SHOP_UPGRADE_COST)]
		up_btn.disabled = GameManager.coins < _shop_price(SHOP_UPGRADE_COST)
	up_btn.pressed.connect(_shop_buy_upgrade)
	vbox.add_child(up_btn)

	var leave_btn := Button.new()
	leave_btn.text = "Leave Shop"
	leave_btn.custom_minimum_size = Vector2(0, 44)
	leave_btn.pressed.connect(_close_reward_popup)
	vbox.add_child(leave_btn)

func _shop_buy_heal() -> void:
	if GameManager.coins < _shop_price(SHOP_HEAL_COST):
		return
	GameManager.coins -= _shop_price(SHOP_HEAL_COST)
	if _player != null and is_instance_valid(_player):
		_player.heal_full()
	_show_shop()

func _shop_buy_upgrade() -> void:
	var wname: String = SaveManager.equipped_weapon.get("name", "")
	if wname == "" or GameManager.coins < _shop_price(SHOP_UPGRADE_COST):
		return
	var level: int = _weapon_upgrades.get(wname, 0)
	if level >= WEAPON_UPGRADE_MAX:
		return
	GameManager.coins -= _shop_price(SHOP_UPGRADE_COST)
	_weapon_upgrades[wname] = level + 1
	_reequip_weapon()
	_show_shop()

# Crate purchase: pick which crate type to spin (weapons/equipment/medical). Coins are only
# deducted once a type is chosen (Cancel returns to the shop with no charge).
func _shop_choose_crate() -> void:
	if _reward_popup != null and is_instance_valid(_reward_popup):
		_reward_popup.queue_free()
		_reward_popup = null
	GameManager.ui_popup_open = true
	_reward_popup = _build_popup_shell()
	var vbox: VBoxContainer = _reward_popup.get_meta("vbox")

	var title := Label.new()
	title.text = "📦  Pick a crate — %d🪙" % _shop_price(SHOP_CRATE_COST)
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	for crate in [["weapon", "🗡️  Weapons Crate"], ["equipment", "🎒  Equipment Crate"], ["medical", "🧰  Medical Crate"]]:
		var btn := Button.new()
		btn.text = crate[1]
		btn.custom_minimum_size = Vector2(0, 48)
		btn.pressed.connect(_shop_buy_crate.bind(crate[0]))
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 44)
	cancel.pressed.connect(_show_shop)
	vbox.add_child(cancel)

func _shop_buy_crate(crate: String) -> void:
	if GameManager.coins < _shop_price(SHOP_CRATE_COST):
		_show_shop()
		return
	GameManager.coins -= _shop_price(SHOP_CRATE_COST)
	var item: Dictionary = ItemRegistry.roll_item_for_crate(crate)
	SaveManager.add_to_inventory(item)
	_return_to_shop = true # equip/keep afterward comes back to the shop
	if _reward_popup != null and is_instance_valid(_reward_popup):
		_reward_popup.queue_free()
		_reward_popup = null
	_show_crate_spin(item, crate)

# After a crate's equip-or-keep choice: return to the shop if the spin came from there,
# otherwise just close.
func _after_crate_choice() -> void:
	if _return_to_shop:
		_show_shop()
	else:
		_close_reward_popup()

# Shared overlay skeleton for the reward popups: full-screen dim + centered panel + a vbox
# (stashed as metadata) for the caller to fill. Added to the HUD CanvasLayer so it draws over
# everything in the world.
func _build_popup_shell() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud.add_child(overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -190.0
	panel.offset_right  =  190.0
	panel.offset_top    = -170.0
	panel.offset_bottom =  170.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  16)
	margin.add_theme_constant_override("margin_top",    14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)
	overlay.set_meta("vbox", vbox)
	return overlay

# In-popup replica of open_crate.gd's spin: a clipped track of random item cards scrolls past
# a center marker with a cubic ease-out, landing on the rolled winner, then hands off to the
# equip-or-keep result. The spin popup has no buttons, so taps during it do nothing.
func _show_crate_spin(item: Dictionary, crate: String) -> void:
	GameManager.ui_popup_open = true
	_reward_popup = _build_popup_shell()
	var vbox: VBoxContainer = _reward_popup.get_meta("vbox")

	var title := Label.new()
	title.text = "📦  Opening crate..."
	title.add_theme_font_size_override("font_size", 17)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, CRATE_CARD_H)
	stage.clip_contents = true
	vbox.add_child(stage)

	# Reel cards are drawn from the same crate's type so the scrolling matches what you opened.
	var track := HBoxContainer.new()
	track.add_theme_constant_override("separation", CRATE_CARD_GAP)
	stage.add_child(track)
	for _i in range(CRATE_WINNER_IDX):
		track.add_child(_make_crate_card(ItemRegistry.random_item_for_crate(crate)))
	track.add_child(_make_crate_card(item))
	for _i in range(8):
		track.add_child(_make_crate_card(ItemRegistry.random_item_for_crate(crate)))

	# Center marker line over the track, so it's clear which card the spin lands on.
	var marker := ColorRect.new()
	marker.color = Color(1.0, 0.85, 0.2, 0.9)
	marker.anchor_left = 0.5
	marker.anchor_right = 0.5
	marker.offset_left = -1.5
	marker.offset_right = 1.5
	marker.offset_top = 0.0
	marker.offset_bottom = CRATE_CARD_H
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(marker)

	# Wait a frame so the stage's container size is resolved before positioning the track
	# (same trick open_crate.gd uses).
	await get_tree().process_frame
	if _reward_popup == null or not is_instance_valid(_reward_popup):
		return
	var vw := stage.size.x
	var slot := CRATE_CARD_W + CRATE_CARD_GAP
	var init_x := vw * 0.5 - slot * 0.5
	# Random off-center landing within the winner card (±35% of its width) so the stop looks
	# random — purely visual, the item comes from `item` not the landing position.
	var jitter := randf_range(-CRATE_CARD_W * 0.35, CRATE_CARD_W * 0.35)
	var end_x := vw * 0.5 - (CRATE_WINNER_IDX * slot + CRATE_CARD_W * 0.5) + jitter
	track.position = Vector2(init_x, 0)
	# Arm the _process tick ticker for the duration of the spin.
	_crate_track = track
	_crate_stage = stage
	_crate_last_tick = -1
	var tw := create_tween()
	tw.tween_property(track, "position:x", end_x, 5.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		_crate_track = null
		_close_reward_popup()
		_show_crate_result(item)
	)

func _make_crate_card(item: Dictionary) -> Control:
	var card := Control.new()
	card.custom_minimum_size = Vector2(CRATE_CARD_W, CRATE_CARD_H)
	var bg := ColorRect.new()
	bg.size = Vector2(CRATE_CARD_W, CRATE_CARD_H)
	bg.color = CRATE_RARITY_COLORS.get(item.get("rarity", ""), Color(0.2, 0.2, 0.2)) as Color
	card.add_child(bg)
	var tex := TextureRect.new()
	tex.size = Vector2(CRATE_CARD_W, CRATE_CARD_H)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.texture = load("res://assets/icons/" + str(item.get("file", "")))
	card.add_child(tex)
	return card

# The reveal: what they won, what's currently equipped in that slot, and the choice — equip
# the new item (loadout re-applied so it works immediately) or keep what they have. Either
# way the rolled item is already in the inventory.
func _show_crate_result(item: Dictionary) -> void:
	GameManager.ui_popup_open = true
	_reward_popup = _build_popup_shell()
	var vbox: VBoxContainer = _reward_popup.get_meta("vbox")

	var title := Label.new()
	title.text = "You got:"
	title.add_theme_font_size_override("font_size", 17)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var center := CenterContainer.new()
	vbox.add_child(center)
	center.add_child(_make_crate_card(item))

	var slot_key: String = SLOT_KEY_BY_TYPE.get(item["type"], "")
	var current: Dictionary = SaveManager.get_slot(slot_key) if slot_key != "" else {}
	var current_name: String = current["name"] if not current.is_empty() else "(empty)"

	var name_lbl := Label.new()
	name_lbl.text = "%s (%s)\nCurrent %s: %s" % [item["name"], String(item["rarity"]).capitalize(), item["type"], current_name]
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	if slot_key != "":
		var equip_btn := Button.new()
		equip_btn.text = "Equip it (replaces %s)" % current_name
		equip_btn.custom_minimum_size = Vector2(0, 52)
		equip_btn.pressed.connect(func():
			SaveManager.set_slot(slot_key, item)
			_apply_loadout()
			_hud.refresh_equipped_icons() # reflect the swapped item in the top-left icons
			_after_crate_choice()
		)
		vbox.add_child(equip_btn)

	var keep_btn := Button.new()
	keep_btn.text = "Keep current item"
	keep_btn.custom_minimum_size = Vector2(0, 52)
	keep_btn.pressed.connect(_after_crate_choice)
	vbox.add_child(keep_btn)

func _close_reward_popup() -> void:
	if _reward_popup != null and is_instance_valid(_reward_popup):
		_reward_popup.queue_free()
	_reward_popup = null
	GameManager.ui_popup_open = false

# Direct touch fallback for the reward popup's buttons, same reasoning as menu.gd/
# character.gd: ButtonNode.pressed only fires on InputEventMouseButton, but the embedded
# display server may not run emulate_mouse_from_touch, so popup taps could otherwise silently
# do nothing on iOS.
func _input(event: InputEvent) -> void:
	if _reward_popup == null or not is_instance_valid(_reward_popup):
		return
	if event is InputEventScreenTouch and event.pressed:
		var btn := _find_button_at(_reward_popup, event.position)
		if btn != null:
			btn.pressed.emit()
			get_viewport().set_input_as_handled()

# Hit-test with get_global_transform_with_canvas() (maps local → screen pixels, correct under the
# EXPAND stretch) against the raw touch position — get_final_transform()/get_global_rect() mapped
# wrong under EXPAND, so popup buttons could fire the wrong (or no) button.
func _find_button_at(root: Node, pixel_pos: Vector2) -> Button:
	for child in root.get_children():
		if child is Button and (child as Button).visible:
			var ctrl := child as Control
			var local: Vector2 = ctrl.get_global_transform_with_canvas().affine_inverse() * pixel_pos
			if Rect2(Vector2.ZERO, ctrl.size).has_point(local):
				return child
		var found := _find_button_at(child, pixel_pos)
		if found != null:
			return found
	return null
