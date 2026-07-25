extends Control

const REQUIRED   := 10
const CARD_W     := 90
const CARD_H     := 90
const CARD_SLOT  := CARD_W + 8   # 98
const WINNER_IDX := 42

const RARITY_UP := { "common": "uncommon", "uncommon": "rare", "rare": "epic" }
const ELIGIBLE  := ["common", "uncommon", "rare"]

# Type filter — mirrors item_list/inventory. "all" lets any type combine (reward drawn from all
# items of the next rarity); a specific type restricts both the selectable items AND the reward to
# that type, so weapons trade up for a weapon crate, equipment for equipment, defensive for defensive.
const TYPE_ORDER  := ["all", "weapon", "equipment", "defensive"]
const TYPE_LABELS := { "all": "All", "weapon": "Weapon", "equipment": "Equipment", "defensive": "Defense" }

const PILL_ACTIVE_BG      := Color(0.18, 0.42, 0.78)
const PILL_ACTIVE_HOVER   := Color(0.22, 0.50, 0.90)
const PILL_INACTIVE_BG    := Color(0.10, 0.13, 0.19)
const PILL_INACTIVE_HOVER := Color(0.14, 0.19, 0.28)
const PILL_ACTIVE_FG      := Color(1.00, 1.00, 1.00)
const PILL_INACTIVE_FG    := Color(0.58, 0.63, 0.72)
const PILL_INACTIVE_HFG   := Color(0.85, 0.88, 0.94)

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

var _selected:       Array  = []
var _current_rarity: String = ""
var _active_type:    String = "all"

@onready var _select:         Control        = $SelectScreen
@onready var _spin:           Control        = $SpinScreen
@onready var _result:         Control        = $ResultScreen
@onready var _content:        VBoxContainer  = $SelectScreen/VBox/ScrollArea/Content
@onready var _filter_row:     HBoxContainer  = $SelectScreen/VBox/FilterScroll/FilterRow
@onready var _hint:           Label          = $SelectScreen/VBox/Footer/HintLabel
@onready var _btn_confirm:    Button         = $SelectScreen/VBox/Footer/BtnConfirm
@onready var _spin_stage:     Control        = $SpinScreen/VBox/SpinStage
@onready var _spin_track:     HBoxContainer  = $SpinScreen/VBox/SpinStage/SpinTrack
@onready var _result_card:    PanelContainer = $ResultScreen/VBox/ResultCard
@onready var _result_rarity:  Label          = $ResultScreen/VBox/ResultCard/CardVBox/RarityLabel
@onready var _result_img:     TextureRect    = $ResultScreen/VBox/ResultCard/CardVBox/ItemImage
@onready var _result_name:    Label          = $ResultScreen/VBox/ResultCard/CardVBox/ItemName

func _ready() -> void:
	SceneManager.add_glass_background(self)
	$SelectScreen/VBox/Header/BtnBack.pressed.connect(
		func(): SceneManager.go_to("res://scenes/inventory/inventory.tscn"))
	_btn_confirm.pressed.connect(_on_confirm)
	$ResultScreen/VBox/Actions/BtnTradeAgain.pressed.connect(_show_select)
	$ResultScreen/VBox/Actions/BtnGoInventory.pressed.connect(
		func(): SceneManager.go_to("res://scenes/inventory/inventory.tscn"))
	_build_filters()
	_show_select()

# ── Type filter pills ───────────────────────────────────────────────────────────

func _build_filters() -> void:
	for type_key in TYPE_ORDER:
		var btn := _make_pill(type_key)
		btn.set_meta("filter_key", type_key)
		_filter_row.add_child(btn)

func _make_pill(type_key: String) -> Button:
	var btn := Button.new()
	btn.text = TYPE_LABELS[type_key]
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 34)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_apply_pill_style(btn, type_key == _active_type)
	btn.pressed.connect(_on_type_pressed.bind(type_key))
	return btn

func _apply_pill_style(btn: Button, is_active: bool) -> void:
	var normal_bg := PILL_ACTIVE_BG    if is_active else PILL_INACTIVE_BG
	var hover_bg  := PILL_ACTIVE_HOVER if is_active else PILL_INACTIVE_HOVER
	var fg        := PILL_ACTIVE_FG    if is_active else PILL_INACTIVE_FG
	var hover_fg  := PILL_ACTIVE_FG    if is_active else PILL_INACTIVE_HFG
	btn.add_theme_stylebox_override("normal",  _pill_box(normal_bg))
	btn.add_theme_stylebox_override("hover",   _pill_box(hover_bg))
	btn.add_theme_stylebox_override("pressed", _pill_box(PILL_ACTIVE_BG))
	btn.add_theme_color_override("font_color",         fg)
	btn.add_theme_color_override("font_hover_color",   hover_fg)
	btn.add_theme_color_override("font_pressed_color", PILL_ACTIVE_FG)

func _pill_box(bg_col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(17)
	s.content_margin_left  = 16.0
	s.content_margin_right = 16.0
	s.content_margin_top   = 6.0
	s.content_margin_bottom = 6.0
	s.bg_color = bg_col
	return s

func _on_type_pressed(type_key: String) -> void:
	if type_key == _active_type:
		return
	_active_type = type_key
	for child in _filter_row.get_children():
		if child is Button:
			_apply_pill_style(child, child.get_meta("filter_key", "") == _active_type)
	# Changing the type invalidates any in-progress same-rarity selection.
	_selected.clear()
	_current_rarity = ""
	_build_grid()
	_sync_footer()

# ── Select screen ─────────────────────────────────────────────────────────────

func _show_select() -> void:
	_selected.clear()
	_current_rarity = ""
	_select.visible = true
	_spin.visible   = false
	_result.visible = false
	_build_grid()
	_sync_footer()

func _build_grid() -> void:
	for c in _content.get_children():
		c.queue_free()

	var items     := SaveManager.inventory
	var has_items := false

	for rarity in ELIGIBLE:
		var group: Array = []
		for i in items.size():
			if items[i].get("rarity", "") != rarity:
				continue
			if _active_type != "all" and _item_type(items[i]) != _active_type:
				continue
			group.append({ "item": items[i], "inv_idx": i })
		if group.is_empty():
			continue
		has_items = true
		_add_section(rarity, group)

	if not has_items:
		_build_empty_state()

# Item type, tolerant of inventory entries that don't carry a "type" field (falls back to the
# registry by name) — same approach as inventory.gd.
func _item_type(item: Dictionary) -> String:
	if item.has("type"):
		return str(item.get("type", ""))
	var item_name := str(item.get("name", ""))
	for reg in ItemRegistry.ITEMS:
		if reg.get("name", "") == item_name:
			return str(reg.get("type", ""))
	return ""

func _add_section(rarity: String, group: Array) -> void:
	var header := Label.new()
	header.text = rarity.capitalize()
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", RARITY_LABEL[rarity])
	_content.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(grid)

	for entry in group:
		grid.add_child(_make_card(entry.item, entry.inv_idx))

func _make_card(item: Dictionary, inv_idx: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CARD_W, CARD_H)
	btn.flat       = true
	btn.focus_mode = Control.FOCUS_NONE
	# PASS (not the Button default STOP) lets a drag started on a card still reach the
	# ScrollContainer for smooth scrolling, while taps still fire pressed — same pattern as
	# item_list.gd's row tap button.
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.set_meta("inv_idx", inv_idx)
	btn.set_meta("rarity",  item.get("rarity", ""))

	var bg := ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = Vector2(CARD_W, CARD_H)
	bg.color = RARITY_BG.get(item.get("rarity", ""), Color(0.2, 0.2, 0.2)) as Color
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(bg)

	var tex := TextureRect.new()
	tex.position = Vector2.ZERO
	tex.size = Vector2(CARD_W, CARD_H)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path: String = "res://assets/icons/" + str(item.get("file", ""))
	tex.texture = load(path)
	btn.add_child(tex)

	# White flash overlay = selected
	var sel_overlay := ColorRect.new()
	sel_overlay.name = "SelOverlay"
	sel_overlay.position = Vector2.ZERO
	sel_overlay.size = Vector2(CARD_W, CARD_H)
	sel_overlay.color       = Color(1, 1, 1, 0.30)
	sel_overlay.visible     = false
	sel_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(sel_overlay)

	# Dark overlay = locked
	var lock_overlay := ColorRect.new()
	lock_overlay.name = "LockOverlay"
	lock_overlay.position = Vector2.ZERO
	lock_overlay.size = Vector2(CARD_W, CARD_H)
	lock_overlay.color       = Color(0, 0, 0, 0.60)
	lock_overlay.visible     = false
	lock_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lock_overlay)

	btn.pressed.connect(func(): _on_card_pressed(inv_idx, str(item.get("rarity", ""))))
	return btn

func _on_card_pressed(inv_idx: int, rarity: String) -> void:
	if _current_rarity != "" and rarity != _current_rarity:
		return
	if _selected.has(inv_idx):
		_selected.erase(inv_idx)
		if _selected.is_empty():
			_current_rarity = ""
	else:
		if _selected.size() >= REQUIRED:
			return
		_selected.append(inv_idx)
		_current_rarity = rarity
	_sync_cards()
	_sync_footer()

func _sync_cards() -> void:
	for node in _content.get_children():
		if not node is GridContainer:
			continue
		for card in node.get_children():
			var inv_idx: int   = card.get_meta("inv_idx", -1)
			var rarity:  String = card.get_meta("rarity", "")
			var is_sel  := _selected.has(inv_idx)
			var is_locked := _current_rarity != "" and rarity != _current_rarity
			card.get_node("SelOverlay").visible  = is_sel
			card.get_node("LockOverlay").visible = is_locked and not is_sel

func _sync_footer() -> void:
	var count := _selected.size()
	_hint.text = (
		"%d / %d %s selected" % [count, REQUIRED, _current_rarity]
		if _current_rarity != ""
		else "Select 10 items of the same rarity"
	)
	_btn_confirm.disabled = count != REQUIRED

func _build_empty_state() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 80)
	_content.add_child(spacer)
	for pair in [["No eligible items", 18], ["Collect common, uncommon, or rare\nitems from crates to trade up.", 14]]:
		var lbl := Label.new()
		lbl.text = pair[0]
		lbl.add_theme_font_size_override("font_size", pair[1])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_content.add_child(lbl)

# ── Confirm → spin ────────────────────────────────────────────────────────────

func _on_confirm() -> void:
	if _selected.size() != REQUIRED:
		return
	var new_rarity: String     = RARITY_UP[_current_rarity]
	# Reward is drawn from the active type's pool at the next rarity up — "all" = any type, else
	# restricted to weapons/equipment/defensive to match what was traded in.
	var pool:       Array      = ItemRegistry.items_of_type_rarity(_active_type, new_rarity)
	if pool.is_empty():
		pool = ItemRegistry.items_of_rarity(new_rarity)
	var winner:     Dictionary = pool[randi() % pool.size()]
	SaveManager.remove_items_by_indices(_selected.duplicate())
	_show_spin(winner, pool)

func _show_spin(winner: Dictionary, pool: Array) -> void:
	_select.visible = false
	_spin.visible   = true
	_result.visible = false
	_build_track(winner, pool)
	await get_tree().process_frame
	_animate_spin(winner)

func _build_track(winner: Dictionary, pool: Array) -> void:
	for c in _spin_track.get_children():
		c.queue_free()
	var track: Array = []
	for _i in WINNER_IDX:
		track.append(pool[randi() % pool.size()])
	track.append(winner)
	for _i in 8:
		track.append(pool[randi() % pool.size()])
	for item in track:
		_spin_track.add_child(_make_spin_card(item))

func _make_spin_card(item: Dictionary) -> Control:
	var card := Control.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	var bg := ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = Vector2(CARD_W, CARD_H)
	bg.color = RARITY_BG.get(item.get("rarity", ""), Color(0.2, 0.2, 0.2)) as Color
	card.add_child(bg)
	var tex := TextureRect.new()
	tex.position = Vector2.ZERO
	tex.size = Vector2(CARD_W, CARD_H)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var path: String = "res://assets/icons/" + str(item.get("file", ""))
	tex.texture = load(path)
	card.add_child(tex)
	return card

func _animate_spin(winner: Dictionary) -> void:
	var vw    := _spin_stage.size.x
	var init  := vw * 0.5 - CARD_SLOT * 0.5
	var final := vw * 0.5 - (WINNER_IDX * CARD_SLOT + CARD_W * 0.5)
	_spin_track.position = Vector2(init, 0)
	var tw := create_tween()
	tw.tween_property(_spin_track, "position:x", final, 5.0) \
	  .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _show_result(winner))

# ── Result ────────────────────────────────────────────────────────────────────

func _show_result(winner: Dictionary) -> void:
	SaveManager.add_to_inventory(winner)
	_select.visible = false
	_spin.visible   = false
	_result.visible = true

	var rarity: String = winner.get("rarity", "common")
	_result_rarity.text = rarity.capitalize()
	_result_name.text   = str(winner.get("name", ""))

	var style := StyleBoxFlat.new()
	style.bg_color = RARITY_BG.get(rarity, Color(0.2, 0.2, 0.2)) as Color
	style.set_corner_radius_all(10)
	style.set_content_margin_all(24.0)
	_result_card.add_theme_stylebox_override("panel", style)

	var path: String = "res://assets/icons/" + str(winner.get("file", ""))
	_result_img.texture = load(path) if ResourceLoader.exists(path) else null
