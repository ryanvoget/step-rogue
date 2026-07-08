extends Node2D

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE  := preload("res://scenes/enemies/enemy_basic.tscn")
const BULLET_SCENE := preload("res://scenes/bullets/bullet.tscn")
const TURRET_SCENE := preload("res://scenes/turret/turret.tscn")
const GRENADE_SCENE := preload("res://scenes/grenade/grenade.tscn")

@onready var _room:    Node2D = $Room
@onready var _bullets: Node   = $Bullets

const TYPE_ORDER := ["all", "weapon", "equipment", "heal", "defensive"]
const TYPE_LABELS := {
	"all":       "All",
	"weapon":    "Weapon",
	"equipment": "Equipment",
	"heal":      "Healing",
	"defensive": "Defense",
}

var _player: CharacterBody2D = null
var _filtered_items: Array = []
var _current_item: Dictionary = {}

func _ready() -> void:
	GameManager.register_bullets_container(_bullets)
	GameManager.deploy_equipment_requested.connect(_use_equipment)
	_spawn_player()
	_spawn_dummy()
	$HUD/BtnMenu.pressed.connect(_on_menu_pressed)
	_setup_item_picker()
	if OS.has_feature("ios") or OS.has_feature("android") or OS.has_feature("editor"):
		add_child(preload("res://scenes/ui/mobile_controls.tscn").instantiate())

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
	GameManager.equipment_deployed  = false

# Same dispatch as world.gd::_use_equipment, but acts on whatever's currently picked in the
# dev dropdown instead of SaveManager.equipped_equipment. Turrets stay one-per-selection
# (re-picking the item resets equipment_deployed above); throwables intentionally never set
# equipment_deployed here so you can lob as many test grenades as you want.
func _use_equipment(angle: float) -> void:
	if _current_item.is_empty():
		return
	if _current_item.get("placeable", false):
		if GameManager.equipment_deployed:
			return
		GameManager.equipment_deployed = true
		_deploy_turret(_current_item)
	elif _current_item.get("throwable", false):
		_throw_grenade(_current_item, angle)

func _deploy_turret(item: Dictionary) -> void:
	var turret: Node2D = TURRET_SCENE.instantiate()
	add_child(turret)
	turret.global_position = _player.global_position
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	turret.configure(tex, item["damage"], item["fire_rate"], item["bullet_speed"])

func _throw_grenade(item: Dictionary, angle: float) -> void:
	var grenade: Node2D = GRENADE_SCENE.instantiate()
	add_child(grenade)
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	var origin: Vector2 = _player.global_position
	var landing: Vector2 = origin + Vector2.RIGHT.rotated(angle) * item["throw_distance"]
	grenade.configure(tex, origin, landing, item["damage"], item["aoe_radius"], item["explode_delay"])

func _spawn_player() -> void:
	var p: CharacterBody2D = PLAYER_SCENE.instantiate()
	p.bullet_scene = BULLET_SCENE
	add_child(p)
	p.global_position = _room.player_spawn_pos
	_player = p

const DUMMY_RESPAWN_DELAY := 0.5 # gives one-shot kills a beat to be visible before the dummy resets

func _spawn_dummy(delay: float = 0.0) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	e.sandbox_mode = true
	e.global_position = _room.enemy_spawn_positions[0]
	e.died.connect(_spawn_dummy.bind(DUMMY_RESPAWN_DELAY))
	add_child(e)

func _on_menu_pressed() -> void:
	SceneManager.go_to_menu()
