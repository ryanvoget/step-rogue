extends Node2D

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE  := preload("res://scenes/enemies/enemy_basic.tscn")
const BULLET_SCENE := preload("res://scenes/bullets/bullet.tscn")
const TURRET_SCENE := preload("res://scenes/turret/turret.tscn")
const GRENADE_SCENE := preload("res://scenes/grenade/grenade.tscn")
const BARRIER_SCENE := preload("res://scenes/barrier_wall/barrier_wall.tscn")
const SIDEKICK_SCENE := preload("res://scenes/sidekick_robot/sidekick_robot.tscn")
const DENNIS_SCENE := preload("res://scenes/dennis/dennis.tscn")
const HEAL_DISPENSER_SCENE := preload("res://scenes/heal_dispenser/heal_dispenser.tscn")

@onready var _room:    Node2D = $Room
@onready var _bullets: Node   = $Bullets

const TYPE_ORDER := ["all", "weapon", "equipment", "defensive"]
const TYPE_LABELS := {
	"all":       "All",
	"weapon":    "Weapon",
	"equipment": "Equipment",
	"defensive": "Defense",
}

# Mirrors enemy_basic.gd's SandboxAction enum order — kept as plain strings here since the
# dropdown just needs labels, not the enum itself.
const ENEMY_ACTION_LABELS := ["Neutral", "Moving", "Attacking", "Shooting"]

var _player: CharacterBody2D = null
var _filtered_items: Array = []
var _current_item: Dictionary = {}
var _dummy: CharacterBody2D = null
var _enemy_action: int = 0 # index into ENEMY_ACTION_LABELS / enemy_basic.gd's SandboxAction
var _enemy_hp: int = 10
var _placed_mine: Node2D = null
var _active_barrier: Node2D = null
var _active_sidekick: Node2D = null
var _active_dennis: Node2D = null
var _active_dispenser: Node2D = null
var _boss_fight_active := false # true once a boss fight is started — stops the dummy respawning

func _ready() -> void:
	GameManager.register_bullets_container(_bullets)
	GameManager.deploy_equipment_requested.connect(_use_equipment)
	GameManager.heal_item_requested.connect(_use_heal_item)
	GameManager.battery_activate_requested.connect(_use_battery)
	_spawn_player()
	_spawn_dummy()
	$HUD/BtnMenu.pressed.connect(_on_menu_pressed)
	_setup_item_picker()
	_setup_enemy_picker()
	_setup_boss_fight_button()
	if OS.has_feature("ios") or OS.has_feature("android") or OS.has_feature("editor"):
		add_child(preload("res://scenes/ui/mobile_controls.tscn").instantiate())

# Dev-only controls: pick how the test dummy behaves (still, patrolling, chasing/attacking
# like a real enemy, or shooting straight down) and how much HP it has, so weapon damage can
# be tested against different scenarios without leaving the sandbox.
func _setup_enemy_picker() -> void:
	var action_dropdown: OptionButton = $HUD/EnemyPicker/ActionDropdown
	for label in ENEMY_ACTION_LABELS:
		action_dropdown.add_item(label)
	action_dropdown.selected = _enemy_action
	action_dropdown.item_selected.connect(_on_enemy_action_selected)

	var hp_slider: HSlider = $HUD/EnemyPicker/HpSlider
	hp_slider.value = _enemy_hp
	hp_slider.value_changed.connect(_on_enemy_hp_changed)

func _on_enemy_action_selected(index: int) -> void:
	_enemy_action = index
	if _dummy and is_instance_valid(_dummy):
		_dummy.sandbox_action = _enemy_action

func _on_enemy_hp_changed(value: float) -> void:
	_enemy_hp = int(value)
	$HUD/EnemyPicker/HpLabel.text = "%d HP" % _enemy_hp
	if _dummy and is_instance_valid(_dummy):
		_dummy.max_health = _enemy_hp
		_dummy.health = _enemy_hp
		_dummy.queue_redraw()

# Dev-only dropdown: pick any ItemRegistry item (optionally narrowed by type) to
# test how it looks/plays as the player's equipped weapon, one at a time. Defaults
# to the assault rifle so the sandbox looks the same as before until you change it.
func _setup_item_picker() -> void:
	var type_filter: OptionButton = $HUD/ItemPicker/TypeFilter
	for type_key in TYPE_ORDER:
		type_filter.add_item(TYPE_LABELS[type_key])
	type_filter.selected = 0
	type_filter.item_selected.connect(_on_type_filter_selected)

	var dropdown: OptionButton = $HUD/ItemPicker/ItemDropdown
	dropdown.item_selected.connect(_on_item_selected)

	_rebuild_item_dropdown("all", "Assault Rifle Blaster")

func _on_type_filter_selected(index: int) -> void:
	_rebuild_item_dropdown(TYPE_ORDER[index])

func _rebuild_item_dropdown(type_key: String, prefer_name: String = "") -> void:
	_filtered_items = ItemRegistry.ITEMS if type_key == "all" \
		else ItemRegistry.ITEMS.filter(func(i): return i["type"] == type_key)
	if _filtered_items.is_empty():
		return

	var dropdown: OptionButton = $HUD/ItemPicker/ItemDropdown
	dropdown.clear()
	var default_idx := 0
	for i in range(_filtered_items.size()):
		var item: Dictionary = _filtered_items[i]
		dropdown.add_item("%s (%s)" % [item["name"], item["rarity"].capitalize()])
		if item["name"] == prefer_name:
			default_idx = i
	dropdown.selected = default_idx
	_on_item_selected(default_idx)

func _on_item_selected(index: int) -> void:
	var item: Dictionary = _filtered_items[index]
	_current_item = item
	var icon: TextureRect = $HUD/ItemPicker/EquippedIcon
	icon.texture = load("res://assets/icons/" + item["file"])
	if _player:
		ItemRegistry.equip_on_player(_player, item)
	# Mirrors world.gd's real-run wiring so mobile_controls' deploy button shows up
	# for placeable/throwable equipment (e.g. Turret, Blast Grenade) picked from the dropdown.
	GameManager.equipment_placeable = item.get("placeable", false)
	GameManager.equipment_throwable = item.get("throwable", false)
	GameManager.equipment_grapple   = item.get("grapple", false)
	GameManager.equipment_aim_preview = item.get("aim_preview", false)
	GameManager.aim_preview_max_distance = item.get("throw_distance", 1200.0)
	GameManager.aim_preview_active = false # don't inherit a stale "touching" state if switched mid-drag
	GameManager.aim_preview_fraction = 0.0
	GameManager.equipment_scaleable_throw = item.get("scaleable_throw", false)
	GameManager.equipment_deployed  = false
	GameManager.heal_item_equipped  = item.get("heal_item", false)
	GameManager.heal_item_deployed  = false
	GameManager.shield_equipped = item.get("shield", false)
	if _player:
		# Always reset (regardless of whether the new item is shield-type), so switching away
		# from an active/broken shield mid-test can't leave stale state behind.
		var shield_hp: float = item["block"] if item.get("block") != null else 10.0
		var scol := Color(1.0, 0.72, 0.2) if item.get("shield_reflect", false) \
			else (Color(0.40, 0.85, 1.0) if shield_hp <= 10.0 else (Color(0.35, 0.50, 1.0) if shield_hp <= 25.0 else Color(0.62, 0.42, 1.0)))
		GameManager.shield_color = scol
		_player.configure_shield(shield_hp, item.get("shield_reflect", false), scol)
	GameManager.equipment_battery   = item.get("battery", false)
	if GameManager.equipment_battery and _player:
		_player.configure_battery(item.get("speed_boost_multiplier", 1.5),
			item.get("battery_active_duration", 10.0), item.get("battery_recharge_duration", 10.0))
	GameManager.equipment_mine = item.get("mine", false)
	GameManager.mine_state = GameManager.MINE_READY
	if _placed_mine != null and is_instance_valid(_placed_mine):
		_placed_mine.queue_free()
	_placed_mine = null
	GameManager.equipment_force_push = item.get("force_push", false)
	GameManager.force_push_held = false
	GameManager.force_push_dir = Vector2.ZERO
	if GameManager.equipment_force_push and _player:
		_player.configure_force_push(item.get("force_push_range", 192.0), item.get("force_push_arc_degrees", 100.0),
			item.get("force_push_mana_max", 100.0), item.get("force_push_mana_drain_rate", 10.0))
	GameManager.equipment_barrier = item.get("barrier", false)
	GameManager.barrier_state = GameManager.BARRIER_READY
	if _active_barrier != null and is_instance_valid(_active_barrier):
		_active_barrier.queue_free()
	_active_barrier = null
	GameManager.equipment_hoverboard = item.get("hoverboard", false)
	if _player:
		if GameManager.equipment_hoverboard:
			var hb_tex: Texture2D = load("res://assets/icons/" + item["file"])
			_player.configure_hoverboard(hb_tex, item.get("hoverboard_speed_multiplier", 1.5))
		else:
			# Switched away from a hoverboard item — force-dismount so the sprite/speed boost
			# from the PREVIOUS item don't linger (configure_hoverboard with a null texture
			# just resets state without touching the sprite's texture/scale).
			_player.configure_hoverboard(null, 1.5)
	GameManager.equipment_teleport = item.get("teleport", false)
	GameManager.equipment_invincible = item.get("invincible", false)
	if _player:
		# Always reset (regardless of whether the new item is invincible-type), so switching
		# away from an active Invincible Battery mid-test can't leave _invincible_active stuck
		# true with no way to turn it off.
		_player.configure_invincible(item.get("invincible_mana_max", 100.0), item.get("invincible_mana_drain_rate", 10.0))
	if _active_sidekick != null and is_instance_valid(_active_sidekick):
		_active_sidekick.queue_free()
	_active_sidekick = null
	if item.get("sidekick", false) and _player:
		_active_sidekick = SIDEKICK_SCENE.instantiate()
		add_child(_active_sidekick)
		var sk_tex: Texture2D = load("res://assets/icons/" + item["file"])
		_active_sidekick.configure(sk_tex, item["damage"], item["fire_rate"], item["bullet_speed"], _player)
	GameManager.equipment_summon = item.get("summon", false)
	GameManager.summon_label = item.get("summon_label", "SUMMON")
	if _active_dennis != null and is_instance_valid(_active_dennis):
		_active_dennis.queue_free()
	_active_dennis = null
	if _active_dispenser != null and is_instance_valid(_active_dispenser):
		_active_dispenser.queue_free()
	_active_dispenser = null

# Same dispatch as world.gd::_use_equipment, but acts on whatever's currently picked in the
# dev dropdown instead of SaveManager.equipped_equipment. Turrets stay one-per-selection
# (re-picking the item resets equipment_deployed above); throwables intentionally never set
# equipment_deployed here so you can lob as many test grenades as you want.
func _use_equipment(angle: float, throw_fraction: float = 1.0) -> void:
	if _current_item.is_empty():
		return
	if _current_item.get("placeable", false):
		if GameManager.equipment_deployed:
			return
		GameManager.equipment_deployed = true
		_deploy_turret(_current_item)
	elif _current_item.get("grapple", false):
		_use_grapple(angle, throw_fraction)
	elif _current_item.get("sticky", false):
		_use_sticky_grenade(_current_item, angle, throw_fraction)
	elif _current_item.get("teleport", false):
		_use_teleport(_current_item, angle, throw_fraction)
	elif _current_item.get("throwable", false):
		_throw_grenade(_current_item, angle, throw_fraction)
	elif _current_item.get("mine", false):
		_use_mine(_current_item)
	elif _current_item.get("barrier", false):
		_use_barrier(_current_item)
	elif _current_item.get("hoverboard", false):
		if _player:
			_player.toggle_hoverboard()
	elif _current_item.get("invincible", false):
		if _player:
			_player.toggle_invincible()
	elif _current_item.get("summon", false):
		if GameManager.equipment_deployed:
			return
		GameManager.equipment_deployed = true
		_summon_dennis(_current_item)

# Same dispatch as world.gd::_spawn_dennis, but tracks _active_dennis so re-picking the item
# frees the previous test summon instead of piling them up (see _on_item_selected).
func _summon_dennis(item: Dictionary) -> void:
	if _player == null:
		return
	var stats: Dictionary = ItemRegistry.get_item_by_name("Assault Rifle Blaster")
	var dmg: int = stats["damage"] if stats.get("damage") != null else 1
	var rate: float = stats["fire_rate"] if stats.get("fire_rate") != null else 0.0625
	var bspeed: float = stats["bullet_speed"] if stats.get("bullet_speed") != null else 520.0
	_active_dennis = DENNIS_SCENE.instantiate()
	add_child(_active_dennis)
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	_active_dennis.configure(tex, dmg, rate, bspeed, _player.global_position)

# Same dispatch as world.gd::_use_grapple, but doesn't set equipment_deployed — like the
# throwable grenade, grapple is unlimited-use in sandbox for repeat testing.
func _use_grapple(angle: float, throw_fraction: float = 1.0) -> void:
	if _player == null:
		return
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

# Same dispatch as world.gd::_use_teleport, unlimited-use in sandbox like other throwables/grapple.
func _use_teleport(item: Dictionary, angle: float, throw_fraction: float = 1.0) -> void:
	if _player == null:
		return
	var direction := Vector2.RIGHT.rotated(angle)
	var max_distance: float = item.get("throw_distance", 1200.0)
	if item.get("scaleable_throw", false):
		# Squared, not linear — matches player.gd's TELEPORT_SENSITIVITY_CURVE in
		# _draw_teleport_preview, so release always lands exactly where the dotted circle showed.
		max_distance *= pow(clampf(throw_fraction, 0.0, 1.0), 2.0)
	var target: Vector2 = _player.get_teleport_target(direction, max_distance)
	_player.teleport_to(target)

# Same dispatch as world.gd::_use_sticky_grenade, unlimited-use in sandbox like other
# throwables/grapple.
func _use_sticky_grenade(item: Dictionary, angle: float, throw_fraction: float = 1.0) -> void:
	if _player == null:
		return
	var direction := Vector2.RIGHT.rotated(angle)
	var max_distance: float = item["throw_distance"]
	if item.get("scaleable_throw", false):
		max_distance *= clampf(throw_fraction, 0.0, 1.0)
	var target: Dictionary = _player.get_aim_target(direction, max_distance)
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	var origin: Vector2 = _player.global_position
	var grenade: Node2D = GRENADE_SCENE.instantiate()
	add_child(grenade)
	if target["is_enemy"]:
		grenade.configure_stick(tex, origin, target["collider"], item["sticky_damage"], item["sticky_delay"])
	else:
		grenade.configure(tex, origin, target["position"], item["damage"], item["aoe_radius"], item["explode_delay"])

func _deploy_turret(item: Dictionary) -> void:
	var turret: Node2D = TURRET_SCENE.instantiate()
	add_child(turret)
	turret.global_position = _player.global_position
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	turret.configure(tex, item["damage"], item["fire_rate"], item["bullet_speed"])

func _throw_grenade(item: Dictionary, angle: float, throw_fraction: float = 1.0) -> void:
	var grenade: Node2D = GRENADE_SCENE.instantiate()
	add_child(grenade)
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	var origin: Vector2 = _player.global_position
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

# Same dispatch as world.gd::_use_mine, but doesn't set equipment_deployed on detonation —
# like the throwable grenade/grapple, mine is unlimited-use in sandbox for repeat testing.
func _use_mine(item: Dictionary) -> void:
	if _player == null:
		return
	if GameManager.mine_state == GameManager.MINE_READY:
		var tex: Texture2D = load("res://assets/icons/" + item["file"])
		_placed_mine = GRENADE_SCENE.instantiate()
		add_child(_placed_mine)
		_placed_mine.configure_mine(tex, _player.global_position, item["damage"], item["aoe_radius"])
		GameManager.mine_state = GameManager.MINE_ARMED
	else:
		if _placed_mine != null and is_instance_valid(_placed_mine):
			_placed_mine.detonate()
		_placed_mine = null
		GameManager.mine_state = GameManager.MINE_READY

# Same dispatch as world.gd::_use_barrier, but doesn't set equipment_deployed on finish — like
# the throwable grenade/mine, unlimited-use in sandbox for repeat testing.
func _use_barrier(item: Dictionary) -> void:
	if _player == null:
		return
	if GameManager.barrier_state == GameManager.BARRIER_READY:
		_active_barrier = BARRIER_SCENE.instantiate()
		add_child(_active_barrier)
		_active_barrier.finished.connect(_on_barrier_finished)
		_active_barrier.start(_player, item.get("barrier_max_length", 200.0), item.get("barrier_thickness", 12.0))
		GameManager.barrier_state = GameManager.BARRIER_PLACING
	elif _active_barrier != null and is_instance_valid(_active_barrier):
		_active_barrier.stop_and_finalize()

func _on_barrier_finished() -> void:
	_active_barrier = null
	GameManager.barrier_state = GameManager.BARRIER_READY

# Same dispatch as world.gd::_use_heal_item, but acts on whatever's currently picked in the
# dev dropdown instead of SaveManager.equipped_defensive, and — like the throwable grenade —
# intentionally never sets heal_item_deployed, so you can test heal/regen/speed-boost effects
# as many times as you want without needing to re-pick the item each time.
func _use_heal_item() -> void:
	if _current_item.is_empty() or not _current_item.get("heal_item", false) or _player == null:
		return
	if _current_item.get("heal_full", false):
		_player.heal_full()
	elif _current_item.get("heal_instant") != null:
		_player.heal(_current_item["heal_instant"])
	if _current_item.get("heal_regen_amount") != null:
		_player.start_regen(_current_item["heal_regen_amount"], _current_item.get("heal_regen_interval", 1.0), _current_item["heal_regen_duration"])
	if _current_item.get("speed_boost_multiplier") != null:
		_player.apply_speed_boost(_current_item["speed_boost_multiplier"], _current_item.get("speed_boost_duration", 0.0))
	if _current_item.get("heal_dispenser", false):
		_spawn_heal_dispenser(_current_item)
	if _current_item.get("shield", false):
		_player.toggle_shield()

# Same dispatch as world.gd::_spawn_heal_dispenser, but tracks _active_dispenser so re-testing
# frees the previous one instead of piling them up (see _on_item_selected).
func _spawn_heal_dispenser(item: Dictionary) -> void:
	if _active_dispenser != null and is_instance_valid(_active_dispenser):
		_active_dispenser.queue_free()
	_active_dispenser = HEAL_DISPENSER_SCENE.instantiate()
	add_child(_active_dispenser)
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	_active_dispenser.configure(tex, _player.global_position, item.get("dispenser_interval", 5.0),
		item.get("dispenser_duration", 20.0), item.get("dispenser_heal_amount", 5))

# Same dispatch as world.gd::_use_battery — repeatable indefinitely (see item_registry.gd's
# battery field docs), so unlike the placeable/throwable/heal-item flows above there's no
# unlimited-use special-casing needed here; the ready/active/recharging cycle already allows it.
func _use_battery() -> void:
	if _player:
		_player.activate_battery()

func _spawn_player() -> void:
	var p: CharacterBody2D = PLAYER_SCENE.instantiate()
	p.bullet_scene = BULLET_SCENE
	add_child(p)
	p.global_position = _room.player_spawn_pos
	_player = p
	var cam := Camera2D.new()
	cam.position = Vector2(GameManager.room_w * 0.5, GameManager.room_h * 0.5)
	add_child(cam)
	cam.make_current()
	p.health_changed.connect(_on_player_health_changed)
	p.died.connect(_on_player_died)
	_on_player_health_changed(p.health, p.max_health)
	# Re-apply whatever's currently picked in the item dropdown (relevant on respawn — a
	# fresh player would otherwise default back to the plain assault rifle look).
	if not _current_item.is_empty():
		ItemRegistry.equip_on_player(p, _current_item)

# The "Attacking"/"Shooting" enemy actions can now genuinely kill the player (melee damage or
# lasers), which player.gd normally handles by queue_free()-ing the node — nothing was
# watching for that in sandbox, so testing would silently break (no player left to control
# or re-equip weapons on). Just respawn, like the dummy already does on death.
func _on_player_died() -> void:
	_player = null
	await get_tree().create_timer(DUMMY_RESPAWN_DELAY).timeout
	_spawn_player()

func _on_player_health_changed(current: int, maximum: int) -> void:
	var bar: ProgressBar = $HUD/PlayerHealthBar
	bar.max_value = maximum
	bar.value = current
	$HUD/PlayerHealthLabel.text = "%d / %d" % [current, maximum]

const DUMMY_RESPAWN_DELAY := 0.5 # gives one-shot kills a beat to be visible before the dummy resets
# room.gd's enemy_spawn_positions[0] (y=120) sits right under the EnemyPicker HUD row (which
# extends to ~y134) — override just the dummy's spawn Y here rather than touching the shared
# room spawn points real gameplay also uses.
const DUMMY_SPAWN_Y := 200.0

# Dev-only "Boss Fight" button (top-right): pick a boss to spawn into the sandbox and test it with
# the currently selected loadout.
func _setup_boss_fight_button() -> void:
	var b := Button.new()
	b.text = "👹 Boss Fight"
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = -130.0
	b.offset_right = -10.0
	b.offset_top = 52.0
	b.offset_bottom = 86.0
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(_show_boss_picker)
	$HUD.add_child(b)

func _show_boss_picker() -> void:
	GameManager.ui_popup_open = true # pauses the mobile joysticks so the picker gets the taps
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	$HUD.add_child(overlay)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	overlay.add_child(dim)
	var panel := VBoxContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -115.0
	panel.offset_right = 115.0
	panel.offset_top = -150.0
	panel.offset_bottom = 150.0
	panel.add_theme_constant_override("separation", 10)
	overlay.add_child(panel)
	var title := Label.new()
	title.text = "Fight which boss?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	for opt in [["Boss1", "🗡  Boss 1"], ["Boss2", "🔫  Boss 2"], ["BossF_P1", "☠  Final — Phase 1"], ["BossF_P2", "☠  Final — Phase 2"]]:
		var btn := Button.new()
		btn.text = opt[1]
		btn.custom_minimum_size = Vector2(0, 46)
		btn.pressed.connect(func():
			GameManager.ui_popup_open = false
			overlay.queue_free()
			_start_boss_fight(opt[0]))
		panel.add_child(btn)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 40)
	cancel.pressed.connect(func():
		GameManager.ui_popup_open = false
		overlay.queue_free())
	panel.add_child(cancel)

func _start_boss_fight(kind: String) -> void:
	GameManager.ui_popup_open = false
	AudioManager.stop_boss_music() # clear any music left from a previous boss test
	_boss_fight_active = true # keep the dummy from respawning during the fight
	if _dummy != null and is_instance_valid(_dummy):
		_dummy.queue_free()
	_dummy = null
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			n.queue_free()
	# The final boss's two phases are separately selectable here, each with its own "I Got Soda"
	# section. Phase 1 = the 1000-HP boss (phase-1 music); phase 2 = the 500-HP splitting boss
	# (phase-2 music). Both restore the background music + dummy once cleared.
	match kind:
		"BossF_P1":
			AudioManager.start_boss_music_phase1()
			var e: CharacterBody2D = ENEMY_SCENE.instantiate()
			e.configure_type("BossF") # 1000 HP, no split
			e.global_position = GameManager.play_rect.get_center()
			e.died.connect(_on_sandbox_final_phase2_died) # restores when cleared
			add_child(e)
		"BossF_P2":
			_sandbox_final_phase2()
		_:
			var e: CharacterBody2D = ENEMY_SCENE.instantiate()
			e.configure_type(kind)
			e.global_position = GameManager.play_rect.get_center()
			add_child(e)

func _sandbox_final_phase2() -> void:
	AudioManager.start_boss_music_phase2()
	_spawn_sandbox_final_boss(500, 75.0, GameManager.play_rect.get_center(), 0)

func _on_sandbox_boss_split(pos: Vector2, hp: int, radius: float, generation: int) -> void:
	if get_tree().get_nodes_in_group("enemies").size() >= 8:
		return
	_spawn_sandbox_final_boss(hp, radius, pos + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * 70.0, generation)

func _spawn_sandbox_final_boss(hp: int, radius: float, pos: Vector2, generation: int) -> void:
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	e.configure_type("BossF")
	e.max_health = hp
	e._radius = radius
	e._split_generation = generation
	e.enable_boss_split()
	e.boss_split.connect(_on_sandbox_boss_split)
	e.died.connect(_on_sandbox_final_phase2_died)
	e.global_position = pos
	add_child(e)

# When the last phase-2 boss/split is gone, restore the background music and bring the dummy back.
func _on_sandbox_final_phase2_died() -> void:
	call_deferred("_check_final_boss_cleared")

func _check_final_boss_cleared() -> void:
	if get_tree().get_nodes_in_group("enemies").is_empty():
		AudioManager.stop_boss_music()
		_boss_fight_active = false
		_spawn_dummy()

func _spawn_dummy(delay: float = 0.0) -> void:
	if _boss_fight_active:
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if _boss_fight_active:
		return
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	e.sandbox_mode = true
	e.sandbox_action = _enemy_action
	e.max_health = _enemy_hp
	e.global_position = Vector2(_room.enemy_spawn_positions[0].x, DUMMY_SPAWN_Y)
	e.died.connect(_spawn_dummy.bind(DUMMY_RESPAWN_DELAY))
	add_child(e)
	_dummy = e

func _on_menu_pressed() -> void:
	SceneManager.go_to_menu()

# Restore the background track if a boss-fight test left the boss music playing.
func _exit_tree() -> void:
	AudioManager.stop_boss_music()
