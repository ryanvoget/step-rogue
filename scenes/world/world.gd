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
const UI_THEME := preload("res://scenes/ui/ui_theme.gd")
const BARTENDER_SCENE  := preload("res://scenes/bartender/bartender.tscn")
const BAR_PATRON_SCENE := preload("res://scenes/bar_patron/bar_patron.tscn")
const DASH_PICKUP_SCENE := preload("res://scenes/dash_pickup/dash_pickup.tscn")
const COIN_SCENE := preload("res://scenes/coin/coin.tscn") # re-dropping gold left in a room
const FIRE_PATCH_SCENE := preload("res://scenes/fx/fire_patch.tscn") # Fire Trail+ artifact
const WAVE_PULSE_SCENE := preload("res://scenes/fx/wave_pulse.tscn") # Wave Pulse+ artifact

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
# Combat rooms pick between the hallway variants and these whole-room layouts, evenly. Each entry
# lists the door sides its art actually has (0=top,1=bottom,2=left,3=right) — a layout is only
# eligible if it has a door on the side the player entered from, exactly like HALLWAY_VARIANTS.
# "hallway" is the sentinel for "use _pick_variant to choose one of the hallway PNGs".
const COMBAT_LAYOUTS := [
	{"kind": "hallway", "doors": [0, 1, 2, 3]}, # per-variant door sets are checked in _pick_variant
	{"kind": "control", "doors": [0, 1, 2, 3]},
	{"kind": "cockpit", "doors": [0, 1, 2]},    # no right door — that edge is the windscreen
	{"kind": "docking", "doors": [1, 2, 3]},    # no top door — that edge is the window
]
const GRENADE_CHARGES := 5 # throwable grenades get this many uses per run instead of one-shot
const TURRET_CHARGES := 5   # placeable turrets get this many deploys per run instead of one-shot
const MINE_CHARGES := 5     # detonator mines get this many uses per run instead of one-shot
const SHOP_EVERY_N_FLOORS := 10 # legacy (superseded by the banded shop floors below)
# Shops appear on banded floors: the Nth shop lands somewhere in floors [7N .. 9N] — "every 7-9 of
# the total", not 7-9 after the last shop (so the 2nd shop can be as late as floor 18). Rolled once
# per run into _shop_floors (see _ready), never on a boss floor (BOSS_FLOORS).
const SHOP_BAND_MIN := 7
const SHOP_BAND_MAX := 9
const SHOP_TALK_RANGE := 66.0 # walk within this of the NPC to open the shop dialog
# Bar rooms: banded like shops (Nth bar somewhere in floors [10N..11N]), never on a shop/boss floor.
# A 2x-wide scrolling cantina with a bartender (drinks-for-coins) and ambient patrons, no enemies.
const BAR_BAND_MIN := 10
const BAR_BAND_MAX := 11
const BAR_TALK_RANGE := 80.0
const BAR_TABLE_OFFSET := 232.0 # fusion table, right of the counter ring
const FUSION_TABLE_SCENE := preload("res://scenes/fusion_table/fusion_table.tscn")
const BAR_DRINKS := [[50, 15], [100, 30], [150, 50]] # [cost, HP restored]
# Bar artifact terminal (the blue screen in the art, top-left). Pay once to have it offer
# TERMINAL_CHOICES artifacts rolled at the normal rarity odds, then pick whichever one you want.
# This replaced the slot machine, which rolled a single artifact you had no say over.
const TERMINAL_COST := 80
const TERMINAL_CHOICES := 3
const BAR_PATRON_COUNT := 6
# These are in the bar's own 1041x960 space (its art is drawn 1:1, not at 2x like the hallways).
const BAR_PATRON_SPACING := 75.0      # keep patrons from overlapping each other
const BAR_COUNTER_CLEARANCE := 160.0  # ...and out of the counter ring
const BAR_SCREEN_CLEARANCE := 130.0   # ...and away from the terminal so they don't block it
const GOLD_PER_UNUSED_POINT := 50 # each loadout point NOT spent converts to this much starting gold
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
var _spawn_token    := 0 # bumped per room; pending spawns from an old room check it and bail
var _spawn_queue: Array = []   # groups still to arrive, each [[type, pos], ...]
var _spawn_timer    := 0.0     # countdown to the next group
var _spawn_interval := 3.5     # gap between groups on this floor
var _spawn_telegraphed := false # has the pending group's ring been shown yet
const ENEMY_BODY_RADIUS := 18.0 # matches enemy_basic's _radius — the telegraph ring's size
var _clearing       := false
var _placed_mine: Node2D = null
var _active_barrier: Node2D = null
var _active_sidekick: Node2D = null
var _shop_npc: Node2D = null      # the shop-keeper in the current room (shop rooms only)
var _shop_npc_active := false     # true while the player is standing in talk range — debounces
                                  # so the dialog only opens on approach, not every frame, and
                                  # can be reopened by stepping away and back after Leaving
var _bartender: Node2D = null     # the bartender in the current room (bar rooms only)
var _bartender_active := false    # proximity debounce for the drink dialog (same idea as shop)
var _bar_screen_pos := Vector2.ZERO # artifact terminal position (painted into the bar art)
var _fusion_table: Node2D = null   # the weapon-fusion console beside the bar counter
var _fusion_table_active := false  # debounce, same pattern as the bartender/terminal
var _terminal_active := false       # proximity debounce for the terminal dialog
var _terminal_offer: Array = []     # the artifacts currently on offer (empty until paid for)
var _terminal_selected := -1        # which offer the player has tapped (shows its description)
var _loadout_bonus := 0           # starting gold from unused loadout points (see _grant_loadout_bonus)
var _unused_points := 0
var _camera: Camera2D = null      # fixed for combat rooms, scrolls with the player for bar rooms
var _room_kind := "combat"        # current room's kind — drives the camera + spawns
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
var _spinning := false # true while an artifact spin reel is animating — guards against a double-fired
                       # tap (screen-touch + emulated mouse) starting two overlapping spins
# Upgrade tree bought at shops. Two branches (damage, rate of fire), 5 bubbles each, per weapon.
# Each dict maps weapon name -> tiers purchased (0..5). Bubble i multiplies by UPGRADE_MULTS[i]
# on top of the previous, so the total is the product; costs scale UPGRADE_COSTS[i]. Damage tier
# scales damage, rof tier speeds fire_rate (divides it). Applied in _reequip_weapon.
const UPGRADE_MULTS := [1.1, 1.2, 1.3, 1.4, 1.5]
const UPGRADE_COSTS := [100, 150, 200, 250, 300]
const HP_UPGRADE_COSTS := [50, 50, 50, 50, 50] # HP branch: flat 50 per bubble
const HP_PER_BUBBLE := 10                       # each HP bubble adds this to max HP (5 => +50)
var _weapon_dmg_tier := {} # weapon name -> damage tier (0..5)
var _weapon_rof_tier := {} # weapon name -> rate-of-fire tier (0..5)
var _hp_tier := 0          # HP-upgrade tier (0..5) — run-scoped, not per weapon
var _weapon_upgrades := {} # legacy (unused by the new tree; kept so old dead handlers still compile)
var _return_to_shop := false      # true while a crate spin was launched from the shop, so the
                                  # equip/keep result returns to the shop instead of closing
# Crate-spin tick state: while _crate_track is set, _process plays a tick each time a new card
# scrolls under the center marker (naturally slowing as the spin decelerates).
var _crate_track: Control = null
var _crate_stage: Control = null
var _crate_last_tick := -1
var _crate_tween: Tween = null   # the active spin tween — held to fast-forward it (see _input)
var _ff_label: Label = null      # transparent ⏩ watermark shown while fast-forwarding a spin
var _dash_pickup: Node2D = null  # the lobby Teleportation Bracelet pickup (freed on walk-over)

func _ready() -> void:
	GameManager.register_bullets_container(_bullets)
	_compute_shop_floors() # roll this run's banded shop floors
	_compute_bar_floors()   # ...then bar floors (avoid shop/boss floors)
	_compute_challenge_floors() # ...then challenge floors (avoid shop/bar/boss, never floor 1)
	GameManager.coins = 0 # run-scoped currency — start every run at zero
	# Active artifacts this run (capped at ItemRegistry.MAX_ARTIFACTS): none to start — artifacts are
	# only acquired DURING a run (bar slot machine adds/replaces up to the cap, boss relics).
	GameManager.run_artifacts.clear()
	_hud.refresh_artifact_icons() # clear the top-right artifact row for the new run
	# Teleportation Bracelet dash: locked until picked up in the lobby (see _spawn_dash_pickup).
	GameManager.dash_unlocked = false
	GameManager.dash_ready = true
	GameManager.dash_cooldown_frac = 1.0
	GameManager.final_boss_beaten = false # hedge-loss: assume the run is lost until the final boss falls
	GameManager.reset_run_stats() # fresh statistics for the new run (shown on the game-over screen)
	_weapon_upgrades.clear()
	GameManager.ui_popup_open = false # persistent autoload — never inherit a stale popup lock
	GameManager.refresh_shirt_effects() # Red character's doubled elemental effects
	GameManager.player_died.connect(_on_run_death) # resolve hedge-loss on death
	GameManager.deploy_equipment_requested.connect(_use_equipment)
	GameManager.heal_item_requested.connect(_use_heal_item)
	GameManager.battery_activate_requested.connect(_use_battery)
	_props = Node2D.new()
	add_child(_props)
	# The very first room is an empty "lobby" (number 0) with a single door — the actual first
	# combat room is the one the player walks into through it (see _go_through_door → number 1).
	# This has to happen BEFORE _spawn_player: room.gd defaults to the "combat" hallway in its own
	# _ready, so spawning first would read the hallway's centre as player_spawn_pos and strand the
	# player up in the Holding Bay's corridor once the room reconfigured under them.
	_rooms_entered = 0
	_rooms[Vector2i.ZERO] = _make_room(-1, 0)
	_refresh_doors()
	_set_combat_room_flag(_rooms[Vector2i.ZERO]) # lobby: combat_only artifacts stay dormant
	_spawn_player()
	_spawn_dash_pickup() # the Teleportation Bracelet, waiting in the lobby
	_apply_loadout()
	_update_camera(true) # snap to the player now that they exist (the _refresh_doors call had none)
	GameManager.current_floor = 0
	GameManager.floor_changed.emit(0)
	# Layered "Hatches" game music: starts on the lobby, floor tiers add stems (5/10/15), and dips to
	# add the low-HP layer under 25% HP. Muted automatically while the final-boss track plays.
	AudioManager.start_hatch_music(0)
	GameManager.floor_changed.connect(func(n): AudioManager.set_hatch_floor(n))
	GameManager.health_changed.connect(_on_hp_for_music)
	# Reward for not spending the full loadout budget: each unused point becomes starting gold
	# (animated on Start). Over-budget (blocked at the menu anyway) yields 0.
	_unused_points = maxi(0, ItemRegistry.EQUIPMENT_POINT_BUDGET - ItemRegistry.equipped_points())
	_loadout_bonus = _unused_points * GOLD_PER_UNUSED_POINT
	_hud.game_started.connect(_spawn_enemies_for_room)
	_hud.game_started.connect(_grant_loadout_bonus)
	if OS.has_feature("ios") or OS.has_feature("android") or OS.has_feature("editor"):
		add_child(preload("res://scenes/ui/mobile_controls.tscn").instantiate())

func _spawn_player() -> void:
	var p: CharacterBody2D = PLAYER_SCENE.instantiate()
	p.bullet_scene = BULLET_SCENE
	add_child(p)
	p.global_position = _room.player_spawn_pos
	_player = p
	_setup_camera()

# Camera at 1x zoom (the map/player sprites bake in the 2x, so world scale matches the pre-map
# game). Combat rooms are exactly screen-sized so it stays centred; bar rooms are 2x wide, so
# _update_camera scrolls it to follow the player, clamped to the map. HUD/joysticks are on
# CanvasLayers, unaffected.
const VIEW_W := 1040.0 # ~visible world size at 1x zoom (a combat room fills the screen)
const VIEW_H := 480.0
func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.position = Vector2(GameManager.room_w * 0.5, GameManager.room_h * 0.5)
	add_child(_camera)
	_camera.make_current()

# Keeps the camera centred in combat rooms and scrolling (clamped to the map) in bar rooms. `snap`
# jumps straight to the target (on room entry); otherwise it eases so scrolling feels smooth.
func _update_camera(snap: bool = false) -> void:
	if _camera == null:
		return
	var target: Vector2
	var rw: float = GameManager.room_w
	var rh: float = GameManager.room_h
	# Scroll to follow the player in any room larger than the view (bar, lobby); centre otherwise.
	if (rw > VIEW_W or rh > VIEW_H) and _player != null and is_instance_valid(_player):
		var hw := VIEW_W * 0.5
		var hh := VIEW_H * 0.5
		var px: float = clampf(_player.global_position.x, hw, rw - hw) if rw > VIEW_W else rw * 0.5
		var py: float = clampf(_player.global_position.y, hh, rh - hh) if rh > VIEW_H else rh * 0.5
		target = Vector2(px, py)
	else:
		target = Vector2(rw * 0.5, rh * 0.5)
	_camera.position = target if snap else _camera.position.lerp(target, 0.18)

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
	# Bonus max HP from the Health+ artifact AND any HP-upgrade bubbles bought at shops.
	_apply_hp_bonus()
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
	var wname: String = w.get("name", "")
	# Upgrade tree: damage tier multiplies damage, rof tier speeds fire rate (cumulative product).
	if w.get("damage") != null:
		w["damage"] = int(round(float(w["damage"]) * _upgrade_product(_weapon_dmg_tier.get(wname, 0))))
	if w.get("fire_rate") != null:
		w["fire_rate"] = float(w["fire_rate"]) / _upgrade_product(_weapon_rof_tier.get(wname, 0))
	# Run upgrades from the post-floor crates. Applied to EVERY weapon rather than per-weapon, so
	# they survive a fusion swapping the primary out.
	if w.get("damage") != null:
		w["damage"] = maxi(1, int(round(float(w["damage"]) * _run_dmg_mult)))
	if w.get("fire_rate") != null:
		w["fire_rate"] = float(w["fire_rate"]) / _run_rof_mult
	# Rarity-scaling relics: Common+ boosts common weapons, Uncommon+ boosts uncommon ones.
	if w.get("damage") != null:
		match str(w.get("rarity", "")):
			"common":   w["damage"] = int(round(float(w["damage"]) * ItemRegistry.artifact_num("common_dmg_mult", 1.0)))
			"uncommon": w["damage"] = int(round(float(w["damage"]) * ItemRegistry.artifact_num("uncommon_dmg_mult", 1.0)))
	# Knockback+ adds knockback to melee weapons, and a smaller amount to lasers.
	var add_kb := ItemRegistry.artifact_num("melee_knockback_add", 0.0) if w.get("melee_range") != null \
		else ItemRegistry.artifact_num("laser_knockback_add", 0.0)
	if add_kb > 0.0:
		var base_kb: float = float(w["knockback"]) if w.get("knockback") != null else 0.0
		w["knockback"] = base_kb + add_kb
	# Elemental+ artifact: elemental weapons deal more base damage.
	var element: String = str(w.get("element", ""))
	var is_elemental := element != ""
	if is_elemental and w.get("damage") != null:
		w["damage"] = int(round(float(w["damage"]) * ItemRegistry.artifact_num("elemental_dmg_mult", 1.0)))
	# Character (shirt colour) passive — a base-stat bonus tied to the chosen character.
	_apply_shirt_passive(w, is_elemental)
	ItemRegistry.equip_on_player(_player, w)

# Applies the selected character's (shirt colour's) passive to the equipped weapon's base damage /
# fire rate. Blue: +50% dmg to NON-elemental weapons. Green: +20% dmg & rate of fire to MELEE
# weapons. Yellow: +20% dmg & rate of fire to RANGED gun weapons. Red is handled elsewhere — it
# scales elemental EFFECTS, not weapon damage, so it has no entry here.
func _apply_shirt_passive(w: Dictionary, is_elemental: bool) -> void:
	var shirt: String = SaveManager.shirt_color
	var is_melee_w: bool = w.get("melee_range") != null or w.get("thrown_melee", false)
	var is_gun_w: bool = (not is_melee_w) and w.get("beam_range") == null # ranged projectile/launcher
	var dmg_mult := 1.0
	var rof_mult := 1.0 # >1 = faster (fire_rate is a cooldown, so we divide by it)
	if shirt == "blue" and not is_elemental:
		dmg_mult = 1.5
	# Red is NOT a damage multiplier — it doubles elemental EFFECT magnitude (burn/chain/thaw)
	# via GameManager.elemental_effect_mult, applied where each effect lands, not on the weapon.
	elif shirt == "green" and is_melee_w:
		dmg_mult = 1.2
		rof_mult = 1.2
	elif shirt == "yellow" and is_gun_w:
		dmg_mult = 1.2
		rof_mult = 1.2
	if w.get("damage") != null and dmg_mult != 1.0:
		w["damage"] = int(round(float(w["damage"]) * dmg_mult))
	if w.get("fire_rate") != null and rof_mult != 1.0:
		w["fire_rate"] = float(w["fire_rate"]) / rof_mult

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
const BASIC_TYPES := ["M", "L", "B", "S"]
const TIER2_TYPES := ["Void", "Warp", "Crater", "Clone", "Meteor"]
const TIER3_TYPES := ["Cryo", "Solar", "Nebula", "Nova"]
# Boss floors: only the boss spawns (no other enemies) — see _spawn_enemies_for_room.
const BOSS_BY_FLOOR := {15: "Boss1", 25: "Boss2"}
const BOSS2_KEY := "Boss2"
# Boss 2 keeps a stream of regular units coming so the arena is never just the boss. Two M/L
# units (basic melee / basic laser) every BOSS2_ADD_INTERVAL seconds, capped so a slow fight
# cannot bury the player under an unbounded crowd.
const BOSS2_ADD_INTERVAL := 5.0
const BOSS2_ADD_TYPES := ["M", "L"]
const BOSS2_ADD_PER_WAVE := 2
const BOSS2_ADD_MAX_ON_FLOOR := 10
const FINAL_BOSS_FLOOR := 35    # two-phase final boss + "I Got Soda" music (see _spawn_final_boss_*)
const BOSS_FLOORS := [15, 25, 35] # never place a shop on a boss floor
var _shop_floors := {}          # floor number -> true; rolled once per run in _ready
var _bar_floors := {}           # floor number -> true; rolled once per run (never a shop/boss floor)
var _challenge_floors := {}     # floor number -> true; ~one per decade — the room reached through the
                                # flashing red challenge door is scaled 10 floors deeper (never a
                                # shop/bar/boss floor, never floor 1)
const FINAL_BOSS_MAX_COUNT := 8 # phase-2 split cap so it can't runaway-multiply
const FINAL_BOSS_PHASE2_HP := 1500 # 3x the original 500
var _final_boss_phase := 0      # 0 = not fighting the final boss, 1/2 = which phase
var _loss_resolved := false     # hedge-loss resolved once per run (death or quit)

# ── Difficulty curve ─────────────────────────────────────────────────────────────────────────
# Tuned against 72 recorded runs rather than guesswork. Two measurements drove it:
#
#   1. Enemy toughness really does climb: damage-per-kill runs 24 on floors 1-14, 31 by 15-19,
#      36 by 20-24, 43 by 25-29 and 55 past 30, as tier-2 then tier-3 types take over the roster.
#   2. Player damage barely keeps up. Weapons under 20 DPS reached a MEDIAN floor of 23 while
#      20+ DPS weapons reached 20 — raw damage is not what ends runs, exposure is.
#
# Together those mean the player's kill rate PEAKS around floor 10 (~1.07/sec) and then falls to
# ~0.60/sec by floor 30. So the spawn interval can tighten through the mid-game but must ease off
# again deep, or spawns outrun kills and the room never stabilises. Keeping spawn rate under ~75%
# of kill rate at every floor is what holds that line.
# Solved so spawn rate reaches — but never exceeds — 90% of the player's kill rate. Beyond that
# the room stops converging: enemies arrive faster than they die and the fight runs away.
const ENEMY_COUNT_PER_FLOOR := 1.17
const ENEMY_COUNT_MAX       := 40
const ENEMY_IV_START        := 3.5
const ENEMY_IV_FLOOR        := 2.20 # tightest interval, reached at floor 20
const ENEMY_IV_TIGHTEN      := 0.068 # seconds shaved per floor on the way there
const ENEMY_IV_EASE_FROM    := 20   # past here the interval relaxes as enemies get tanky
const ENEMY_IV_EASE         := 0.018
const ENEMY_IV_MAX_LATE     := 2.45
# Group size per beat. A spawn brings one enemy by default, two at ENEMY_DOUBLE, or three at
# ENEMY_TRIPLE — which is checked first, so the two chances don't have to be kept disjoint by
# hand. Expected group size tops out at 1 + 0.42 + 2*0.16 = 1.74, and the interval above was
# lengthened to pay for that: without it the spawn rate crosses the kill rate around floor 20 and
# the room stops converging.
const ENEMY_DOUBLE_MAX      := 0.50
const ENEMY_DOUBLE_FROM     := 3
const ENEMY_DOUBLE_STEP     := 0.033
const ENEMY_TRIPLE_MAX      := 0.24
const ENEMY_TRIPLE_FROM     := 8
const ENEMY_TRIPLE_STEP     := 0.014

func _enemy_count_for_floor(n: int) -> int:
	return mini(2 + int(float(maxi(n, 1) - 1) * ENEMY_COUNT_PER_FLOOR), ENEMY_COUNT_MAX)

# Seconds between spawns on this floor.
func _enemy_spawn_interval(n: int) -> float:
	var f := maxi(n, 1)
	if f <= ENEMY_IV_EASE_FROM:
		return maxf(ENEMY_IV_FLOOR, ENEMY_IV_START - ENEMY_IV_TIGHTEN * float(f - 1))
	return minf(ENEMY_IV_MAX_LATE, ENEMY_IV_FLOOR + ENEMY_IV_EASE * float(f - ENEMY_IV_EASE_FROM))

# Chance any given spawn brings two enemies rather than one.
func _enemy_double_chance(n: int) -> float:
	return clampf(float(maxi(n, 1) - ENEMY_DOUBLE_FROM) * ENEMY_DOUBLE_STEP, 0.0, ENEMY_DOUBLE_MAX)

# Chance it brings three. Rolled before the double check, so this is its own slice rather than a
# subset of it.
func _enemy_triple_chance(n: int) -> float:
	return clampf(float(maxi(n, 1) - ENEMY_TRIPLE_FROM) * ENEMY_TRIPLE_STEP, 0.0, ENEMY_TRIPLE_MAX)

# Spawns this room's enemies. The count scales by floor (capped at 5), and difficulty scales by
# swapping basic M/L units for tougher tier-2/tier-3 types the deeper you go — the enemies
# themselves have fixed per-type stats (no per-floor stat inflation).
func _spawn_enemies_for_room() -> void:
	var st: Dictionary = _rooms[_current_pos]
	_room_had_fight = false
	# Non-combat rooms (the empty lobby, shops, bars) never spawn enemies — game_started is wired
	# here too, so this guard keeps the lobby empty when the player taps Start.
	if st.get("cleared", false):
		# Nothing to fight here, so nothing will ever call _on_enemy_died to clear the flag.
		# Leaving it set would block the NEXT room from registering as cleared at all.
		_clearing = false
		return
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
	# Normal rooms use the full floor ramp (2 up to 7). Challenge rooms are scaled 10 floors
	# deeper for both count and enemy type, and never drop below the 5 they used to spawn.
	var is_challenge: bool = st.get("challenge", false)
	var diff_n: int = n + 10 if is_challenge else n
	var base_count: int = maxi(5, _enemy_count_for_floor(diff_n)) if is_challenge else _enemy_count_for_floor(n)
	var count: int = mini(base_count, all_spawns.size())
	var spawns: Array = all_spawns.filter(func(p): return p.distance_to(entry_pos) >= DOOR_CLEARANCE)
	if spawns.size() >= count:
		spawns.shuffle()
	else:
		all_spawns.sort_custom(func(a, b): return a.distance_to(entry_pos) > b.distance_to(entry_pos))
		spawns = all_spawns

	# Which tougher types are available, and how many of the slots they take over (grows with
	# depth past floor 10, eventually replacing every basic unit). Challenge rooms use the deeper
	# scaled difficulty (diff_n) but never a boss type — just harder regular enemies.
	var hard_pool: Array = []
	if diff_n >= 20:
		hard_pool = TIER2_TYPES + TIER3_TYPES
	elif diff_n >= 10:
		hard_pool = TIER2_TYPES
	var hard: int = 0
	if not hard_pool.is_empty():
		hard = mini(count, 1 + int((diff_n - 10) / 3))

	var types: Array = []
	for i in range(count):
		if i < hard:
			types.append(hard_pool[randi() % hard_pool.size()])
		else:
			types.append(BASIC_TYPES[randi() % BASIC_TYPES.size()])
	types.shuffle()

	# _enemies_alive counts everything that WILL arrive, not just what's on the floor right now —
	# otherwise the room would read as cleared during the gap between waves.
	_enemies_alive = count
	_clearing = false
	_room_had_fight = true
	_schedule_enemy_waves(types, spawns, count, diff_n)

# Enemies teleport in over time rather than all at once. The room opens with SPAWN_OPENING_COUNT
# arriving together at SPAWN_FIRST_DELAY, then one more every SPAWN_WAVE_INTERVAL after that — so
# there's something to fight immediately, and the rest trickle in as pressure rather than a wall.
# Every spawn is telegraphed by a pulsing ring SPAWN_LEAD ahead of it, so the player always gets a
# beat of warning. Positions are reused once the list runs out — by the time a later enemy lands,
# whoever spawned there has moved off.
const SPAWN_FIRST_DELAY   := 1.5
const SPAWN_OPENING_COUNT := 2   # arrive together on the opening beat
const SPAWN_LEAD          := 1.0
const SPAWN_TELEGRAPH := preload("res://scenes/fx/spawn_telegraph.tscn")

func _schedule_enemy_waves(types: Array, spawns: Array, count: int, floor_n: int) -> void:
	if spawns.is_empty():
		return
	_spawn_token += 1 # invalidates anything still pending from the previous room
	var interval := _enemy_spawn_interval(floor_n)
	var double_chance := _enemy_double_chance(floor_n)
	var triple_chance := _enemy_triple_chance(floor_n)
	# Build the queue as a list of GROUPS rather than individual arrival times, so the pump below
	# can release a whole group at once and re-time whatever is left.
	_spawn_queue.clear()
	_boss2_add_timer = 0.0
	var i := 0
	var first := true
	while i < count:
		var group := 1
		if first:
			group = mini(SPAWN_OPENING_COUNT, count)
			first = false
		else:
			var roll := randf()
			if roll < triple_chance:
				group = 3
			elif roll < triple_chance + double_chance:
				group = 2
			group = mini(group, count - i)
		var batch: Array = []
		for k in range(group):
			batch.append([types[i + k], spawns[(i + k) % spawns.size()]])
		_spawn_queue.append(batch)
		i += group
	_spawn_interval = interval
	_spawn_timer = SPAWN_FIRST_DELAY
	_spawn_telegraphed = false

# Pump, called every physics frame. Normally releases the next group when the interval elapses;
# but if the floor is EMPTY and something is still queued it releases immediately, so a player who
# clears a wave faster than the timer never stands around waiting for the room to catch up.
func _tick_spawn_queue(delta: float) -> void:
	if _spawn_queue.is_empty():
		return
	var on_floor := _living_enemy_count()
	_spawn_timer -= delta
	# Empty floor: skip the remaining wait entirely (but still telegraph, so an enemy never just
	# materialises on top of the player).
	if on_floor == 0 and _spawn_timer > SPAWN_LEAD:
		_spawn_timer = SPAWN_LEAD
	# Telegraph SPAWN_LEAD before the group lands.
	if not _spawn_telegraphed and _spawn_timer <= SPAWN_LEAD:
		_spawn_telegraphed = true
		for entry in _spawn_queue[0]:
			_show_spawn_telegraph(_spawn_token, entry[1], maxf(_spawn_timer, 0.05))
	if _spawn_timer > 0.0:
		return
	var batch: Array = _spawn_queue.pop_front()
	for entry in batch:
		_spawn_one_enemy(_spawn_token, str(entry[0]), entry[1])
	_spawn_timer = _spawn_interval
	_spawn_telegraphed = false

# Enemies actually standing on the floor right now — NOT _enemies_alive, which also counts
# everything still queued to arrive.
func _living_enemy_count() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			n += 1
	return n

func _show_spawn_telegraph(token: int, pos: Vector2, lead: float) -> void:
	if token != _spawn_token or _enemies == null or not is_instance_valid(_enemies):
		return
	var fx: Node2D = SPAWN_TELEGRAPH.instantiate()
	_enemies.add_child(fx)
	fx.setup(pos, ENEMY_BODY_RADIUS, lead)

func _spawn_one_enemy(token: int, type_key: String, pos: Vector2) -> void:
	if token != _spawn_token or _enemies == null or not is_instance_valid(_enemies):
		return
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	e.configure_type(type_key)
	e.global_position = pos
	e.died.connect(_on_enemy_died)
	e.unit_split.connect(_on_unit_split) # Clone Unit halving
	_enemies.add_child(e)

# Spawns a single boss (Boss1/Boss2) in the centre of the play area — the whole floor's fight.
func _spawn_boss(type_key: String) -> void:
	_enemies_alive = 1
	_clearing = false
	_room_had_fight = true
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	e.configure_type(type_key)
	e.global_position = GameManager.play_rect.get_center()
	e.died.connect(_on_enemy_died)
	_enemies.add_child(e)
	# Boss 2 is accompanied by a steady trickle of regular units.
	_boss2_add_timer = BOSS2_ADD_INTERVAL if type_key == BOSS2_KEY else 0.0

var _boss2_add_timer := 0.0

# Two M/L units every BOSS2_ADD_INTERVAL while the second boss is alive. They are telegraphed
# like any other spawn and counted in _enemies_alive, so the room cannot clear while adds are
# still standing.
func _tick_boss2_adds(delta: float) -> void:
	if _boss2_add_timer <= 0.0:
		return
	_boss2_add_timer -= delta
	if _boss2_add_timer > 0.0:
		return
	_boss2_add_timer = BOSS2_ADD_INTERVAL
	if _living_enemy_count() >= BOSS2_ADD_MAX_ON_FLOOR:
		return # arena is already full; skip this wave rather than piling on
	var spots: Array = _room.enemy_spawn_positions
	if spots.is_empty():
		return
	for i in BOSS2_ADD_PER_WAVE:
		var pos: Vector2 = spots[randi() % spots.size()]
		var type_key: String = BOSS2_ADD_TYPES[randi() % BOSS2_ADD_TYPES.size()]
		_enemies_alive += 1
		_show_spawn_telegraph(_spawn_token, pos, SPAWN_LEAD)
		var token := _spawn_token
		get_tree().create_timer(SPAWN_LEAD).timeout.connect(
			func(): _spawn_one_enemy(token, type_key, pos))

# ── Final boss (floor 35) ───────────────────────────────────────────────────────────────────
# Phase 1: a lone 500-HP boss; the "I Got Soda" track fades in and loops its first section. On
# death the room does NOT clear — a Continue prompt appears, and choosing it starts phase 2: the
# boss respawns (music restarts at 4:20) and now splits in two every 10s. Clearing phase 2 clears
# the room normally and restores the background music.
func _spawn_final_boss_phase1() -> void:
	_final_boss_phase = 1
	_enemies_alive = 1
	_clearing = false
	_room_had_fight = true
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
	_room_had_fight = true
	AudioManager.start_boss_music_phase2()
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	e.configure_type("BossF")
	# Phase 2 at triple the old 500. The splits halve HP each time, so a bigger starting pool is
	# what keeps the later generations from being trivial: at 1500 the third halving still leaves
	# eight 187-HP bodies rather than eight 62-HP ones.
	e.max_health = FINAL_BOSS_PHASE2_HP
	e._gold = 0 # the 9999 payout is awarded once the whole phase-2 fight is won (see _on_enemy_died)
	e.enable_boss_split()
	e.global_position = GameManager.play_rect.get_center()
	e.died.connect(_on_enemy_died)
	e.boss_split.connect(_on_boss_split)
	_enemies.add_child(e)

# A phase-2 boss split in two: spawn its twin at half HP + half size, at the same halving depth.
func _on_boss_split(pos: Vector2, hp: int, radius: float, generation: int) -> void:
	# Count actual enemies, not _enemies' children — dropped coins are parented there too (see
	# enemy_basic.gd's _drop_coins), and loose gold on the floor must not stop the boss splitting.
	if get_tree().get_nodes_in_group("enemies").size() >= FINAL_BOSS_MAX_COUNT:
		return
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	e.configure_type("BossF")
	e._gold = 0 # only the original drops the payout
	e.max_health = hp # _ready() sets health = max_health
	e._radius = radius # matches the parent's halved size (_ready sizes the collider from _radius)
	e._split_generation = generation # inherits the halving depth so it stops after 3
	e.enable_boss_split()
	e.global_position = pos + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * 70.0
	e.died.connect(_on_enemy_died)
	e.boss_split.connect(_on_boss_split)
	_enemies.add_child(e)
	_enemies_alive += 1

# A Clone Unit hit half HP: spawn its twin alongside it at the same HP. _enemies_alive has to go
# up or the room would clear while the twin is still standing (same reason _on_boss_split does it).
# The twin can't split again — enemy_basic only ever emits this once per unit (_has_split).
const CLONE_SPLIT_OFFSET := 46.0
func _on_unit_split(type_key: String, pos: Vector2, hp: int) -> void:
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	e.configure_type(type_key)
	e.max_health = hp # _ready() sets health = max_health
	e._has_split = true
	e.global_position = pos + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * CLONE_SPLIT_OFFSET
	e.died.connect(_on_enemy_died)
	_enemies.add_child(e)
	_enemies_alive += 1

func _on_enemy_died() -> void:
	_enemies_alive -= 1
	if _enemies_alive <= 0 and not _clearing:
		if _final_boss_phase == 2:
			GameManager.add_coins(250) # final-boss payout, awarded once phase 2 is fully cleared
			GameManager.final_boss_beaten = true # loadout is now safe for the rest of the run
			SaveManager.grant_hedge_token() # reward: +1 hedge token for beating the final boss
		if _final_boss_phase != 0: # final boss defeated → back to normal music
			_final_boss_phase = 0
			AudioManager.stop_boss_music()
		_on_room_cleared()

# Restore the background track whenever the run is left (death → game over, or back to menu).
func _exit_tree() -> void:
	AudioManager.stop_boss_music()
	AudioManager.stop_hatch_music()
	_resolve_hedge_loss() # backup: also resolve a forfeit if the run is abandoned without dying

# Layers the low-HP music stem on/off as the player crosses 25% HP (kept in sync — see AudioManager).
func _on_hp_for_music(health: int, max_health: int) -> void:
	AudioManager.set_hatch_low_hp(max_health > 0 and float(health) / float(max_health) < 0.25)

# Hedge-loss: on a run that didn't beat the final boss, the equipped loadout is destroyed (minus any
# hedged slots). Runs once per run (death or quit); a beaten run is exempt.
var _run_recorded := false
func _on_run_death() -> void:
	if not _run_recorded:
		_run_recorded = true
		_record_run() # capture stats + loadout BEFORE hedge-loss wipes the equipped items
	_resolve_hedge_loss()

# Appends this run to the persistent history (SaveManager.run_history) for the Statistics screen.
func _record_run() -> void:
	var w: Dictionary = SaveManager.equipped_weapon
	var arts: Array = []
	for a in GameManager.run_artifacts:
		arts.append(a.get("name", ""))
	SaveManager.record_run({
		"date": Time.get_datetime_string_from_system(false, true),
		"won": GameManager.final_boss_beaten,
		"floor_died": GameManager.current_floor,
		"floors_cleared": GameManager.stat_floors_cleared,
		"weapon": w.get("name", "(none)"),
		"weapon_rarity": w.get("rarity", ""),
		"equipment": SaveManager.equipped_equipment.get("name", ""),
		"defensive": SaveManager.equipped_defensive.get("name", ""),
		"artifacts": arts,
		"damage_dealt": GameManager.stat_total_damage,
		"damage_taken": GameManager.stat_damage_taken,
		"enemies_slain": GameManager.stat_enemies_slain,
		"gold_earned": GameManager.stat_gold_earned,
		"gold_spent": GameManager.stat_gold_spent,
		"shots_fired": GameManager.stat_shots_fired,
		"shots_hit": GameManager.stat_shots_hit,
		"melee_attempts": GameManager.stat_melee_attempts,
		"melee_hits": GameManager.stat_melee_hits,
	})

func _resolve_hedge_loss() -> void:
	if _loss_resolved or GameManager.final_boss_beaten:
		return
	_loss_resolved = true
	# A secondary weapon that was never fused is handed back rather than destroyed — carrying one
	# costs equipment points, but only spending it costs the weapon itself.
	var keep: Array = []
	if not _fused_this_run and SaveManager.secondary_pool_full():
		keep.append("secondary_pool")
	SaveManager.resolve_run_loss(keep)

# Places the shop-keeper NPC in the middle of a shop room. Room-scoped (added to _props so it's
# freed on the next transition). The shop dialog opens when the player walks up to it — see the
# proximity check in _physics_process.
# Places the Teleportation Bracelet pickup in the lobby, just ahead of the player toward the door.
func _spawn_dash_pickup() -> void:
	var p: Node2D = DASH_PICKUP_SCENE.instantiate()
	# In the Holding Bay it sits on the blue console in the middle of the floor — on the way from
	# either holding cell to the corridor, so it's picked up naturally on the way out.
	if _room_kind == "start":
		p.global_position = _room.LOBBY_CONSOLE
	else:
		p.global_position = _room.player_spawn_pos + Vector2(150.0, 0.0)
	_props.add_child(p)
	_dash_pickup = p

func _spawn_shop_npc() -> void:
	var npc: Node2D = SHOP_NPC_SCENE.instantiate()
	npc.global_position = GameManager.play_rect.get_center() # corridor centre
	_props.add_child(npc)
	_shop_npc = npc
	_shop_npc_active = false

# Bar room: a bartender behind the central counter plus a few ambient patrons scattered across the
# wide floor. All room-scoped (added to _props, freed on the next transition).
func _spawn_bar() -> void:
	var r: Rect2 = GameManager.play_rect
	var bartender: Node2D = BARTENDER_SCENE.instantiate()
	bartender.global_position = _room.BAR_COUNTER # inside the oval counter ring, as drawn
	_props.add_child(bartender)
	_bartender = bartender
	_bartender_active = false
	# The artifact terminal is the blue screen painted into the art (top-left), so there's no prop
	# to spawn — just the position the proximity check uses. (The old slot-machine prop is gone.)
	_bar_screen_pos = _room.BAR_SCREEN
	_terminal_active = false
	# Fusion table, set beside the counter ring on the right so it is passed on the way in but
	# never blocks the bartender.
	var table: Node2D = FUSION_TABLE_SCENE.instantiate()
	table.global_position = _room.BAR_COUNTER + Vector2(BAR_TABLE_OFFSET, 36.0)
	_props.add_child(table)
	_fusion_table = table
	_fusion_table_active = false
	table.set_available(not _fused_this_run or _boost_slots_free() > 0)
	# Scatter patrons at random spots on the floor, keeping clear of the counter ring, the screen,
	# and each other so nobody spawns standing inside the bartender.
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < BAR_PATRON_COUNT and tries < 200:
		tries += 1
		var p := Vector2(randf_range(r.position.x + 45.0, r.end.x - 45.0), randf_range(r.position.y + 45.0, r.end.y - 45.0))
		if p.distance_to(_room.BAR_COUNTER) < BAR_COUNTER_CLEARANCE:
			continue
		if p.distance_to(_room.BAR_SCREEN) < BAR_SCREEN_CLEARANCE:
			continue
		if p.distance_to(_room.BAR_COUNTER + Vector2(BAR_TABLE_OFFSET, 36.0)) < 70.0:
			continue # don't stand inside the fusion table
		var clash := false
		for q in placed:
			if p.distance_to(q) < BAR_PATRON_SPACING:
				clash = true
				break
		if clash:
			continue
		placed.append(p)
		var patron: Node2D = BAR_PATRON_SCENE.instantiate()
		patron.global_position = p
		_props.add_child(patron)

# Bar drink dialog: three coin-for-HP options (see BAR_DRINKS), rebuilt after each purchase so the
# balance/enabled states refresh, until the player Leaves.
func _show_bar() -> void:
	if _reward_popup != null and is_instance_valid(_reward_popup):
		_reward_popup.queue_free()
		_reward_popup = null
	GameManager.ui_popup_open = true
	_reward_popup = _build_popup_shell()
	var vbox: VBoxContainer = _reward_popup.get_meta("vbox")

	var title := Label.new()
	title.text = "🍸  Cantina"
	title.add_theme_font_size_override("font_size", 19)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var npc := Label.new()
	npc.text = "Care for a drink, traveller?"
	npc.add_theme_font_size_override("font_size", 14)
	npc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	npc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(npc)

	var coins_lbl := Label.new()
	coins_lbl.text = "🪙 %d credits" % GameManager.coins
	coins_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2))
	coins_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(coins_lbl)

	var full: bool = _player != null and is_instance_valid(_player) and _player.health >= _player.max_health
	for drink in BAR_DRINKS:
		var cost: int = drink[0]
		var hp: int = drink[1]
		var btn := Button.new()
		var free_left := _free_drinks_left()
		btn.text = "🍺  Restore %d HP — FREE (%d left)" % [hp, free_left] if free_left > 0 \
			else "🍺  Restore %d HP — %d🪙" % [hp, cost]
		btn.custom_minimum_size = Vector2(0, 46)
		btn.disabled = full or (free_left <= 0 and GameManager.coins < cost)
		btn.pressed.connect(_buy_drink.bind(cost, hp))
		vbox.add_child(btn)

	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.custom_minimum_size = Vector2(0, 44)
	leave_btn.pressed.connect(_close_reward_popup)
	vbox.add_child(leave_btn)

# Bar Pass+ artifact: the first few drinks of the run are on the house. Run-scoped (world.gd is
# rebuilt per run), and counted rather than per-bar, so it's N drinks total however many bars
# the player visits.
var _free_drinks_used := 0
func _free_drinks_left() -> int:
	return maxi(0, int(ItemRegistry.artifact_num("free_bar_drinks", 0.0)) - _free_drinks_used)

func _buy_drink(cost: int, hp: int) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var on_the_house := _free_drinks_left() > 0
	if not on_the_house and GameManager.coins < cost:
		return
	if on_the_house:
		_free_drinks_used += 1
	else:
		GameManager.spend_coins(cost)
	_player.heal(hp)
	_show_bar() # refresh balance/enabled states

# Artifact terminal (the blue screen in the bar art). One payment of TERMINAL_COST rolls
# TERMINAL_CHOICES artifacts at the normal rarity odds; the player then picks whichever they want
# rather than being handed a random one. Tapping an offer selects it and reveals its description;
# a second button actually takes it. The offer persists until taken or the player leaves.
func _show_terminal() -> void:
	if _reward_popup != null and is_instance_valid(_reward_popup):
		_reward_popup.queue_free()
		_reward_popup = null
	GameManager.ui_popup_open = true
	_reward_popup = _build_popup_shell()
	var vbox: VBoxContainer = _reward_popup.get_meta("vbox")

	var title := Label.new()
	title.text = "🖥️  Artifact Terminal"
	title.add_theme_font_size_override("font_size", 19)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var coins_lbl := Label.new()
	coins_lbl.text = "🪙 %d credits" % GameManager.coins
	coins_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2))
	coins_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(coins_lbl)

	if _terminal_offer.is_empty():
		# Nothing on offer yet — pay to have the terminal roll a set.
		var blurb := Label.new()
		blurb.text = "Scan for artifacts and choose one of %d." % TERMINAL_CHOICES
		blurb.add_theme_font_size_override("font_size", 13)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(blurb)

		var scan := Button.new()
		scan.text = "Scan — %d🪙" % TERMINAL_COST
		scan.custom_minimum_size = Vector2(0, 48)
		scan.disabled = GameManager.coins < TERMINAL_COST
		scan.pressed.connect(_buy_terminal_scan)
		vbox.add_child(scan)
	else:
		for i in range(_terminal_offer.size()):
			var a: Dictionary = _terminal_offer[i]
			var btn := Button.new()
			var mark := "▸ " if i == _terminal_selected else ""
			btn.text = "%s%s  (%s)" % [mark, a.get("name", ""), str(a.get("rarity", "")).capitalize()]
			btn.custom_minimum_size = Vector2(0, 44)
			btn.add_theme_color_override("font_color", _rarity_text_color(a.get("rarity", "")))
			btn.pressed.connect(_select_terminal_offer.bind(i))
			vbox.add_child(btn)
		if _terminal_selected >= 0 and _terminal_selected < _terminal_offer.size():
			var sel: Dictionary = _terminal_offer[_terminal_selected]
			var desc := Label.new()
			desc.text = str(sel.get("effect", ""))
			desc.add_theme_font_size_override("font_size", 13)
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(desc)

			var take := Button.new()
			take.text = "Take %s" % sel.get("name", "")
			take.custom_minimum_size = Vector2(0, 48)
			take.pressed.connect(_take_terminal_offer)
			vbox.add_child(take)

	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.custom_minimum_size = Vector2(0, 44)
	leave_btn.pressed.connect(_close_reward_popup)
	vbox.add_child(leave_btn)

# Pays for a scan and rolls the offer. Duplicates are re-rolled a few times so the three choices
# are usually distinct, but the per-artifact odds are still ItemRegistry.roll_artifact's.
func _buy_terminal_scan() -> void:
	if GameManager.coins < TERMINAL_COST or not _terminal_offer.is_empty():
		return
	GameManager.spend_coins(TERMINAL_COST)
	var offer: Array = []
	var guard := 0 # caps the re-roll loop so a small artifact pool can't spin forever
	while offer.size() < TERMINAL_CHOICES and guard < 60:
		guard += 1
		var a: Dictionary = ItemRegistry.roll_artifact()
		var dup := false
		for o in offer:
			if o.get("name", "") == a.get("name", ""):
				dup = true
				break
		if not dup:
			offer.append(a)
	_terminal_offer = offer
	_terminal_selected = -1
	_show_terminal()

func _select_terminal_offer(index: int) -> void:
	_terminal_selected = index
	_show_terminal() # rebuild so the description and Take button appear

func _take_terminal_offer() -> void:
	if _terminal_selected < 0 or _terminal_selected >= _terminal_offer.size():
		return
	var chosen: Dictionary = _terminal_offer[_terminal_selected]
	_terminal_offer = []
	_terminal_selected = -1
	_award_reopen = true # returns to the terminal so the player can scan again
	_award_artifact(chosen)

const RARITY_TEXT := {
	"common": Color(0.70, 0.70, 0.75), "uncommon": Color(0.35, 0.90, 0.45),
	"rare": Color(0.30, 0.55, 1.00), "epic": Color(0.80, 0.40, 1.00), "legendary": Color(1.00, 0.80, 0.10),
}
func _rarity_text_color(rarity: String) -> Color:
	return RARITY_TEXT.get(rarity, Color(1, 1, 1))

# Awards a rolled artifact/relic: stacks it (up to ItemRegistry.MAX_ARTIFACTS) or opens the replace
# dialog if at the cap. _award_reopen decides whether to return to the slot machine afterward (true
# for a bar spin) or just close the popup (false for a boss relic).
var _award_reopen := true
func _award_artifact(artifact: Dictionary) -> void:
	if GameManager.run_artifacts.size() >= ItemRegistry.MAX_ARTIFACTS:
		_show_artifact_replace(artifact)
		return
	GameManager.run_artifacts.append(artifact)
	_apply_active_artifacts()
	if _award_reopen:
		_show_terminal() # back to the terminal, ready to scan again
	else:
		_close_reward_popup()

# Re-applies the effects that are baked in at equip time (weapon damage/fire-rate/knockback, bonus
# max HP) after the active-artifact set changes. The rest (regen, shop cost, invincibility,
# lifesteal) are read live at their use sites, so they need no refresh.
func _apply_active_artifacts() -> void:
	_reequip_weapon()
	_apply_hp_bonus()
	_hud.refresh_artifact_icons() # keep the top-right artifact row in sync with run_artifacts

# At the artifact cap: pick which current artifact the freshly-won one replaces, or discard it.
func _show_artifact_replace(new_artifact: Dictionary) -> void:
	if _reward_popup != null and is_instance_valid(_reward_popup):
		_reward_popup.queue_free()
		_reward_popup = null
	GameManager.ui_popup_open = true
	_reward_popup = _build_popup_shell()
	var vbox: VBoxContainer = _reward_popup.get_meta("vbox")

	var title := Label.new()
	title.text = "🏺  You won: %s" % new_artifact.get("name", "")
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", _rarity_text_color(new_artifact.get("rarity", "")))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var msg := Label.new()
	msg.text = "Artifacts are full (%d). Replace one?" % ItemRegistry.MAX_ARTIFACTS
	msg.add_theme_font_size_override("font_size", 13)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(msg)

	for i in range(GameManager.run_artifacts.size()):
		var cur: Dictionary = GameManager.run_artifacts[i]
		var btn := Button.new()
		btn.text = "Replace: %s" % cur.get("name", "")
		btn.custom_minimum_size = Vector2(0, 44)
		btn.add_theme_color_override("font_color", _rarity_text_color(cur.get("rarity", "")))
		btn.pressed.connect(_replace_artifact.bind(i, new_artifact))
		vbox.add_child(btn)

	var discard := Button.new()
	discard.text = "Discard new artifact"
	discard.custom_minimum_size = Vector2(0, 44)
	discard.pressed.connect(func(): _show_terminal() if _award_reopen else _close_reward_popup())
	vbox.add_child(discard)

func _replace_artifact(index: int, new_artifact: Dictionary) -> void:
	if index >= 0 and index < GameManager.run_artifacts.size():
		GameManager.run_artifacts[index] = new_artifact
		_apply_active_artifacts()
	if _award_reopen:
		_show_terminal()
	else:
		_close_reward_popup()

# Room cleared: the doors (rolled at creation, red until now) unlock in place — entry turns
# blue, exits green. (Shop rooms have no enemies, so they never reach here — they're marked
# cleared on creation and the shop is opened by walking up to the keeper instead.)
func _on_room_cleared() -> void:
	_clearing = true
	# Read this BEFORE _refresh_doors below: that call also runs on plain room entry, and an
	# earlier version reset the flag there — which wiped it mid-clear and silently skipped every
	# reward crate. Capture first, decide later.
	var had_fight := _room_had_fight
	var st: Dictionary = _rooms[_current_pos]
	st["cleared"] = true
	_refresh_doors()
	_maybe_offer_challenge(st) # if the next floor is a challenge floor, flash one exit red
	_rooms_cleared += 1
	GameManager.record_floor_cleared()
	GameManager.room_cleared.emit()
	# Reward crate for a cleared fight. Keyed off whether this room actually spawned enemies, NOT
	# off st["kind"] — kind is the LAYOUT (combat/cockpit/control/docking), so matching on
	# "combat" alone silently skipped the crate on three of the four fighting layouts.
	if had_fight:
		_spawn_upgrade_crate()
		_refresh_doors() # re-lock: the room is not finished until the crate is resolved
	# Defeating a boss grants a boss relic — pick 1 of 2.
	if st.get("kind", "combat") == "boss":
		_offer_boss_relics()

# When a combat room is cleared, if the next floor is a rolled challenge floor, pick one of this
# room's forward exits to be the flashing red challenge door. Taking it makes that next room a
# challenge (6 enemies scaled 10 floors deeper); the other doors stay a normal combat floor.
func _maybe_offer_challenge(st: Dictionary) -> void:
	if st.get("kind", "combat") != "combat" or st.get("challenge", false):
		return
	if st.get("challenge_door", -1) != -1:
		return # already decided (e.g. this room was cleared before)
	var next_num: int = _rooms_entered + 1
	if not _challenge_floors.has(next_num) or _kind_for_number(next_num) != "combat":
		return # once-per-decade cadence, and never in place of a shop/bar/boss floor
	var candidates: Array = []
	for side in st["doors"]:
		if side != _current_entry_side: # a forward exit, not the way back
			candidates.append(side)
	if candidates.is_empty():
		return
	var side: int = candidates[randi() % candidates.size()]
	st["challenge_door"] = side
	_room.set_challenge_door(side)

# On a boss kill: offer two random boss relics; the player picks one (replacing a held artifact if
# already at the cap). Boss relics never come from the slot machine.
func _offer_boss_relics() -> void:
	var choices := ItemRegistry.roll_two_boss_relics()
	if choices.is_empty():
		return
	if _reward_popup != null and is_instance_valid(_reward_popup):
		_reward_popup.queue_free()
	GameManager.ui_popup_open = true
	_reward_popup = _build_popup_shell()
	var vbox: VBoxContainer = _reward_popup.get_meta("vbox")
	var title := Label.new()
	title.text = "🏆  Boss Relic"
	title.add_theme_font_size_override("font_size", 19)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var msg := Label.new()
	msg.text = "Choose one to claim:"
	msg.add_theme_font_size_override("font_size", 13)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(msg)
	for relic in choices:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 58)
		btn.text = "%s\n%s" % [relic.get("name", ""), relic.get("effect", "")]
		btn.add_theme_font_size_override("font_size", 12)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_color_override("font_color", _rarity_text_color(relic.get("rarity", "")))
		btn.pressed.connect(_claim_boss_relic.bind(relic))
		vbox.add_child(btn)

func _claim_boss_relic(relic: Dictionary) -> void:
	# Reuses the artifact add/replace flow (stacks up to the cap, or opens the replace dialog); a
	# relic just closes the popup afterward rather than returning to a slot machine.
	_award_reopen = false
	_close_reward_popup()
	_award_artifact(relic)

# A shop room if this floor was rolled as one (banded 8-10 apart — see _compute_shop_floors).
func _is_shop_room(number: int) -> bool:
	return _shop_floors.has(number)

# Rolls this run's shop floors: the Nth shop somewhere in [7N..9N], skipping boss floors.
# Shop floors were removed: those floors are now ordinary combat floors, and everything the shop
# used to sell lives in the bar instead (the fusion table) or in the post-clear upgrade crate.
# The roller stays — always empty — because the bar and challenge rollers both read _shop_floors
# to avoid collisions, and an empty set keeps that logic correct without special-casing it.
func _compute_shop_floors() -> void:
	_shop_floors.clear()

func _is_bar_room(number: int) -> bool:
	return _bar_floors.has(number)

# Rolls this run's bar floors: the Nth bar somewhere in [8N..9N], skipping boss AND shop floors
# (compute after _compute_shop_floors so the shop floors are known).
func _compute_bar_floors() -> void:
	_bar_floors.clear()
	for n in range(1, 30):
		var lo: int = BAR_BAND_MIN * n
		var hi: int = BAR_BAND_MAX * n
		var f: int = randi_range(lo, hi)
		var tries := 0
		while (f in BOSS_FLOORS or _shop_floors.has(f)) and tries < 16:
			f = randi_range(lo, hi)
			tries += 1
		if not (f in BOSS_FLOORS) and not _shop_floors.has(f):
			_bar_floors[f] = true

# Rolls this run's challenge floors: roughly one per decade (band k covers floors up to 10k), never
# floor 1 and never a shop/bar/boss floor — the challenge always lands on a would-be combat floor.
func _compute_challenge_floors() -> void:
	_challenge_floors.clear()
	for k in range(1, 12):
		var lo: int = maxi(2, 10 * k - 8)
		var hi: int = 10 * k
		var f: int = randi_range(lo, hi)
		var tries := 0
		while (f in BOSS_FLOORS or _shop_floors.has(f) or _bar_floors.has(f)) and tries < 20:
			f = randi_range(lo, hi)
			tries += 1
		if f >= 2 and not (f in BOSS_FLOORS) and not _shop_floors.has(f) and not _bar_floors.has(f):
			_challenge_floors[f] = true

# The kind of a room by its floor number: boss / shop / bar / combat (start room is number 0).
func _kind_for_number(number: int) -> String:
	if number == 0:
		return "start"
	if number in BOSS_FLOORS:
		return "boss"
	if _is_shop_room(number):
		return "shop"
	if _is_bar_room(number):
		return "bar"
	return "combat"

# Picks a Hallway variant whose baked-in doors include the entry side (any variant for the starting
# room, entry_side -1), so the loaded art always has a door where the player came from. Returns the
# variant dict {tex, doors}.
func _pick_variant(entry_side: int) -> Dictionary:
	var candidates: Array = []
	for v in HALLWAY_VARIANTS:
		if entry_side == -1 or entry_side in v["doors"]:
			candidates.append(v)
	return candidates[randi() % candidates.size()]

# A hallway variant that has a door on `side` (for the 1-door start room).
func _pick_variant_with(side: int) -> Dictionary:
	var candidates: Array = []
	for v in HALLWAY_VARIANTS:
		if side in v["doors"]:
			candidates.append(v)
	return candidates[randi() % candidates.size()] if not candidates.is_empty() else HALLWAY_VARIANTS[0]

# Builds a room state for the given entry side + floor number. Combat/boss rooms are uncleared (need
# a fight); start/shop/bar rooms are cleared (no enemies). Doors: combat uses a matching hallway
# variant's door set; the start room has a single door; bar rooms have left/right (+ the entry) doors.
func _make_room(entry_side: int, number: int) -> Dictionary:
	var kind := _kind_for_number(number)
	var cleared := kind == "start" or kind == "shop" or kind == "bar"
	var variant := ""
	var doors: Array = []
	# Side indices match room.gd's SIDE_* (0=top,1=bottom,2=left,3=right).
	if kind == "bar":
		doors = [2, 3] # left + right doors on the wide bar
		if entry_side != -1 and not doors.has(entry_side):
			doors.append(entry_side) # plus the way back, wherever the player came in
	elif kind == "start":
		doors = [0] # single door on top (side 0) — the Holding Bay art has one door, at the top
	elif kind == "boss" and BOSS_BY_FLOOR.get(number, "") == BOSS2_KEY:
		# The second boss fights on the bridge — the cockpit layout. It has no right-hand door
		# (that edge is the windscreen), so if the player arrives from the right the room falls
		# back to a hallway rather than sealing them outside the map.
		if entry_side == 3:
			var bv := _pick_variant_with(3)
			variant = bv["tex"]
			doors = bv["doors"].duplicate()
		else:
			kind = "cockpit"
			doors = [0, 1, 2]
	elif kind == "combat":
		# Pick evenly among the layouts that have a door where the player came in. These are
		# different sizes/shapes, so each is a room KIND (room.gd::configure) rather than another
		# entry in HALLWAY_VARIANTS.
		var eligible: Array = []
		for l in COMBAT_LAYOUTS:
			if entry_side == -1 or entry_side in l["doors"]:
				eligible.append(l)
		var pick: Dictionary = eligible[randi() % eligible.size()] if not eligible.is_empty() else COMBAT_LAYOUTS[0]
		if pick["kind"] == "hallway":
			var v := _pick_variant(entry_side)
			variant = v["tex"]
			doors = v["doors"].duplicate()
		else:
			kind = pick["kind"]
			doors = pick["doors"].duplicate()
	else:
		var v2 := _pick_variant(entry_side)
		variant = v2["tex"]
		doors = v2["doors"].duplicate()
	return {"cleared": cleared, "doors": doors, "entry_side": entry_side, "number": number, "variant": variant, "kind": kind, "challenge": false, "challenge_door": -1}

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
	_room_kind = st.get("kind", "combat")
	_room.configure(_room_kind) # sets size, walls, bounds, and (for bar) the scrolling layout
	if st["variant"] != "":
		_room.set_map_texture(st["variant"]) # load the art whose doors match this room
		                                     # (bar/lobby/control have no variant — they own their art)
	# A pending reward crate keeps the doors shut — the room is not finished until it is resolved.
	_room.set_doors(_current_entry_side, st["doors"], (not st["cleared"]) or _crate_pending)
	var cd: int = st.get("challenge_door", -1)
	if cd != -1 and st.get("cleared", false):
		_room.set_challenge_door(cd) # keep the flashing red door showing when re-entering a cleared room
	_update_camera(true) # snap the camera to the new room immediately

# Door polling: walls stay physically solid behind the drawn gaps, so transitions trigger off
# the player overlapping a door's zone (which reaches slightly into the room) rather than
# actually passing through the wall.
func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or GameManager.ui_popup_open:
		return
	_update_camera() # scroll to follow the player in bar rooms (no-op/centred otherwise)
	_tick_fire_trail(_delta) # Fire Trail+ artifact
	_tick_wave_pulse(_delta) # Wave Pulse+ artifact
	# Teleportation Bracelet pickup (lobby): walk over it to unlock the dash for the run.
	if _dash_pickup != null and is_instance_valid(_dash_pickup):
		if _player.global_position.distance_to(_dash_pickup.global_position) <= 40.0:
			GameManager.dash_unlocked = true
			_dash_pickup.queue_free()
			_dash_pickup = null
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
	# Bartender: open the drink dialog when the player walks up (same debounce as the shop).
	if _bartender != null and is_instance_valid(_bartender):
		var near_bar := _player.global_position.distance_to(_bartender.global_position) <= BAR_TALK_RANGE
		if near_bar and not _bartender_active:
			_bartender_active = true
			_show_bar()
			return
		elif not near_bar:
			_bartender_active = false
	_tick_spawn_queue(_delta) # release the next enemy group (early if the floor is empty)
	_tick_boss2_adds(_delta) # boss 2: two M/L units every 5s
	_tick_upgrade_crate() # Open prompt for the post-floor reward crate
	# Fusion table: the console beside the counter. Everything the shop used to offer for weapons
	# — fusing and elemental boosts — now lives here.
	if _fusion_table != null and is_instance_valid(_fusion_table):
		var near_table := _player.global_position.distance_to(_fusion_table.global_position) <= BAR_TALK_RANGE
		if near_table and not _fusion_table_active:
			_fusion_table_active = true
			_show_fusion_table()
			return
		elif not near_table:
			_fusion_table_active = false
	# Artifact terminal: open its dialog when the player walks up to the screen in the bar art.
	if _bar_screen_pos != Vector2.ZERO:
		var near_screen := _player.global_position.distance_to(_bar_screen_pos) <= BAR_TALK_RANGE
		if near_screen and not _terminal_active:
			_terminal_active = true
			_show_terminal()
			return
		elif not near_screen:
			_terminal_active = false
	if GameManager.ui_popup_open:
		return
	for side in _active_door_sides():
		if _room.door_zone(side).has_point(_player.global_position):
			_go_through_door(side)
			return

# Crate-spin ticker: while the reward crate is spinning, play a tick each time a new card
# crosses the center marker. idx grows as the track scrolls left; it slows with the tween's
# cubic ease-out, so the ticks space out toward the end for the classic case-opening feel.
const SHAKE_MAX_OFFSET := 9.0 # px — minor, quick jolt that keeps the screen readable
const SHAKE_DECAY := 4.5       # trauma units per second
func _process(delta: float) -> void:
	_update_camera_shake(delta)
	_process_fusion_spin(delta) # decelerating icon swap on the fusion hologram
	if _crate_track == null or not is_instance_valid(_crate_track):
		return
	var slot := float(CRATE_CARD_W + CRATE_CARD_GAP)
	var idx := int((_crate_stage.size.x * 0.5 - _crate_track.position.x) / slot)
	if idx != _crate_last_tick:
		_crate_last_tick = idx
		AudioManager.play_tick()

# Turns GameManager.screen_shake trauma into a quick random camera offset (separate from the
# camera's position so it never fights the follow/clamp), decaying back to zero.
func _update_camera_shake(delta: float) -> void:
	if _camera == null:
		return
	if GameManager.screen_shake <= 0.0:
		if _camera.offset != Vector2.ZERO:
			_camera.offset = Vector2.ZERO
		return
	var s := GameManager.screen_shake * GameManager.screen_shake # ease so small trauma is subtle
	_camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * s * SHAKE_MAX_OFFSET
	GameManager.screen_shake = maxf(GameManager.screen_shake - SHAKE_DECAY * delta, 0.0)

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
	_room_had_fight = false # recomputed by _spawn_enemies_for_room if the new room fights
	# Finalize any in-progress barrier placement before its node is freed with the props,
	# otherwise the green button would be stuck in the PLACING state with nothing to finish.
	if _active_barrier != null and is_instance_valid(_active_barrier):
		_active_barrier.stop_and_finalize()
	# Stash any gold still lying on the floor into THIS room's state before the container is
	# cleared (_current_pos is still the room being left — it only moves further down). Walking
	# back in re-drops it, so leaving a room by accident never costs the player their gold.
	_stash_dropped_coins()
	for c in _props.get_children():
		c.queue_free()
	for c in _enemies.get_children():
		c.queue_free()
	_placed_mine = null
	_shop_npc = null
	_shop_npc_active = false
	_bartender = null
	_bartender_active = false
	_bar_screen_pos = Vector2.ZERO
	_fusion_table = null
	_fusion_table_active = false
	_spawn_queue.clear()
	_upgrade_crate = null
	_crate_prompt_active = false
	_crate_pending = false
	_close_crate_prompt()
	_terminal_active = false
	_terminal_offer = []
	_terminal_selected = -1
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

	# Did the player leave through this room's flashing red challenge door? (Read before moving.)
	var took_challenge: bool = _rooms[_current_pos].get("challenge_door", -1) == side
	_current_pos += SIDE_OFFSETS[side]
	var entry := _opposite(side)
	_current_entry_side = entry
	if not _rooms.has(_current_pos):
		_rooms_entered += 1
		# Shop/bar rooms carry no fight, so they start "cleared" — doors open immediately.
		var new_room := _make_room(entry, _rooms_entered)
		# A combat room reached through the challenge door becomes a challenge (6 tougher enemies).
		if took_challenge and new_room.get("kind", "") == "combat":
			new_room["challenge"] = true
		_rooms[_current_pos] = new_room
		if _rooms[_current_pos]["cleared"]:
			GameManager.record_floor_cleared() # non-combat floors count as cleared for run stats
	var st: Dictionary = _rooms[_current_pos]
	GameManager.current_floor = st["number"]
	GameManager.floor_changed.emit(st["number"])
	_refresh_doors() # reconfigure the room (size/walls/bounds) FIRST so entry_position uses the new room
	_player.global_position = _room.entry_position(entry)
	_update_camera(true) # re-snap now that the player is placed in the resized room
	_set_combat_room_flag(st)   # drives the combat_only artifact gate (Fire Trail+, Wave Pulse+)
	_grant_room_invincibility() # Invincible+ artifact — every room entry
	_restore_dropped_coins()    # gold left behind last time the player was in this room
	match st.get("kind", "combat"):
		"shop": _spawn_shop_npc()
		"bar":  _spawn_bar()
		_:
			if not st["cleared"]:
				_spawn_enemies_for_room()

# ── Uncollected gold when backtracking ──────────────────────────────────────────────────────
# Coins are dropped as siblings of the enemy that died (enemy_basic.gd's _drop_coins), so they sit
# in _enemies and are freed on the way out — losing any gold the player hadn't walked over yet.
# The drop from the room just left is held here and re-created if the player turns straight back
# around, so stepping through a door by accident costs nothing. Only the PREVIOUS room is kept:
# walking on to a third room discards it, so gold can't be banked indefinitely.
const NO_ROOM := Vector2i(9999, 9999) # sentinel — never a real grid position
var _prev_room_pos := NO_ROOM   # the room being left, recorded on the way out
var _prev_room_coins: Array = []
var _restore_pos := NO_ROOM     # the room BEFORE that — the one a turnaround walks back into
var _restore_coins: Array = []

func _stash_dropped_coins() -> void:
	# Hand the old stash over to the restore slot FIRST. Both steps run inside one transition:
	# stash-on-exit would otherwise clobber the previous room's gold before restore-on-entry got
	# to read it, so walking straight back would find the floor empty.
	_restore_pos = _prev_room_pos
	_restore_coins = _prev_room_coins
	var left: Array = []
	for c in get_tree().get_nodes_in_group("coins"):
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			left.append({"pos": c.global_position, "value": c.value()})
	_prev_room_pos = _current_pos
	_prev_room_coins = left

func _restore_dropped_coins() -> void:
	if _current_pos != _restore_pos or _restore_coins.is_empty():
		return
	var saved: Array = _restore_coins
	_restore_coins = [] # live again — don't double-spawn if they leave without collecting
	# Deferred: _go_through_door queue_free()s everything in _enemies earlier in this same frame,
	# and that flush must land before the replacements go in, or they're swept up with it.
	for entry in saved:
		_spawn_saved_coin.call_deferred(entry["pos"], int(entry["value"]))

func _spawn_saved_coin(pos: Vector2, value: int) -> void:
	var c: Node2D = COIN_SCENE.instantiate()
	_enemies.add_child(c)
	# Zero speed: it settles exactly where it was dropped rather than bursting outward again.
	c.burst(pos, Vector2.ZERO, 0.0, value)

# ── Fire Trail+ / Wave Pulse+ ───────────────────────────────────────────────────────────────
# Both are passive, artifact-driven, and both read through artifact_num — which ignores
# combat_only artifacts outside fight rooms, so these go quiet in the lobby, shops and the bar
# without either tick needing its own room check. Spawned into _enemies so they're cleaned up
# with everything else on a room transition.
const FIRE_TRAIL_DROP_INTERVAL := 0.18 # seconds between patches
const FIRE_TRAIL_MIN_STEP := 26.0      # ...and a minimum distance moved, so standing still
                                       # doesn't stack a pile of patches on one spot
var _fire_trail_timer := 0.0
var _fire_trail_last := Vector2.ZERO
func _tick_fire_trail(delta: float) -> void:
	var burn := int(ItemRegistry.artifact_num("fire_trail_burn_damage", 0.0))
	if burn <= 0:
		return
	_fire_trail_timer -= delta
	if _fire_trail_timer > 0.0:
		return
	if _player.global_position.distance_to(_fire_trail_last) < FIRE_TRAIL_MIN_STEP:
		return
	_fire_trail_timer = FIRE_TRAIL_DROP_INTERVAL
	_fire_trail_last = _player.global_position
	var patch: Node2D = FIRE_PATCH_SCENE.instantiate()
	_enemies.add_child(patch)
	patch.configure(_player.global_position, burn, ItemRegistry.artifact_num("fire_trail_burn_duration", 3.0))

var _wave_pulse_timer := 0.0
func _tick_wave_pulse(delta: float) -> void:
	var dmg := int(ItemRegistry.artifact_num("wave_pulse_damage", 0.0))
	if dmg <= 0:
		return
	_wave_pulse_timer -= delta
	if _wave_pulse_timer > 0.0:
		return
	_wave_pulse_timer = ItemRegistry.artifact_num("wave_pulse_interval", 2.0)
	var pulse: Node2D = WAVE_PULSE_SCENE.instantiate()
	_enemies.add_child(pulse)
	pulse.configure(_player.global_position, dmg)

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

# Rooms that never carry a fight. Keyed on KIND rather than the room's cleared flag: a combat room
# is marked cleared the moment its fight is won, and Fire Trail+ / Wave Pulse+ should keep running
# in a level that spawns enemies, not switch off mid-room.
const NO_COMBAT_KINDS := ["start", "shop", "bar"]
func _set_combat_room_flag(st: Dictionary) -> void:
	GameManager.room_spawns_enemies = not (str(st.get("kind", "combat")) in NO_COMBAT_KINDS)

# Invincible+ artifact: grant the room-entry invincibility window (no-op if not equipped).
func _grant_room_invincibility() -> void:
	if _player != null and is_instance_valid(_player):
		_player.grant_room_invincible(ItemRegistry.artifact_num("room_invincible_seconds", 0.0))

# On Start: convert unused loadout points into starting gold with a little count-up animation. The
# gold is added incrementally as it counts so the HUD credit total rises in sync. No-op if the whole
# budget was spent.
func _grant_loadout_bonus() -> void:
	if _loadout_bonus <= 0:
		return
	var pts := _unused_points
	var bonus := _loadout_bonus
	_loadout_bonus = 0 # once per run
	var base := GameManager.coins

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE # non-blocking — the player can move meanwhile
	_hud.add_child(overlay)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.28
	panel.anchor_bottom = 0.28
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.10, 0.85)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(16)
	style.border_color = Color(1.0, 0.82, 0.2, 0.8)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "🎯  %d Unused Loadout Point%s" % [pts, "" if pts == 1 else "s"]
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var gold_lbl := Label.new()
	gold_lbl.text = "+0 🪙"
	gold_lbl.add_theme_font_size_override("font_size", 24)
	gold_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2))
	gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(gold_lbl)

	var tw := create_tween()
	tw.tween_method(func(v: float):
		var g := int(round(v))
		GameManager.coins = base + g
		gold_lbl.text = "+%d 🪙" % g
	, 0.0, float(bonus), 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.7)
	tw.tween_property(overlay, "modulate:a", 0.0, 0.5)
	tw.tween_callback(overlay.queue_free)

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
	coins_lbl.text = "🪙 %d credits" % GameManager.coins
	coins_lbl.add_theme_font_size_override("font_size", 15)
	coins_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2))
	coins_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(coins_lbl)


	# Weapon fusion — only offered when the player actually brought a second weapon, the pair
	# combines, and they haven't already fused this run.
	_add_fuse_button(vbox)
	# Elemental boost — draws at random from the catalog the player loaded before the run.
	_add_boost_button(vbox)

	var leave_btn := Button.new()
	leave_btn.text = "Leave Shop"
	leave_btn.custom_minimum_size = Vector2(0, 44)
	leave_btn.pressed.connect(_close_reward_popup)
	vbox.add_child(leave_btn)

# ── Weapon fusion ────────────────────────────────────────────────────────────────────────────
# The player carries a primary and (optionally) a secondary weapon, both paid for in equipment
# points. At a shop, FUSE_COST credits combines them into the matching COMBINED_WEAPONS entry,
# consuming BOTH originals. Once per run. Never fusing costs nothing — the secondary comes home
# intact, which is what makes bringing one a low-risk bet rather than a gamble.
const FUSE_COST := 100
var _fused_this_run := false

# Which of the five pool weapons this run's fusion will use. Drawn once, the first time the
# question is asked, and then held for the rest of the run — re-rolling on every shop visit would
# let the player shop-hop until they got the pairing they wanted, which defeats the 1-in-5.
var _fusion_draw: Dictionary = {}

# The pool entries that actually pair with the current primary. Not every same-type pair has a
# recipe — Beam Sword + Beam Sword has none, for instance — so drawing blind from all five could
# land on a dead pair and make the whole fuse option vanish with no explanation. Drawing from the
# valid subset keeps every draw meaningful; the character screen already warns when some of the
# five can't pair, so the player knows their real odds before the run.
func _fusable_pool_entries() -> Array:
	var a: String = SaveManager.equipped_weapon.get("name", "")
	if a == "":
		return []
	return SaveManager.secondary_pool.filter(
		func(e): return not ItemRegistry.fusion_result(a, str(e.get("name", ""))).is_empty())

func _secondary_draw() -> Dictionary:
	if _fusion_draw.is_empty() and SaveManager.secondary_pool_full():
		var valid := _fusable_pool_entries()
		if not valid.is_empty():
			_fusion_draw = valid[randi() % valid.size()]
	return _fusion_draw

# The fusion available right now, or {} if there isn't one.
func _available_fusion() -> Dictionary:
	if _fused_this_run:
		return {}
	var a: String = SaveManager.equipped_weapon.get("name", "")
	var b: String = str(_secondary_draw().get("name", ""))
	if a == "" or b == "":
		return {}
	return ItemRegistry.fusion_result(a, b)

func _add_fuse_button(vbox: VBoxContainer) -> void:
	var result := _available_fusion()
	if result.is_empty():
		# A partial pool is the most common reason the option is missing, and the least obvious —
		# say so rather than showing nothing at all.
		if not _fused_this_run and not SaveManager.secondary_pool.is_empty() and not SaveManager.secondary_pool_full():
			vbox.add_child(_fuse_note("⚗️  Second weapon pool only %d/%d loaded — no fusion this run"
				% [SaveManager.secondary_pool.size(), SaveManager.SECONDARY_POOL_SIZE]))
			return
		if not _fused_this_run and SaveManager.secondary_pool_full() and _fusable_pool_entries().is_empty():
			vbox.add_child(_fuse_note("⚗️  None of your 5 pool weapons fuse with %s"
				% SaveManager.equipped_weapon.get("name", "your weapon")))
			return
		# Explain why it isn't on offer, but only once the player has actually brought two weapons —
		# otherwise the shop would nag every visit about a system they chose not to use.
		if _fused_this_run and SaveManager.secondary_pool_full():
			var done := Label.new()
			done.text = "⚗️  Already fused this run"
			done.add_theme_font_size_override("font_size", 13)
			done.add_theme_color_override("font_color", Color(0.6, 0.62, 0.68))
			done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(done)
		return
	var cost := _shop_price(FUSE_COST)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 52)
	# Deliberately does NOT name the result — the reveal sequence is the whole point.
	btn.text = "⚗️  Fuse Weapon — %d🪙" % cost
	btn.add_theme_color_override("font_color", Color(0.72, 0.90, 1.0))
	btn.disabled = GameManager.coins < cost
	btn.pressed.connect(_do_fusion)
	vbox.add_child(btn)

	vbox.add_child(_fuse_note("%s + one of your %d (both consumed)"
		% [SaveManager.equipped_weapon.get("name", ""), _fusable_pool_entries().size()]))

func _fuse_note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.62, 0.65, 0.72))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _do_fusion() -> void:
	var result := _available_fusion()
	var cost := _shop_price(FUSE_COST)
	if result.is_empty() or GameManager.coins < cost:
		return
	GameManager.spend_coins(cost)
	_fused_this_run = true
	# Both components are consumed: the fused weapon takes the primary slot and the secondary is
	# emptied. _fused_components records what went in so the run-loss pass knows they're gone.
	var drawn: String = str(_secondary_draw().get("name", ""))
	_fused_components = [SaveManager.equipped_weapon.get("name", ""), drawn]
	SaveManager.consume_for_fusion(_fused_components)
	SaveManager.set_slot("equipped_weapon", result.duplicate(true))
	SaveManager.remove_from_secondary_pool(drawn) # only the drawn one is spent; the other 4 remain
	_reequip_weapon() # swap the live weapon immediately
	GameManager.add_screen_shake(0.35)
	_show_fusion_reveal(_fused_components[0], drawn, result)

var _fused_components: Array = []

# ── Elemental boosts ─────────────────────────────────────────────────────────────────────────
# BOOST_COST buys ONE boost drawn at random from the catalog the player loaded before the run —
# they stack the odds by choosing what goes in, but not which one comes out. The boost is applied
# to the currently equipped weapon and consumed. How many a weapon can hold depends on its rarity
# (ItemRegistry.BOOST_SLOTS_BY_RARITY): commons and uncommons take 2, rares only 1.
const BOOST_COST := 50

func _weapon_boosts() -> Array:
	return SaveManager.equipped_weapon.get("applied_boosts", [])

func _boost_slots_free() -> int:
	return ItemRegistry.boost_slots_for(SaveManager.equipped_weapon) - _weapon_boosts().size()

func _add_boost_button(vbox: VBoxContainer) -> void:
	if SaveManager.equipped_weapon.is_empty() or SaveManager.boost_catalog.is_empty():
		return
	var free := _boost_slots_free()
	var cost := _shop_price(BOOST_COST)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 48)
	if free <= 0:
		btn.text = "⚡  No boost slots left (%s holds %d)" % [
			str(SaveManager.equipped_weapon.get("rarity", "")).capitalize(),
			ItemRegistry.boost_slots_for(SaveManager.equipped_weapon)]
		btn.disabled = true
	else:
		btn.text = "⚡  Apply Elemental Boost — %d🪙" % cost
		btn.disabled = GameManager.coins < cost
		btn.pressed.connect(_buy_boost)
	vbox.add_child(btn)

	var sub := Label.new()
	sub.text = "%d in catalog · %d slot%s free" % [SaveManager.boost_catalog.size(), free, "" if free == 1 else "s"]
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color(0.62, 0.65, 0.72))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

func _buy_boost() -> void:
	var cost := _shop_price(BOOST_COST)
	if GameManager.coins < cost or _boost_slots_free() <= 0 or SaveManager.boost_catalog.is_empty():
		return
	# Draw from the catalog at the normal rarity odds — the player picked the pool, not the result.
	var pool: Array = []
	for n in SaveManager.boost_catalog:
		var b := ItemRegistry.boost_by_name(str(n))
		if not b.is_empty():
			pool.append(b)
	if pool.is_empty():
		return
	GameManager.spend_coins(cost)
	var boost: Dictionary = ItemRegistry.roll_boost(pool)
	var w: Dictionary = SaveManager.equipped_weapon.duplicate(true)
	var applied: Array = w.get("applied_boosts", []).duplicate()
	applied.append(boost["name"])
	w["applied_boosts"] = applied
	SaveManager.set_slot("equipped_weapon", w)
	SaveManager.consume_boost(boost["name"]) # spent — gone from inventory and catalog
	_reequip_weapon() # the boosted stats take effect immediately
	_show_boost_result(boost)

# Shows what the draw produced, then drops back to the shop.
func _show_boost_result(boost: Dictionary) -> void:
	if _reward_popup != null and is_instance_valid(_reward_popup):
		_reward_popup.queue_free()
	GameManager.ui_popup_open = true
	_reward_popup = _build_popup_shell()
	var vbox: VBoxContainer = _reward_popup.get_meta("vbox")
	var title := Label.new()
	title.text = "⚡  %s" % boost.get("name", "")
	title.add_theme_font_size_override("font_size", 19)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", _rarity_text_color(boost.get("rarity", "")))
	vbox.add_child(title)
	var desc := Label.new()
	desc.text = str(boost.get("effect", ""))
	desc.add_theme_font_size_override("font_size", 13)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc)
	var applied_to := Label.new()
	applied_to.text = "Applied to %s" % SaveManager.equipped_weapon.get("name", "")
	applied_to.add_theme_font_size_override("font_size", 12)
	applied_to.add_theme_color_override("font_color", Color(0.62, 0.65, 0.72))
	applied_to.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(applied_to)
	var back := Button.new()
	back.text = "Back to Shop"
	back.custom_minimum_size = Vector2(0, 44)
	back.pressed.connect(_show_shop)
	vbox.add_child(back)

# Cumulative multiplier for a branch tier (product of UPGRADE_MULTS[0..tier-1]).
func _upgrade_product(tier: int) -> float:
	var p := 1.0
	for i in tier:
		p *= UPGRADE_MULTS[i]
	return p

# Applies the current HP-upgrade tier (+ the Health+ artifact) as bonus max HP.
func _apply_hp_bonus() -> void:
	if _player != null and is_instance_valid(_player):
		_player.apply_bonus_max_health(int(ItemRegistry.artifact_num("bonus_hp", 0.0)) + _hp_tier * HP_PER_BUBBLE + _run_bonus_hp)


# Upgrade tree popup: three branches (damage / fire rate / HP), 5 bubbles each. Owned bubbles are
# green, the next is buyable (shows its cost), the rest locked. Bought in order.
# The weapon upgrade tree was removed along with the shops — per-weapon damage/rate-of-fire
# bubbles are replaced by the post-floor supply crates, which hand out the same kinds of bonus as
# run-wide multipliers instead. _weapon_dmg_tier/_weapon_rof_tier are still read by
# _reequip_weapon, and stay at 0 for the whole run now that nothing can raise them.

func _shop_buy_heal() -> void:
	if GameManager.coins < _shop_price(SHOP_HEAL_COST):
		return
	GameManager.spend_coins(_shop_price(SHOP_HEAL_COST))
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
	GameManager.spend_coins(_shop_price(SHOP_UPGRADE_COST))
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
	GameManager.spend_coins(_shop_price(SHOP_CRATE_COST))
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
	_crate_tween = create_tween()
	_crate_tween.tween_property(track, "position:x", end_x, 5.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_crate_tween.tween_callback(func():
		_crate_track = null
		_crate_tween = null
		_show_ff_watermark(false)
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
	_spinning = false
	GameManager.ui_popup_open = false

# Direct touch fallback for the reward popup's buttons, same reasoning as menu.gd/
# character.gd: ButtonNode.pressed only fires on InputEventMouseButton, but the embedded
# display server may not run emulate_mouse_from_touch, so popup taps could otherwise silently
# do nothing on iOS.
func _input(event: InputEvent) -> void:
	# Hold the screen during a crate/artifact spin to fast-forward it at 2x (with a ⏩ watermark).
	if _crate_tween != null and _crate_tween.is_valid() and event is InputEventScreenTouch:
		if event.pressed:
			_crate_tween.set_speed_scale(2.0)
			_show_ff_watermark(true)
		else:
			_crate_tween.set_speed_scale(1.0)
			_show_ff_watermark(false)
		return
	if _reward_popup == null or not is_instance_valid(_reward_popup):
		return
	if event is InputEventScreenTouch and event.pressed:
		var btn := _find_button_at(_reward_popup, event.position)
		if btn != null:
			btn.pressed.emit()
			get_viewport().set_input_as_handled()

# Transparent ⏩ fast-forward watermark over the whole screen while a spin is being held.
func _show_ff_watermark(show: bool) -> void:
	if show:
		if _ff_label == null or not is_instance_valid(_ff_label):
			_ff_label = Label.new()
			_ff_label.text = "⏩"
			_ff_label.add_theme_font_size_override("font_size", 120)
			_ff_label.modulate = Color(1, 1, 1, 0.22) # watermark — barely there
			_ff_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			_ff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_ff_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_ff_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_hud.add_child(_ff_label)
	elif _ff_label != null and is_instance_valid(_ff_label):
		_ff_label.queue_free()
		_ff_label = null

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

# ── Fusion reveal ────────────────────────────────────────────────────────────────────────────
# A four-beat sequence played after paying for a fusion, in place of simply naming the result:
#   1. a hologram panel rises and the pool weapons spin past it, decelerating onto the drawn one
#   2. the primary and the drawn weapon settle side by side with a "+" between them
#   3. they slide together and a white blast washes the screen
#   4. the fused weapon is revealed
# The outcome is already decided and committed before any of this runs — the animation only
# reports it, so a player who backgrounds the app mid-spin still gets the same weapon.
const FUSE_SPIN_TIME  := 1.7
const FUSE_PAIR_TIME  := 1.0
const FUSE_BLAST_TIME := 0.45

var _fuse_overlay: Control = null
var _fuse_reel: TextureRect = null
var _fuse_reel_pool: Array = []
var _fuse_spin_t := 0.0
var _fuse_spinning := false
var _fuse_tick := 0.0

func _icon_tex(item_name: String) -> Texture2D:
	var it: Dictionary = ItemRegistry.get_item_by_name(item_name)
	if it.is_empty():
		it = ItemRegistry.combined_by_name(item_name)
	var path: String = "res://assets/icons/" + str(it.get("file", ""))
	return load(path) if ResourceLoader.exists(path) else null

func _fuse_icon(item_name: String, size: float) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(size, size)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.texture = _icon_tex(item_name)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _show_fusion_reveal(primary: String, drawn: String, result: Dictionary) -> void:
	_close_reward_popup()
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud.add_child(overlay)
	_fuse_overlay = overlay

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.02, 0.04, 0.86)
	overlay.add_child(dim)

	# The hologram: a cyan-rimmed pane that scales up from nothing.
	var holo := PanelContainer.new()
	holo.anchor_left = 0.5; holo.anchor_right = 0.5
	holo.anchor_top = 0.5;  holo.anchor_bottom = 0.5
	holo.offset_left = -150.0; holo.offset_right = 150.0
	holo.offset_top = -110.0;  holo.offset_bottom = 110.0
	holo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holo.grow_vertical = Control.GROW_DIRECTION_BOTH
	holo.pivot_offset = Vector2(150, 110)
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.06, 0.20, 0.28, 0.80)
	hs.border_color = Color(0.35, 0.85, 1.0, 0.9)
	hs.set_border_width_all(2)
	hs.set_corner_radius_all(12)
	hs.set_content_margin_all(12.0)
	holo.add_theme_stylebox_override("panel", hs)
	holo.scale = Vector2(0.2, 0.2)
	holo.modulate = Color(1, 1, 1, 0.0)
	overlay.add_child(holo)
	overlay.set_meta("holo", holo)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	holo.add_child(col)

	var cap := Label.new()
	cap.text = "SELECTING FROM POOL"
	cap.add_theme_font_size_override("font_size", 12)
	cap.add_theme_color_override("font_color", Color(0.55, 0.92, 1.0))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	overlay.set_meta("caption", cap)

	var stage := CenterContainer.new()
	stage.custom_minimum_size = Vector2(0, 120)
	col.add_child(stage)
	overlay.set_meta("stage", stage)

	# Beat 1: the reel. A single icon swapped rapidly, slowing as it settles — the same read as
	# the crate spin without needing a scrolling track inside a 300px pane.
	_fuse_reel_pool = []
	for e in SaveManager.secondary_pool:
		_fuse_reel_pool.append(str(e.get("name", "")))
	if not _fuse_reel_pool.has(drawn):
		_fuse_reel_pool.append(drawn)
	_fuse_reel = _fuse_icon(drawn, 76.0)
	stage.add_child(_fuse_reel)
	_fuse_spin_t = 0.0
	_fuse_tick = 0.0
	_fuse_spinning = true

	var tw := create_tween()
	tw.tween_property(holo, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(holo, "modulate:a", 1.0, 0.2)

	get_tree().create_timer(FUSE_SPIN_TIME).timeout.connect(
		func(): _fuse_beat_pair(primary, drawn, result))

func _process_fusion_spin(delta: float) -> void:
	if not _fuse_spinning or _fuse_reel == null or not is_instance_valid(_fuse_reel):
		return
	_fuse_spin_t += delta
	# Swap interval eases from 0.04s to 0.30s across the spin, so it visibly decelerates.
	var t: float = clampf(_fuse_spin_t / FUSE_SPIN_TIME, 0.0, 1.0)
	var interval: float = lerpf(0.04, 0.30, t * t)
	_fuse_tick -= delta
	if _fuse_tick <= 0.0:
		_fuse_tick = interval
		if not _fuse_reel_pool.is_empty():
			_fuse_reel.texture = _icon_tex(_fuse_reel_pool[randi() % _fuse_reel_pool.size()])
		AudioManager.play_tick()

# Beat 2: the two components side by side.
func _fuse_beat_pair(primary: String, drawn: String, result: Dictionary) -> void:
	_fuse_spinning = false
	if _fuse_overlay == null or not is_instance_valid(_fuse_overlay):
		return
	var stage: CenterContainer = _fuse_overlay.get_meta("stage")
	var cap: Label = _fuse_overlay.get_meta("caption")
	cap.text = "FUSING"
	for c in stage.get_children():
		c.queue_free()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var left := _fuse_icon(primary, 64.0)
	var plus := Label.new()
	plus.text = "+"
	plus.add_theme_font_size_override("font_size", 28)
	plus.add_theme_color_override("font_color", Color(0.6, 0.92, 1.0))
	plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var right := _fuse_icon(drawn, 64.0)
	row.add_child(left); row.add_child(plus); row.add_child(right)
	stage.add_child(row)

	var names := Label.new()
	names.text = "%s  +  %s" % [primary, drawn]
	names.add_theme_font_size_override("font_size", 11)
	names.add_theme_color_override("font_color", Color(0.72, 0.86, 0.95))
	names.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(names)

	# Slide the two together, then hand off to the blast.
	var tw := create_tween()
	tw.tween_interval(FUSE_PAIR_TIME * 0.45)
	tw.tween_property(left, "position:x", left.position.x + 34.0, FUSE_PAIR_TIME * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(right, "position:x", right.position.x - 34.0, FUSE_PAIR_TIME * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(plus, "modulate:a", 0.0, FUSE_PAIR_TIME * 0.3)
	tw.tween_callback(func(): _fuse_beat_blast(result))

# Beat 3: a white wash over the whole screen.
func _fuse_beat_blast(result: Dictionary) -> void:
	if _fuse_overlay == null or not is_instance_valid(_fuse_overlay):
		return
	var flash := ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 1, 1, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fuse_overlay.add_child(flash)
	GameManager.add_screen_shake(0.5)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 1.0, FUSE_BLAST_TIME * 0.35)
	tw.tween_callback(func(): _fuse_beat_result(result))
	tw.tween_property(flash, "color:a", 0.0, FUSE_BLAST_TIME * 0.65)
	tw.tween_callback(func(): flash.queue_free())

# Beat 4: the fused weapon.
func _fuse_beat_result(result: Dictionary) -> void:
	if _fuse_overlay == null or not is_instance_valid(_fuse_overlay):
		return
	var stage: CenterContainer = _fuse_overlay.get_meta("stage")
	var cap: Label = _fuse_overlay.get_meta("caption")
	cap.text = "FUSION COMPLETE"
	for c in stage.get_children():
		c.queue_free()

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	var icon := _fuse_icon(str(result.get("name", "")), 84.0)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(icon)
	var nm := Label.new()
	nm.text = str(result.get("name", ""))
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_color_override("font_color", _rarity_text_color(result.get("rarity", "")))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nm)
	var sub := Label.new()
	sub.text = "%s  ·  %s" % [str(result.get("rarity", "")).capitalize(), ItemRegistry.weapon_kind_label(result)]
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color(0.70, 0.76, 0.86))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	stage.add_child(col)

	var done := Button.new()
	done.text = "Continue"
	done.custom_minimum_size = Vector2(0, 42)
	done.pressed.connect(func():
		if _fuse_overlay != null and is_instance_valid(_fuse_overlay):
			_fuse_overlay.queue_free()
			_fuse_overlay = null
		_show_shop()
	)
	var holo: Control = _fuse_overlay.get_meta("holo")
	holo.get_child(0).add_child(done)

# ── Fusion table (bar) ───────────────────────────────────────────────────────────────────────
# The weapon bench that replaced the shops. Offers exactly what the shop did for weapons — fusing
# the drawn pool weapon into the primary (FUSE_COST) and loading an elemental boost (BOOST_COST) —
# at the same prices, reusing the same builders so the two can never drift apart.
func _show_fusion_table() -> void:
	if _reward_popup != null and is_instance_valid(_reward_popup):
		_reward_popup.queue_free()
		_reward_popup = null
	GameManager.ui_popup_open = true
	_reward_popup = _build_popup_shell()
	var vbox: VBoxContainer = _reward_popup.get_meta("vbox")

	var title := Label.new()
	title.text = "⚗️  Fabrication Bench"
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(0.373, 0.847, 0.961))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var coins_lbl := Label.new()
	coins_lbl.text = "🪙 %d credits" % GameManager.coins
	coins_lbl.add_theme_font_size_override("font_size", 15)
	coins_lbl.add_theme_color_override("font_color", Color(1.0, 0.663, 0.2))
	coins_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(coins_lbl)

	_add_fuse_button(vbox)  # same offer, same price, same once-per-run rule as before
	_add_boost_button(vbox)

	var leave := Button.new()
	leave.text = "Step Away"
	leave.custom_minimum_size = Vector2(0, 44)
	leave.pressed.connect(_close_reward_popup)
	vbox.add_child(leave)
	UI_THEME.style_all_buttons(_reward_popup, UI_THEME.CYAN)

# ── Post-floor upgrade crate ─────────────────────────────────────────────────────────────────
# Clearing a fight drops a crate. Walking up to it shows an Open prompt; opening it spins a reel
# that stops on THREE cards at once and lets the player buy exactly one of them for UPGRADE_COST.
# Taking one bursts the crate and opens the doors. Skipping it also opens the doors — the crate is
# an opportunity, not a toll.
const UPGRADE_CRATE_SCENE := preload("res://scenes/upgrade_crate/upgrade_crate.tscn")
const UPGRADE_COST := 35
const UPGRADE_PICK_RANGE := 70.0

# Each upgrade is a permanent, stacking run bonus. Kept deliberately small so they read as a
# steady drip rather than a power spike — the player sees a lot of these over a long run.
const RUN_UPGRADES := [
	{"key": "dmg",   "icon": "⚔", "name": "Weapon Damage",    "detail": "+3% damage",        "color": Color(1.00, 0.45, 0.38)},
	{"key": "rof",   "icon": "⟳", "name": "Rate of Fire",     "detail": "+3% fire rate",     "color": Color(1.00, 0.80, 0.30)},
	{"key": "speed", "icon": "➤", "name": "Movement Speed",   "detail": "+5% move speed",    "color": Color(0.45, 0.95, 0.65)},
	{"key": "hp",    "icon": "✚", "name": "Hull Integrity",   "detail": "+10 max health",    "color": Color(0.45, 0.85, 1.00)},
	{"key": "elem",  "icon": "✦", "name": "Elemental Charge", "detail": "+5% elemental dmg", "color": Color(0.80, 0.55, 1.00)},
]

var _run_dmg_mult := 1.0
var _run_rof_mult := 1.0
var _run_elem_mult := 1.0
var _run_bonus_hp := 0
var _upgrade_crate: Node2D = null
var _crate_prompt_active := false
var _crate_pending := false # doors stay shut while a crate is waiting to be resolved
var _room_had_fight := false # true if THIS room spawned enemies — what earns a reward crate

func _spawn_upgrade_crate() -> void:
	if _upgrade_crate != null and is_instance_valid(_upgrade_crate):
		_upgrade_crate.queue_free()
	var c: Node2D = UPGRADE_CRATE_SCENE.instantiate()
	# Drop it in the middle of the room the player just cleared, nudged off the exact centre so it
	# never lands under the player standing still.
	var r: Rect2 = GameManager.play_rect
	c.global_position = r.get_center() + Vector2(0.0, -28.0)
	_props.add_child(c)
	_upgrade_crate = c
	_crate_prompt_active = false
	_crate_pending = true

# Proximity check, called from _physics_process alongside the bar/shop prompts.
func _tick_upgrade_crate() -> void:
	if _upgrade_crate == null or not is_instance_valid(_upgrade_crate):
		return
	if GameManager.ui_popup_open:
		return
	var near := _player.global_position.distance_to(_upgrade_crate.global_position) <= UPGRADE_PICK_RANGE
	if near and not _crate_prompt_active:
		_crate_prompt_active = true
		_show_crate_prompt()
	elif not near and _crate_prompt_active:
		_crate_prompt_active = false
		_close_crate_prompt()

var _crate_prompt: Control = null

func _show_crate_prompt() -> void:
	_close_crate_prompt()
	_crate_prompt = Control.new()
	_crate_prompt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crate_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_crate_prompt)
	var btn := Button.new()
	btn.text = "◈  OPEN"
	btn.custom_minimum_size = Vector2(170, 52)
	btn.anchor_left = 0.5
	btn.anchor_right = 0.5
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = -85.0
	btn.offset_right = 85.0
	btn.offset_top = -210.0
	btn.offset_bottom = -158.0
	btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	UI_THEME.style_button(btn, UI_THEME.CYAN, 18)
	btn.pressed.connect(_open_upgrade_crate)
	_crate_prompt.add_child(btn)
	_crate_prompt.modulate.a = 0.0
	var tw := _crate_prompt.create_tween()
	tw.tween_property(_crate_prompt, "modulate:a", 1.0, 0.18)

func _close_crate_prompt() -> void:
	if _crate_prompt != null and is_instance_valid(_crate_prompt):
		_crate_prompt.queue_free()
	_crate_prompt = null

# The reel. Same presentation as a normal crate opening, with two deliberate differences: no
# centre line (nothing is being singled out), and the highlight window spans THREE cards — the
# reel stops showing three offers side by side and the player buys one.
const UC_CARD_W := 104
const UC_CARD_H := 124
const UC_CARD_GAP := 8
const UC_SLOT := UC_CARD_W + UC_CARD_GAP
const UC_WINNER_IDX := 30 # the middle of the three that land in the window

var _uc_track: HBoxContainer = null
var _uc_stage: Control = null
var _uc_column: VBoxContainer = null # reel + hint + choice buttons, aligned as one column
var _uc_offers: Array = []
var _uc_tween: Tween = null
var _upgrade_taken := false # one purchase per crate — guards against a double-fired tap

func _open_upgrade_crate() -> void:
	_close_crate_prompt()
	_crate_prompt_active = false
	_upgrade_taken = false
	GameManager.ui_popup_open = true
	# Three distinct upgrades, drawn without replacement so the window never shows duplicates.
	var pool: Array = RUN_UPGRADES.duplicate()
	pool.shuffle()
	_uc_offers = [pool[0], pool[1], pool[2]]

	if _reward_popup != null and is_instance_valid(_reward_popup):
		_reward_popup.queue_free()
	_reward_popup = _build_popup_shell()
	# The crate needs more width than the other popups — three cards side by side plus the stat
	# panel. Widened here rather than in _build_popup_shell so every other dialog keeps its size.
	var panel_node: Control = _reward_popup.get_child(1)
	panel_node.offset_left = -262.0
	panel_node.offset_right = 262.0
	var vbox: VBoxContainer = _reward_popup.get_meta("vbox")

	var title := Label.new()
	title.text = "SUPPLY CRATE"
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", UI_THEME.CYAN_HOT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Reel on the left, the player's accumulated run stats on the right — so the upgrade being
	# offered can be read against what it would actually change.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	vbox.add_child(body)

	# Reel, hint and the choice buttons share one column, so the buttons sit directly under the
	# cards they belong to. Putting the buttons in the outer vbox centred them on the whole popup
	# instead, which left them visibly offset from the three cards above.
	_uc_column = VBoxContainer.new()
	_uc_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_uc_column.add_theme_constant_override("separation", 6)
	body.add_child(_uc_column)

	_uc_stage = Control.new()
	_uc_stage.custom_minimum_size = Vector2(0, UC_CARD_H + 16)
	_uc_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_uc_stage.clip_contents = true
	_uc_column.add_child(_uc_stage)

	body.add_child(_build_stat_panel())

	_uc_track = HBoxContainer.new()
	_uc_track.add_theme_constant_override("separation", UC_CARD_GAP)
	_uc_stage.add_child(_uc_track)

	# Window frame spanning three cards — drawn behind the reel, with NO centre line.
	var frame := Control.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_uc_stage.add_child(frame)
	frame.draw.connect(func(): _draw_uc_frame(frame))

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "Scanning…"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UI_THEME.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_uc_column.add_child(hint)

	_build_uc_track()
	await get_tree().process_frame
	_spin_upgrade_reel()

# Three-card read window: brackets around the whole span, dimmed shoulders either side, and no
# centre marker — all three cards inside are equally on offer.
func _draw_uc_frame(frame: Control) -> void:
	if not is_instance_valid(frame):
		return
	var sz := frame.size
	if sz.x <= 0.0:
		return
	var win := float(UC_SLOT * 3 - UC_CARD_GAP) + 14.0
	var cx := sz.x * 0.5
	frame.draw_rect(Rect2(0, 0, cx - win * 0.5, sz.y), Color(UI_THEME.VOID, 0.60))
	frame.draw_rect(Rect2(cx + win * 0.5, 0, sz.x - cx - win * 0.5, sz.y), Color(UI_THEME.VOID, 0.60))
	UI_THEME.draw_brackets(frame, Rect2(cx - win * 0.5, 2.0, win, sz.y - 4.0),
		Color(UI_THEME.CYAN, 0.9), 18.0, 2.0)
	UI_THEME.draw_glow_line(frame, Vector2(0, 1.0), Vector2(sz.x, 1.0), UI_THEME.CYAN, 1.5, 0.8)
	UI_THEME.draw_glow_line(frame, Vector2(0, sz.y - 1.0), Vector2(sz.x, sz.y - 1.0), UI_THEME.CYAN, 1.5, 0.8)

func _build_uc_track() -> void:
	for c in _uc_track.get_children():
		c.queue_free()
	# Filler before the window, then the three real offers, then filler after.
	for i in UC_WINNER_IDX - 1:
		_uc_track.add_child(_make_uc_card(RUN_UPGRADES[randi() % RUN_UPGRADES.size()], false))
	for off in _uc_offers:
		_uc_track.add_child(_make_uc_card(off, true))
	for i in 8:
		_uc_track.add_child(_make_uc_card(RUN_UPGRADES[randi() % RUN_UPGRADES.size()], false))

func _make_uc_card(up: Dictionary, real: bool) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(UC_CARD_W, UC_CARD_H)
	var accent: Color = up["color"]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r * 0.12, accent.g * 0.12, accent.b * 0.16, 0.92)
	sb.border_color = Color(accent, 0.8)
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8.0)
	card.add_theme_stylebox_override("panel", sb)
	card.set_meta("upgrade", up)
	card.set_meta("real", real)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)

	var icon := Label.new()
	icon.text = str(up["icon"])
	icon.add_theme_font_size_override("font_size", 30)
	icon.add_theme_color_override("font_color", accent)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(icon)

	var nm := Label.new()
	nm.text = str(up["name"])
	nm.add_theme_font_size_override("font_size", 11)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nm)

	var det := Label.new()
	det.text = str(up["detail"])
	det.add_theme_font_size_override("font_size", 10)
	det.add_theme_color_override("font_color", accent)
	det.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(det)
	return card

func _spin_upgrade_reel() -> void:
	var vw := _uc_stage.size.x
	# Land so the MIDDLE of the three offers sits on centre, which places the other two either
	# side of it inside the window.
	var end_x := vw * 0.5 - (float(UC_WINNER_IDX) * float(UC_SLOT) + float(UC_CARD_W) * 0.5)
	_uc_track.position = Vector2(vw * 0.5 - float(UC_SLOT) * 0.5, 4.0)
	_uc_tween = create_tween()
	_uc_tween.tween_property(_uc_track, "position:x", end_x, 2.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_uc_tween.tween_callback(_offer_upgrade_choice)

# Reel has landed: the three offers are sitting in the window. Buying one is the only way to take
# an upgrade — the player can also walk away, which costs nothing.
func _offer_upgrade_choice() -> void:
	# The reel tween owns this callback, so it can land after the popup is gone — the player died,
	# left the room, or resolved the crate while it was still spinning. Bail rather than build
	# buttons onto a freed node.
	if _reward_popup == null or not is_instance_valid(_reward_popup) or _uc_offers.is_empty():
		return
	var vbox: VBoxContainer = _reward_popup.get_meta("vbox")
	var hint: Label = vbox.get_node_or_null("Hint")
	if hint != null:
		hint.text = "Choose ONE — %d🪙 each" % UPGRADE_COST
		hint.add_theme_color_override("font_color", UI_THEME.AMBER)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UC_CARD_GAP) # same gap as the cards above
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	# Into the reel column, not the outer vbox — this is what keeps each button under its card.
	var host: Node = _uc_column if (_uc_column != null and is_instance_valid(_uc_column)) else vbox
	host.add_child(row)
	var affordable := GameManager.coins >= UPGRADE_COST
	for i in _uc_offers.size():
		var up: Dictionary = _uc_offers[i]
		var b := Button.new()
		b.text = str(up["icon"])
		b.tooltip_text = "%s — %s" % [up["name"], up["detail"]]
		b.custom_minimum_size = Vector2(UC_CARD_W, 46)
		b.disabled = not affordable
		UI_THEME.style_button(b, up["color"], 20)
		b.pressed.connect(_take_upgrade.bind(i))
		row.add_child(b)

	var coins_lbl := Label.new()
	coins_lbl.text = "🪙 %d credits" % GameManager.coins
	coins_lbl.add_theme_font_size_override("font_size", 13)
	coins_lbl.add_theme_color_override("font_color",
		UI_THEME.AMBER if affordable else UI_THEME.DANGER)
	coins_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host.add_child(coins_lbl)
	if not affordable:
		coins_lbl.text = "🪙 %d — need %d" % [GameManager.coins, UPGRADE_COST]

	var skip := Button.new()
	skip.text = "Leave It"
	skip.custom_minimum_size = Vector2(0, 42)
	skip.pressed.connect(_dismiss_upgrade_crate)
	UI_THEME.style_button(skip, UI_THEME.TEXT_DIM, 15)
	vbox.add_child(skip)

func _take_upgrade(idx: int) -> void:
	# A single tap can arrive TWICE — once as InputEventScreenTouch and again as the emulated
	# mouse press — so `pressed` fires twice in one frame. Disabling the buttons was not enough:
	# that happened after the purchase, and both calls got through before it ran, charging twice
	# and applying the upgrade twice (+20 HP instead of +10, 6% instead of 3%). This flag is set
	# synchronously, before any work, so the second call can never do anything.
	if _upgrade_taken:
		return
	if idx < 0 or idx >= _uc_offers.size():
		return
	if GameManager.coins < UPGRADE_COST:
		return
	_upgrade_taken = true
	var up: Dictionary = _uc_offers[idx]
	var key := str(up["key"])
	var tint: Color = up["color"]
	GameManager.spend_coins(UPGRADE_COST)

	# Capture the stat BEFORE applying, so the row can count from the old value to the new one.
	var before := _stat_value(key)
	_apply_run_upgrade(key)
	var after := _stat_value(key)

	# Lock the buttons so a second tap during the animation can't buy twice.
	_set_upgrade_buttons_enabled(false)
	_fly_card_to_stat(key, tint, str(up["icon"]))
	await get_tree().create_timer(0.40).timeout   # card arrives
	_animate_stat(key, before, after, tint)
	GameManager.add_screen_shake(0.18)
	await get_tree().create_timer(0.85).timeout   # let the count-up finish and settle
	_dismiss_upgrade_crate()

# Greys out the three picks and the decline the moment one is chosen.
func _set_upgrade_buttons_enabled(on: bool) -> void:
	if _reward_popup == null or not is_instance_valid(_reward_popup):
		return
	for n in _reward_popup.get_meta("vbox").get_children():
		if n is Button:
			(n as Button).disabled = not on
		for c in n.get_children():
			if c is Button:
				(c as Button).disabled = not on

# Each upgrade stacks multiplicatively (or additively, for flat HP) for the rest of the run.
func _apply_run_upgrade(key: String) -> void:
	match key:
		"dmg":
			_run_dmg_mult *= 1.03
			_reequip_weapon()
		"rof":
			_run_rof_mult *= 1.03
			_reequip_weapon()
		"speed":
			if _player != null and is_instance_valid(_player):
				_player.set_run_speed_multiplier(_player._run_speed_multiplier * 1.05)
		"hp":
			_run_bonus_hp += 10
			_apply_hp_bonus()
		"elem":
			_run_elem_mult *= 1.05
			GameManager.elemental_effect_mult = _shirt_elem_base() * _run_elem_mult

# The shirt's own elemental multiplier, which the run upgrades scale on top of rather than
# overwrite (red shirt doubles elemental effects).
func _shirt_elem_base() -> float:
	return 2.0 if SaveManager.shirt_color == "red" else 1.0

# Closes the crate: burst, then unlock the doors. Used by both taking an upgrade and skipping.
var _crate_dismissing := false

func _dismiss_upgrade_crate() -> void:
	if _crate_dismissing:
		return # same double-tap hazard on "Leave It"
	_crate_dismissing = true
	_close_reward_popup()
	_uc_offers.clear()
	var wait := 0.0
	if _upgrade_crate != null and is_instance_valid(_upgrade_crate):
		wait = _upgrade_crate.burst() # blue spark
		GameManager.add_screen_shake(0.25)
	_upgrade_crate = null
	_crate_prompt_active = false
	_close_crate_prompt()
	# Doors open once the spark clears.
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	_crate_pending = false
	_crate_dismissing = false
	_refresh_doors()

# ── Run stat readout ─────────────────────────────────────────────────────────────────────────
# The running total of every upgrade bought this run, shown beside the crate reel. Each row is
# keyed by the same string the upgrades use, so taking one can find its row and animate it.

const STAT_ROWS := [
	{"key": "dmg",   "label": "Weapon Damage"},
	{"key": "rof",   "label": "Rate of Fire"},
	{"key": "hp",    "label": "Max Health"},
	{"key": "elem",  "label": "Elemental Dmg"},
	{"key": "speed", "label": "Move Speed"},
]

var _stat_value_labels := {} # key -> Label, so _animate_stat can find the row to count up

const SHIRT_PANEL_COLORS := {
	"blue":   Color(0.40, 0.62, 1.00),
	"red":    Color(1.00, 0.42, 0.38),
	"green":  Color(0.42, 0.92, 0.52),
	"yellow": Color(1.00, 0.84, 0.28),
}

# The shirt's own contribution to a stat, before any crate upgrades. Each colour is a character
# with a passive (see character.gd's SHIRT_PASSIVES), and those passives are real multipliers on
# the same stats the crates buy — so the panel has to start from them rather than from 1.00x, or
# it would under-report what the player actually has.
#
# Blue's 1.5x applies only to NON-elemental weapons and green/yellow only to melee/guns
# respectively, so the figure shown is what the CURRENTLY EQUIPPED weapon gets.
func _shirt_stat_base(key: String) -> float:
	var shirt: String = SaveManager.shirt_color
	if key == "elem":
		return 2.0 if shirt == "red" else 1.0
	if key != "dmg" and key != "rof":
		return 1.0
	var w: Dictionary = SaveManager.equipped_weapon
	if w.is_empty():
		return 1.0
	var is_elem: bool = str(w.get("element", "")) != ""
	var is_melee_w: bool = w.get("melee_range") != null or w.get("thrown_melee", false)
	var is_gun_w: bool = (not is_melee_w) and w.get("beam_range") == null
	match shirt:
		"blue":
			return 1.5 if (key == "dmg" and not is_elem) else 1.0
		"green":
			return 1.2 if is_melee_w else 1.0
		"yellow":
			return 1.2 if is_gun_w else 1.0
	return 1.0

# Current displayed value for a stat: the shirt's passive multiplied by everything bought from
# crates this run. Health is a flat bonus rather than a multiplier.
func _stat_value(key: String) -> float:
	match key:
		"dmg":   return _shirt_stat_base("dmg") * _run_dmg_mult
		"rof":   return _shirt_stat_base("rof") * _run_rof_mult
		"elem":  return _shirt_stat_base("elem") * _run_elem_mult
		"speed": return _player._run_speed_multiplier if (_player != null and is_instance_valid(_player)) else 1.0
		"hp":    return float(_run_bonus_hp)
	return 1.0

func _stat_text(key: String, v: float) -> String:
	return "+%d" % int(round(v)) if key == "hp" else "%.2fx" % v

func _build_stat_panel() -> Control:
	_stat_value_labels.clear()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(132, 0)
	panel.add_theme_stylebox_override("panel", UI_THEME.inset_box(UI_THEME.CYAN, 8))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	panel.add_child(col)

	var hdr := Label.new()
	hdr.text = "RUN STATS"
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", UI_THEME.CYAN)
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hdr)

	# Name the character, so a panel that starts at 1.50x reads as "this is my shirt" rather than
	# looking like a bug.
	var shirt: String = SaveManager.shirt_color
	var who := Label.new()
	who.text = shirt.capitalize()
	who.add_theme_font_size_override("font_size", 10)
	who.add_theme_color_override("font_color", SHIRT_PANEL_COLORS.get(shirt, UI_THEME.TEXT_DIM))
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(who)

	var sep := HSeparator.new()
	col.add_child(sep)

	for row in STAT_ROWS:
		var key: String = row["key"]
		var line := VBoxContainer.new()
		line.add_theme_constant_override("separation", 0)
		var name_lbl := Label.new()
		name_lbl.text = str(row["label"])
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", UI_THEME.TEXT_DIM)
		line.add_child(name_lbl)
		var val := Label.new()
		val.text = _stat_text(key, _stat_value(key))
		val.add_theme_font_size_override("font_size", 15)
		val.add_theme_color_override("font_color", UI_THEME.TEXT)
		line.add_child(val)
		_stat_value_labels[key] = val
		col.add_child(line)
	return panel

# Counts a stat row up to its new value after an upgrade is bought: the row flashes to the
# upgrade's colour, scales up, ticks from the old number to the new one, then settles. This is
# the moment the purchase is meant to feel earned, so it is deliberately the loudest thing on
# the screen for about a second.
func _animate_stat(key: String, from_v: float, to_v: float, tint: Color) -> void:
	var lbl: Label = _stat_value_labels.get(key)
	if lbl == null or not is_instance_valid(lbl):
		return
	lbl.pivot_offset = lbl.size * 0.5
	lbl.add_theme_color_override("font_color", tint)
	var tw := lbl.create_tween()
	# Count the number up.
	tw.tween_method(func(v: float):
		if is_instance_valid(lbl):
			lbl.text = _stat_text(key, v)
	, from_v, to_v, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Pop, then settle back to the normal text colour.
	tw.parallel().tween_property(lbl, "scale", Vector2(1.35, 1.35), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "scale", Vector2.ONE, 0.42).set_delay(0.22)
	tw.tween_property(lbl, "theme_override_colors/font_color", UI_THEME.TEXT, 0.45)

# A copy of the chosen card flying from the reel into its stat row, so the upgrade visibly
# "lands" on the number it changes rather than just vanishing.
func _fly_card_to_stat(key: String, tint: Color, icon: String) -> void:
	var lbl: Label = _stat_value_labels.get(key)
	if lbl == null or not is_instance_valid(lbl) or _reward_popup == null:
		return
	var ghost := Label.new()
	ghost.text = icon
	ghost.add_theme_font_size_override("font_size", 30)
	ghost.add_theme_color_override("font_color", tint)
	ghost.z_index = 50
	_reward_popup.add_child(ghost)
	var start: Vector2 = _uc_stage.global_position + _uc_stage.size * 0.5
	var end: Vector2 = lbl.global_position + lbl.size * 0.5
	ghost.global_position = start
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "global_position", end, 0.42) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(ghost, "scale", Vector2(0.5, 0.5), 0.42)
	tw.tween_callback(ghost.queue_free)
