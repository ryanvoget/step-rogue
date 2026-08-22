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

# Each shirt colour is a distinct character with a passive (applied in world.gd's _apply_shirt_passive).
const SHIRT_PASSIVES := {
	"blue":   "Blue — non-elemental weapons deal 1.5× damage",
	"red":    "Red — elemental effects are doubled (burn, chain lightning, freeze thaw)",
	"green":  "Green — melee weapons: +20% damage & rate of fire",
	"yellow": "Yellow — ranged guns: +20% damage & rate of fire",
}

const SLOTS := [
	{ "key": "equipped_weapon",    "label": "Weapon",    "empty_icon": "⚔️",  "type": "weapon"    },
	{ "key": "equipped_equipment", "label": "Equipment",  "empty_icon": "🎒",  "type": "equipment" },
	{ "key": "equipped_defensive", "label": "Defense",   "empty_icon": "🛡️",  "type": "defensive" },
	# Artifacts are no longer equipped here — they are only acquired during a run (bar slot machine,
	# boss relics) and shown in the in-game HUD's top-right (see hud.gd's refresh_artifact_icons).
]

# Rarity styling — matches inventory/item_list so the picker reads the same everywhere.
const RARITY_BG := {
	"common":    Color(0.22, 0.22, 0.27),
	"uncommon":  Color(0.07, 0.32, 0.11),
	"rare":      Color(0.07, 0.14, 0.48),
	"epic":      Color(0.28, 0.07, 0.42),
	"legendary": Color(0.50, 0.35, 0.00),
}
const RARITY_LABEL := {
	"common":    Color(0.70, 0.70, 0.75),
	"uncommon":  Color(0.35, 0.90, 0.45),
	"rare":      Color(0.30, 0.55, 1.00),
	"epic":      Color(0.80, 0.40, 1.00),
	"legendary": Color(1.00, 0.80, 0.10),
}
const RARITY_ORDER := ["legendary", "epic", "rare", "uncommon", "common"]

@onready var _sprite:     AnimatedSprite2D = $PlayerSprite
@onready var _canvas:     Control          = $VBox/ContentRow/CharCanvas
@onready var _shader_mat: ShaderMaterial   = $PlayerSprite.material
@onready var _points_label: Label          = $VBox/ContentRow/CharCanvas/PointsLabel

var _slot_btns: Array = []
var _current_overlay: Control = null # the active _open_picker overlay, if any — see _handle_screen_touch
var _current_panel: Control = null   # the picker's centered panel — taps outside it dismiss the popup
const TAP_MAX_DRAG := 45.0 # a touch that moves more than this (screen px) is a scroll drag, not a
                            # tap — event positions are physical pixels (~3x), so 12 was far too
                            # tight and normal taps got dropped as drags (popup didn't close)
var _touch_start := Vector2.ZERO
var _touch_moved := false
var _press_btn: Button = null # button under the initial touch-down; fired on release if not dragged

func _ready() -> void:
	SceneManager.add_glass_background(self)
	$VBox/Header/BtnBack.pressed.connect(SceneManager.go_to_menu)
	_setup_sprite()
	_setup_shirt_buttons()
	_setup_slots()
	_apply_shirt(SaveManager.shirt_color)
	_refresh_passive_label()
	_refresh_points()
	await get_tree().process_frame
	_reposition_sprite()

# Shows the total equipment-point cost of the loadout above the player. Red (and the run is
# blocked at the Play button) when it exceeds the budget; accent colour when within it.
func _refresh_points() -> void:
	var pts := ItemRegistry.equipped_points()
	_points_label.text = "Loadout Points: %d / %d" % [pts, ItemRegistry.EQUIPMENT_POINT_BUDGET]
	if pts > ItemRegistry.EQUIPMENT_POINT_BUDGET:
		_points_label.add_theme_color_override("font_color", Color(1.0, 0.30, 0.30))
	else:
		_points_label.add_theme_color_override("font_color", Color(0.55, 0.90, 1.0))

# Direct touch fallback, same reasoning/pattern as menu.gd's _handle_screen_touch:
# ButtonNode.pressed only fires on InputEventMouseButton, but the embedded display server may
# not run emulate_mouse_from_touch, so taps here (slot buttons, shirt buttons, and the
# dynamically-built item-picker overlay's buttons) can silently never register. Unlike menu.gd,
# this screen's item picker is built at runtime with a variable number of buttons, so this
# walks the tree generically instead of checking a hardcoded list.
func _input(event: InputEvent) -> void:
	# Capture the button under the touch-DOWN, then fire it on release if the finger didn't drag —
	# standard button behavior. This is robust to the finger drifting slightly (or the list
	# scrolling) between press and release: we act on the button that was pressed, not on wherever
	# the release happened to land (which could be a gap between buttons → nothing selected → popup
	# didn't close). A drag past TAP_MAX_DRAG is a scroll, so it selects nothing.
	if event is InputEventScreenTouch:
		# While a picker is open it is fully modal: taps are hit-tested ONLY against the overlay, never
		# the character screen behind it. This is what stops the popup "cycling" — previously a tap that
		# missed the small ✕ (which sits directly over a slot box) could fall through and re-open a slot
		# picker, and a double-fired tap (touch + emulated mouse) could even stack two overlays.
		var ov := _active_overlay()
		if event.pressed:
			_touch_start = event.position
			_touch_moved = false
			_press_btn = _find_button_at(ov if ov != null else self, event.position)
		else:
			if not _touch_moved and _press_btn != null and is_instance_valid(_press_btn) and _press_btn.visible:
				_press_btn.pressed.emit()
				get_viewport().set_input_as_handled()
			elif ov != null and not _touch_moved and not _panel_has_point(_touch_start):
				# A clean tap outside the panel (or that missed the ✕) → close the popup in one tap.
				_close_overlay()
				get_viewport().set_input_as_handled()
			elif ov != null:
				# Any other tap while the popup is open is swallowed so nothing behind it ever reacts.
				get_viewport().set_input_as_handled()
			_press_btn = null
	elif event is InputEventScreenDrag:
		if event.position.distance_to(_touch_start) > TAP_MAX_DRAG:
			_touch_moved = true

# Hit-test with get_global_transform_with_canvas() (maps local → screen pixels, INCLUDING any
# ScrollContainer scroll offset and the viewport stretch) instead of get_global_rect() — the
# latter ignores the scroll's canvas transform, so after scrolling it matched pre-scroll positions
# and picked the wrong item (bottom-of-list items never registered). Compares against the raw
# touch position (already in screen pixels).
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

# The currently-open picker overlay, or null. Treats an overlay that's already been queue_free'd as
# closed, so a tap in the frame after closing can't be routed to the lingering (freed) node.
func _active_overlay() -> Control:
	if _current_overlay != null and is_instance_valid(_current_overlay) and not _current_overlay.is_queued_for_deletion():
		return _current_overlay
	return null

func _close_overlay() -> void:
	if _current_overlay != null and is_instance_valid(_current_overlay):
		_current_overlay.queue_free()
	_current_overlay = null
	_current_panel = null

# True if a screen-pixel position falls inside the current picker panel (used to tell a tap on the
# panel apart from a tap on the dimmed background, which dismisses the popup).
func _panel_has_point(pixel_pos: Vector2) -> bool:
	if _current_panel == null or not is_instance_valid(_current_panel):
		return false
	var local: Vector2 = _current_panel.get_global_transform_with_canvas().affine_inverse() * pixel_pos
	return Rect2(Vector2.ZERO, _current_panel.size).has_point(local)

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

var _pts_lbls: Array = [] # per-slot "N pts" labels, sitting to the right of each slot button

func _setup_slots() -> void:
	# Bold white font for the point-cost labels beside each slot.
	var bold := FontVariation.new()
	bold.base_font = ThemeDB.fallback_font
	bold.variation_embolden = 0.6
	for i in range(SLOTS.size()):
		var btn := get_node("VBox/ContentRow/SlotsCol/Row" + str(i) + "/Slot" + str(i)) as Button
		_slot_btns.append(btn)
		btn.pressed.connect(_open_picker.bind(i))
		# Item type ("Weapon"/"Equipment"/"Defense") centered white across the top of the box.
		var type_lbl := Label.new()
		type_lbl.name = "TypeLabel"
		type_lbl.text = SLOTS[i]["label"]
		type_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
		type_lbl.offset_top = 5.0
		type_lbl.offset_bottom = 24.0
		type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		type_lbl.add_theme_font_size_override("font_size", 12)
		type_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(type_lbl)
		var pts := get_node("VBox/ContentRow/SlotsCol/Row" + str(i) + "/Pts" + str(i)) as Label
		pts.add_theme_font_override("font", bold)
		pts.add_theme_color_override("font_color", Color(1, 1, 1))
		_pts_lbls.append(pts)
		_refresh_slot(i)

func _refresh_slot(idx: int) -> void:
	var slot     = SLOTS[idx]
	var btn      = _slot_btns[idx] as Button
	var equipped: Dictionary = SaveManager.get_slot(slot["key"])
	btn.expand_icon = false
	var rarity: String = equipped.get("rarity", "")
	# The item type is shown by the TypeLabel on top of the box (see _setup_slots); the button's
	# own text is just the item name (or "(empty)"), sitting below it.
	if equipped.is_empty():
		btn.icon = null
		btn.remove_theme_color_override("font_color")
		btn.text = "\n(empty)"
	else:
		# Show the equipped item's image next to the name (capped to 44px), coloured by rarity.
		btn.icon = load("res://assets/icons/" + equipped["file"])
		btn.add_theme_constant_override("icon_max_width", 44)
		btn.add_theme_color_override("font_color", RARITY_LABEL.get(rarity, Color(1, 1, 1)))
		btn.text = ("\n🟣 " if SaveManager.is_slot_hedged(slot["key"]) else "\n") + equipped["name"]
	# Points this item contributes, shown to the right of the slot (outside the button box).
	# Artifacts have no equip cost for now, so their slot shows no point label.
	if idx < _pts_lbls.size():
		if slot.get("artifact", false):
			_pts_lbls[idx].text = ""
		else:
			_pts_lbls[idx].text = "" if equipped.is_empty() else "%d pts" % ItemRegistry.item_points(equipped)

func _open_picker(slot_idx: int) -> void:
	# Never stack overlays. A single tap can arrive twice (screen-touch AND emulated mouse), which
	# previously opened two pickers on top of each other — the root cause of the "cycling" close bug.
	if _active_overlay() != null:
		return
	var slot = SLOTS[slot_idx]
	# Artifacts live in their own inventory; every other slot draws from the shared inventory.
	var source: Array = SaveManager.artifact_inventory if slot.get("artifact", false) else SaveManager.inventory
	var inv: Array = source.filter(
		func(item): return item.get("type", "") == slot["type"]
	)

	# Full-screen overlay
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_current_overlay = overlay

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
	_current_panel = panel

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
	close_btn.custom_minimum_size = Vector2(48, 48) # big, easy-to-hit target
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.pressed.connect(_close_overlay)
	title_row.add_child(close_btn)

	# Unequip button if slot is filled
	var cur: Dictionary = SaveManager.get_slot(slot["key"])
	if not cur.is_empty():
		var unequip_btn := Button.new()
		unequip_btn.text = "Unequip  (" + cur["name"] + ")"
		unequip_btn.pressed.connect(_on_unequip.bind(slot_idx, overlay))
		vbox.add_child(unequip_btn)
		# Hedge token toggle: protect this item so it survives a lost run (or free the token to move it).
		vbox.add_child(_make_hedge_toggle(slot_idx))

	# Item list or empty message
	if inv.is_empty():
		var msg := Label.new()
		msg.text = "No " + slot["label"].to_lower() + " items in your inventory yet."
		msg.add_theme_font_size_override("font_size", 14)
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(msg)
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 340)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED # only scrolls vertically
		vbox.add_child(scroll)

		var content := VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation", 6)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scroll.add_child(content)

		# Grouped by rarity (highest first): a colored section header, then a 2-column grid of
		# item name buttons.
		for rarity in RARITY_ORDER:
			var group: Array = inv.filter(func(i): return i.get("rarity", "") == rarity)
			if group.is_empty():
				continue
			var header := Label.new()
			header.text = "%s  (%d)" % [rarity.capitalize(), group.size()]
			header.add_theme_font_size_override("font_size", 13)
			header.add_theme_color_override("font_color", RARITY_LABEL[rarity])
			header.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(header)

			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 8)
			grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(grid)

			for item in group:
				grid.add_child(_make_picker_button(item, slot_idx, overlay))

# One item button in the picker list: the item's icon (small, left) + name, rarity-tinted and
# rarity-bordered, stretched to fill its grid column (2 per row). A tap anywhere on it selects the
# item. MOUSE_FILTER_PASS lets a drag started on it still reach the ScrollContainer for scrolling.
func _make_picker_button(item: Dictionary, slot_idx: int, overlay: Control) -> Control:
	var rarity: String = item.get("rarity", "")
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 46)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.text = str(item.get("name", ""))
	btn.icon = load("res://assets/icons/" + item["file"])
	btn.add_theme_constant_override("icon_max_width", 26)
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true # long names truncate instead of overflowing the button
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", RARITY_LABEL.get(rarity, Color(0.85, 0.85, 0.9)))
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.add_theme_stylebox_override("normal",  _rarity_box(rarity, false))
	btn.add_theme_stylebox_override("hover",   _rarity_box(rarity, true))
	btn.add_theme_stylebox_override("pressed", _rarity_box(rarity, true))
	btn.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())
	btn.pressed.connect(_on_equip.bind(slot_idx, item, overlay))
	return btn

func _rarity_box(rarity: String, hover: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	var base: Color = RARITY_BG.get(rarity, Color(0.2, 0.2, 0.25))
	s.bg_color = base.lightened(0.12) if hover else base
	s.border_color = RARITY_LABEL.get(rarity, Color(0.6, 0.6, 0.65))
	s.set_border_width_all(2)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(6)
	return s

# Purple hedge-token toggle for a slot: apply (protect the equipped item on a lost run) or remove
# (free the token to move it elsewhere). Disabled/greyed when there are none to apply.
func _make_hedge_toggle(slot_idx: int) -> Control:
	var key: String = SLOTS[slot_idx]["key"]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 40)
	if SaveManager.is_slot_hedged(key):
		btn.text = "🟣  Remove Hedge Token"
		btn.pressed.connect(_on_hedge_toggle.bind(slot_idx, false))
	elif SaveManager.hedge_tokens > 0:
		btn.text = "🟣  Apply Hedge Token (%d)" % SaveManager.hedge_tokens
		btn.pressed.connect(_on_hedge_toggle.bind(slot_idx, true))
	else:
		btn.text = "🟣  No hedge tokens"
		btn.disabled = true
	return btn

func _on_hedge_toggle(slot_idx: int, apply: bool) -> void:
	var key: String = SLOTS[slot_idx]["key"]
	if apply:
		SaveManager.apply_hedge(key)
	else:
		SaveManager.remove_hedge(key)
	_refresh_slot(slot_idx)
	_close_overlay() # tear down the current picker, then rebuild so the toggle reflects the new state
	_open_picker(slot_idx)

func _on_equip(slot_idx: int, item: Dictionary, _overlay: Control) -> void:
	# Swapping the item frees any hedge token on this slot (the token protected the old item).
	if SaveManager.is_slot_hedged(SLOTS[slot_idx]["key"]):
		SaveManager.remove_hedge(SLOTS[slot_idx]["key"])
	SaveManager.set_slot(SLOTS[slot_idx]["key"], item)
	_refresh_slot(slot_idx)
	_refresh_points()
	_close_overlay()

func _on_unequip(slot_idx: int, _overlay: Control) -> void:
	if SaveManager.is_slot_hedged(SLOTS[slot_idx]["key"]):
		SaveManager.remove_hedge(SLOTS[slot_idx]["key"])
	SaveManager.set_slot(SLOTS[slot_idx]["key"], {})
	_refresh_slot(slot_idx)
	_refresh_points()
	_close_overlay()

func _on_shirt_pressed(shirt_id: String) -> void:
	SaveManager.shirt_color = shirt_id
	SaveManager.save()
	_apply_shirt(shirt_id)
	_refresh_shirt_buttons()
	_refresh_passive_label()

func _refresh_passive_label() -> void:
	var lbl := get_node_or_null("VBox/ShirtSection/CharacterPassive") as Label
	if lbl != null:
		lbl.text = "✦ " + str(SHIRT_PASSIVES.get(SaveManager.shirt_color, ""))

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
