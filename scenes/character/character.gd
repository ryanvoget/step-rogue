extends Control

const FRAME_W      := 64
const FRAME_H      := 64
const FRAME_COUNT  := 5
const IDLE_FPS     := 8.0
const SPRITE_SCALE := 4.55  # 7.0 * 0.65 (35% reduction)

const SHIRT_OPTIONS := [
	{ "id": "blue",   "label": "Blue",   "hue": 0.583 },
	{ "id": "red",    "label": "Red",    "hue": 0.0   },
	{ "id": "yellow", "label": "Yellow", "hue": 0.144 },
	{ "id": "green",  "label": "Green",  "hue": 0.361 },
]

const SLOTS := [
	{ "key": "equipped_weapon",    "label": "Weapon",    "empty_icon": "⚔️",  "type": "weapon"    },
	{ "key": "equipped_equipment", "label": "Equipment",  "empty_icon": "🎒",  "type": "equipment" },
	{ "key": "equipped_defensive", "label": "Defense",   "empty_icon": "🛡️",  "type": "defensive" },
]

@onready var _sprite:     AnimatedSprite2D = $PlayerSprite
@onready var _canvas:     Control          = $VBox/ContentRow/CharCanvas
@onready var _shader_mat: ShaderMaterial   = $PlayerSprite.material

var _slot_btns: Array = []

func _ready() -> void:
	$VBox/Header/BtnBack.pressed.connect(SceneManager.go_to_menu)
	_setup_sprite()
	_setup_shirt_buttons()
	_setup_slots()
	_apply_shirt(SaveManager.shirt_color)
	await get_tree().process_frame
	_reposition_sprite()

func _reposition_sprite() -> void:
	_sprite.position = _canvas.get_global_rect().get_center()

func _setup_sprite() -> void:
	var tex: Texture2D = load("res://assets/Sprites/idle_spritesheet.png")
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("idle")
	sf.set_animation_speed("idle", IDLE_FPS)
	sf.set_animation_loop("idle", true)
	for i in range(FRAME_COUNT):
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * FRAME_W, 0, FRAME_W, FRAME_H)
		sf.add_frame("idle", atlas)
	_sprite.sprite_frames = sf
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_sprite.play("idle")

func _setup_shirt_buttons() -> void:
	for option in SHIRT_OPTIONS:
		var btn := get_node("VBox/ShirtSection/ShirtPicker/Btn" + option["label"]) as Button
		btn.pressed.connect(_on_shirt_pressed.bind(option["id"]))
	_refresh_shirt_buttons()

func _setup_slots() -> void:
	for i in range(SLOTS.size()):
		var btn := get_node("VBox/ContentRow/SlotsCol/Slot" + str(i)) as Button
		_slot_btns.append(btn)
		btn.pressed.connect(_open_picker.bind(i))
		_refresh_slot(i)

func _refresh_slot(idx: int) -> void:
	var slot     = SLOTS[idx]
	var btn      = _slot_btns[idx] as Button
	var equipped: Dictionary = SaveManager.get_slot(slot["key"])
	btn.icon        = null
	btn.expand_icon = false
	if equipped.is_empty():
		btn.text = slot["empty_icon"] + "  " + slot["label"] + "\n(empty)"
	else:
		btn.text = slot["empty_icon"] + "  " + slot["label"] + "\n" + equipped["name"]

func _open_picker(slot_idx: int) -> void:
	var slot = SLOTS[slot_idx]
	var inv: Array = SaveManager.inventory.filter(
		func(item): return item.get("type", "") == slot["type"]
	)

	# Full-screen overlay
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.76)
	overlay.add_child(dim)

	# Centered panel
	var panel := PanelContainer.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -190.0
	panel.offset_right  =  190.0
	panel.offset_top    = -250.0
	panel.offset_bottom =  250.0
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
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title row
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	var title_lbl := Label.new()
	title_lbl.text = "Choose " + slot["label"]
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(overlay.queue_free)
	title_row.add_child(close_btn)

	# Unequip button if slot is filled
	var cur: Dictionary = SaveManager.get_slot(slot["key"])
	if not cur.is_empty():
		var unequip_btn := Button.new()
		unequip_btn.text = "Unequip  (" + cur["name"] + ")"
		unequip_btn.pressed.connect(_on_unequip.bind(slot_idx, overlay))
		vbox.add_child(unequip_btn)

	# Item grid or empty message
	if inv.is_empty():
		var msg := Label.new()
		msg.text = "No " + slot["label"].to_lower() + " items in your inventory yet."
		msg.add_theme_font_size_override("font_size", 14)
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(msg)
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 330)
		vbox.add_child(scroll)

		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		scroll.add_child(grid)

		for item in inv:
			var item_btn := Button.new()
			item_btn.custom_minimum_size = Vector2(98, 98)
			item_btn.icon           = load("res://assets/icons/" + item["file"])
			item_btn.expand_icon    = true
			item_btn.tooltip_text   = item["name"]
			item_btn.pressed.connect(_on_equip.bind(slot_idx, item, overlay))
			grid.add_child(item_btn)

func _on_equip(slot_idx: int, item: Dictionary, overlay: Control) -> void:
	SaveManager.set_slot(SLOTS[slot_idx]["key"], item)
	_refresh_slot(slot_idx)
	overlay.queue_free()

func _on_unequip(slot_idx: int, overlay: Control) -> void:
	SaveManager.set_slot(SLOTS[slot_idx]["key"], {})
	_refresh_slot(slot_idx)
	overlay.queue_free()

func _on_shirt_pressed(shirt_id: String) -> void:
	SaveManager.shirt_color = shirt_id
	SaveManager.save()
	_apply_shirt(shirt_id)
	_refresh_shirt_buttons()

func _apply_shirt(shirt_id: String) -> void:
	var hue := 0.583
	for option in SHIRT_OPTIONS:
		if option["id"] == shirt_id:
			hue = option["hue"]
			break
	_shader_mat.set_shader_parameter("target_hue", hue)

func _refresh_shirt_buttons() -> void:
	for option in SHIRT_OPTIONS:
		var btn := get_node("VBox/ShirtSection/ShirtPicker/Btn" + option["label"]) as Button
		if option["id"] == SaveManager.shirt_color:
			btn.add_theme_color_override("font_color", Color(0.78, 0.33, 0.98))
			btn.add_theme_stylebox_override("normal", _selected_style())
			btn.add_theme_stylebox_override("hover",  _selected_style())
		else:
			btn.remove_theme_color_override("font_color")
			btn.remove_theme_stylebox_override("normal")
			btn.remove_theme_stylebox_override("hover")

func _selected_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color                   = Color(0.49, 0.23, 0.93, 0.18)
	s.border_color               = Color(0.49, 0.23, 0.93, 1.0)
	s.border_width_left          = 2
	s.border_width_right         = 2
	s.border_width_top           = 2
	s.border_width_bottom        = 2
	s.corner_radius_top_left     = 10
	s.corner_radius_top_right    = 10
	s.corner_radius_bottom_left  = 10
	s.corner_radius_bottom_right = 10
	return s
