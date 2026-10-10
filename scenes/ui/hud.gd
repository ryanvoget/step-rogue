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
@onready var _artifact_row:  HBoxContainer = $ArtifactRow

var _coin_label: Label = null # running gold total, shown after the equipped-item icons
var _damage_flash: ColorRect = null # full-screen red flash pulsed when the player takes damage
var _prev_hp := 0 # last seen player HP, to detect a drop (a hit) in _on_health

func _ready() -> void:
	_build_status_bar()
	GameManager.health_changed.connect(_on_health)
	GameManager.floor_changed.connect(_on_floor)
	GameManager.room_cleared.connect(_on_room_cleared)
	GameManager.player_died.connect(_on_died)
	$BtnMenu.pressed.connect(_on_menu_pressed)
	$StartOverlay/BtnStart.pressed.connect(_on_start_pressed)
	_health_bar.max_value = 150
	_health_bar.value     = 150
	# Shield bar fill is recoloured per shield type in _process; give it a dark track too.
	_shield_fill = StyleBoxFlat.new()
	_shield_fill.set_corner_radius_all(3)
	_shield_bar.add_theme_stylebox_override("fill", _shield_fill)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.05, 0.07, 0.11, 0.85)
	track.set_corner_radius_all(3)
	_shield_bar.add_theme_stylebox_override("background", track)
	# Full-screen red "you got hit" flash (starts invisible; pulsed in flash_damage on an HP drop).
	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(0.9, 0.06, 0.06)
	_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_flash.modulate = Color(1, 1, 1, 0)
	add_child(_damage_flash)
	refresh_equipped_icons()
	refresh_artifact_icons()

# Pulses the red screen flash — a brief, low-alpha sting that fades out fast.
func flash_damage() -> void:
	if _damage_flash == null:
		return
	_damage_flash.modulate = Color(1, 1, 1, 0.34)
	var tw := create_tween()
	tw.tween_property(_damage_flash, "modulate:a", 0.0, 0.35)

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
	_coin_label.add_theme_font_size_override("font_size", 19)
	_coin_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	_coin_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_coin_label.add_theme_constant_override("outline_size", 5)
	_coin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_equipped_row.add_child(_coin_label)

# Rarity-tinted background for an artifact chip in the top-right row.
const _ARTIFACT_TINT := {
	"common":    Color(0.20, 0.20, 0.25, 0.9),
	"uncommon":  Color(0.10, 0.30, 0.14, 0.9),
	"rare":      Color(0.10, 0.16, 0.42, 0.9),
	"epic":      Color(0.28, 0.10, 0.40, 0.9),
	"legendary": Color(0.42, 0.32, 0.04, 0.9),
}

# Rebuilds the top-right active-artifact icons from GameManager.run_artifacts (mirrors the top-left
# equipped-item row). Called at run start and after every artifact change (world.gd's
# _apply_active_artifacts). Artifacts stack, so the same icon can appear more than once.
func refresh_artifact_icons() -> void:
	if _artifact_row == null:
		return
	for c in _artifact_row.get_children():
		c.free() # immediate so the row never briefly shows the old + new set together
	for art in GameManager.run_artifacts:
		var bg := ColorRect.new()
		bg.custom_minimum_size = Vector2(26, 26)
		bg.color = _ARTIFACT_TINT.get(art.get("rarity", ""), Color(0.08, 0.1, 0.15, 0.85))
		var file: String = art.get("file", "")
		if file != "":
			var tex := TextureRect.new()
			tex.set_anchors_preset(Control.PRESET_FULL_RECT)
			tex.texture      = load("res://assets/icons/" + file)
			tex.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			bg.add_child(tex)
		_artifact_row.add_child(bg)
	_refresh_divider()

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
	if current < _prev_hp:
		flash_damage() # HP dropped → the player was hit
	_prev_hp = current
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


# ── Top status bar ───────────────────────────────────────────────────────────────────────────
# Floor, equipped loadout, gold and active artifacts all live in ONE glass panel centred at the
# top, instead of a left-pinned row and a right-pinned row. Pinning them to opposite corners meant
# that on a wide screen the two halves sat far apart in the periphery; a single centred group sits
# where the player is already looking. Sizes to its content, so it stays compact early in a run and
# grows only as artifacts are picked up.
const T := preload("res://scenes/ui/ui_theme.gd")
const BAR_FILL   := Color(0.047, 0.098, 0.141, 0.82) # UITheme.PANEL_GLASS
const BAR_BORDER := Color(0.373, 0.847, 0.961, 0.45) # UITheme.CYAN at panel strength

func _build_status_bar() -> void:
	var top_row: Control = $TopRow
	var artifacts: Control = $ArtifactRow

	var bar := PanelContainer.new()
	bar.name = "StatusBar"
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.offset_top = 6.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_END
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = BAR_FILL
	sb.border_color = BAR_BORDER
	sb.set_border_width_all(1)
	sb.border_width_top = 2 # the lit emitter edge every holo panel carries
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(T.CYAN, 0.18)
	sb.shadow_size = 7
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	bar.add_theme_stylebox_override("panel", sb)
	# Slides down into place on run start rather than popping in.
	bar.modulate.a = 0.0
	var tw := bar.create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(bar, "modulate:a", 1.0, 0.4)
	add_child(bar)
	move_child(bar, 0) # behind the popups/overlays that sit on this layer

	# Reparent the existing rows so every @onready reference above stays valid.
	top_row.get_parent().remove_child(top_row)
	top_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	top_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top_row.add_theme_constant_override("separation", 10)
	bar.add_child(top_row)

	artifacts.get_parent().remove_child(artifacts)
	artifacts.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	artifacts.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_row.add_child(artifacts) # artifacts now trail the gold count in the same group

	# Thin divider between the loadout/gold group and the artifacts, so the bar reads as
	# two sections rather than one long strip of icons.
	var sep := VSeparator.new()
	sep.add_theme_constant_override("separation", 10)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(sep)
	top_row.move_child(sep, artifacts.get_index())
	artifacts.set_meta("divider", sep)
	_refresh_divider()

# The divider is only meaningful when there is something on both sides of it.
func _refresh_divider() -> void:
	var artifacts: Control = $StatusBar/TopRow/ArtifactRow if has_node("StatusBar/TopRow/ArtifactRow") else null
	if artifacts == null or not artifacts.has_meta("divider"):
		return
	var sep: Control = artifacts.get_meta("divider")
	if is_instance_valid(sep):
		sep.visible = artifacts.get_child_count() > 0
