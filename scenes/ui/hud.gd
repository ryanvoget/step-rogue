extends CanvasLayer

signal game_started

const GAME_OVER := preload("res://scenes/ui/game_over.gd")

@onready var _health_bar:    ProgressBar  = $PlayerHealthBar
@onready var _hp_label:      Label        = $PlayerHealthLabel
@onready var _shield_bar:    ProgressBar  = $ShieldBar
@onready var _shield_label:  Label        = $ShieldLabel
var _shield_fill: StyleBoxFlat = null # tinted to the active shield's colour in _process
@onready var _floor_label:   Label        = $TopRow/FloorLabel
@onready var _grenade_label: Label        = $TopRow/GrenadeLabel
@onready var _turret_label:  Label        = $TopRow/TurretLabel
@onready var _battery_label: Label        = $TopRow/BatteryLabel
@onready var _mine_label:    Label        = $TopRow/MineLabel
@onready var _hoverboard_label: Label     = $HoverboardLabel
@onready var _cleared_label: Label        = $ClearedLabel
@onready var _start_overlay: Control      = $StartOverlay
@onready var _equipped_row:  HBoxContainer = $TopRow/EquippedRow

var _coin_label: Label = null # running gold total, shown after the equipped-item icons

func _ready() -> void:
	GameManager.health_changed.connect(_on_health)
	GameManager.floor_changed.connect(_on_floor)
	GameManager.room_cleared.connect(_on_room_cleared)
	GameManager.player_died.connect(_on_died)
	$BtnMenu.pressed.connect(_on_menu_pressed)
	$StartOverlay/BtnStart.pressed.connect(_on_start_pressed)
	_health_bar.max_value = 100
	_health_bar.value     = 100
	# Shield bar fill is recoloured per shield type in _process; give it a dark track too.
	_shield_fill = StyleBoxFlat.new()
	_shield_fill.set_corner_radius_all(3)
	_shield_bar.add_theme_stylebox_override("fill", _shield_fill)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.05, 0.07, 0.11, 0.85)
	track.set_corner_radius_all(3)
	_shield_bar.add_theme_stylebox_override("background", track)
	refresh_equipped_icons()

# Rebuilds the top-left equipped-item icons + coin label from the current SaveManager slots.
# Called at start and again after an in-run crate swap (world.gd) so the icon up top reflects
# the item the player chose to equip.
func refresh_equipped_icons() -> void:
	for c in _equipped_row.get_children():
		c.free() # immediate (not queue_free) so the row doesn't briefly show old + new side by side
	_coin_label = null
	for key in ["equipped_weapon", "equipped_equipment", "equipped_defensive"]:
		var item: Dictionary = SaveManager.get_slot(key)
		var slot_bg := ColorRect.new()
		slot_bg.custom_minimum_size = Vector2(24, 24)
		slot_bg.color = Color(0.08, 0.1, 0.15, 0.85)
		if not item.is_empty():
			var tex_rect := TextureRect.new()
			tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			tex_rect.texture      = load("res://assets/icons/" + item["file"])
			tex_rect.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			slot_bg.add_child(tex_rect)
		_equipped_row.add_child(slot_bg)
	# Coin total, shown right after the equipped-item slots.
	_coin_label = Label.new()
	_coin_label.add_theme_font_size_override("font_size", 15)
	_coin_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2))
	_coin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_equipped_row.add_child(_coin_label)

func _on_start_pressed() -> void:
	_start_overlay.visible = false
	game_started.emit()

func _process(_delta: float) -> void:
	_coin_label.text = "🪙 %d" % GameManager.coins
	# Grenade throwables show a remaining-uses counter; everything else hides it (polled here so
	# it stays right after a mid-run crate swap re-runs world.gd's _apply_loadout).
	if GameManager.equipment_is_grenade:
		_grenade_label.visible = true
		_grenade_label.text = "🧨 %d" % GameManager.grenade_charges
	else:
		_grenade_label.visible = false
	# Turret deploys remaining, shown while a placeable turret is equipped.
	if GameManager.equipment_placeable:
		_turret_label.visible = true
		_turret_label.text = "🔧 %d" % GameManager.placeable_charges
	else:
		_turret_label.visible = false
	# Speed Boost Battery uses a recharge model now (no fixed charge count) — its state is shown by
	# the button/recharge bar in mobile_controls, so no HUD charge label.
	_battery_label.visible = false
	# Detonator Mine uses remaining.
	if GameManager.equipment_mine:
		_mine_label.visible = true
		_mine_label.text = "💣 %d" % GameManager.mine_charges
	else:
		_mine_label.visible = false
	# Hoverboard remaining-rooms counter, shown only while a hoverboard is equipped.
	if GameManager.equipment_hoverboard:
		_hoverboard_label.visible = true
		_hoverboard_label.text = "🛹 Hoverboard: %d" % GameManager.hoverboard_rooms_remaining
	else:
		_hoverboard_label.visible = false
	# Shield HP bar above the health bar — visible while a shield is equipped and unbroken,
	# tinted to the shield type's colour.
	if GameManager.shield_equipped and not GameManager.shield_broken and GameManager.shield_hp_max > 0.0:
		_shield_bar.visible = true
		_shield_label.visible = true
		_shield_bar.max_value = GameManager.shield_hp_max
		_shield_bar.value = GameManager.shield_hp
		_shield_fill.bg_color = GameManager.shield_color
		_shield_label.text = "🛡 %d / %d" % [int(round(GameManager.shield_hp)), int(round(GameManager.shield_hp_max))]
	else:
		_shield_bar.visible = false
		_shield_label.visible = false

func _on_health(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value     = current
	_hp_label.text = "%d / %d" % [current, maximum]

func _on_floor(num: int) -> void:
	_floor_label.text = "Floor %d" % num
	_cleared_label.visible = false

func _on_room_cleared() -> void:
	_cleared_label.visible = true

func _on_died() -> void:
	await get_tree().create_timer(1.4).timeout
	# Game-over / statistics overlay on its own high CanvasLayer so it sits above the joystick
	# layer (20). ui_popup_open stops the mobile controls from acting while it's up.
	GameManager.ui_popup_open = true
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.add_child(GAME_OVER.new())
	add_child(layer)

func _on_menu_pressed() -> void:
	GameManager.current_floor = 1
	GameManager.coins = 0
	SceneManager.go_to_menu()
