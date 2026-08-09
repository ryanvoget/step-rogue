extends Control

const CARD_SIZE := 100

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
const ORDER := ["legendary", "epic", "rare", "uncommon", "common"]

const TYPE_ORDER  := ["all", "weapon", "equipment", "heal", "defensive"]
const TYPE_LABELS := {
	"all":       "All",
	"weapon":    "Weapons",
	"equipment": "Equipment",
	"heal":      "Healing",
	"defensive": "Defense",
}

const PILL_ACTIVE_BG       := Color(0.18, 0.42, 0.78)
const PILL_ACTIVE_HOVER    := Color(0.22, 0.50, 0.90)
const PILL_INACTIVE_BG     := Color(0.10, 0.13, 0.19)
const PILL_INACTIVE_HOVER  := Color(0.14, 0.19, 0.28)
const PILL_ACTIVE_FG       := Color(1.00, 1.00, 1.00)
const PILL_INACTIVE_FG     := Color(0.58, 0.63, 0.72)
const PILL_INACTIVE_HFG    := Color(0.85, 0.88, 0.94)

var _active_filter: String = "all"

@onready var _content:     VBoxContainer = $VBox/ScrollArea/Content
@onready var _count_label: Label         = $VBox/Header/CountLabel
@onready var _actions:     HBoxContainer = $VBox/Actions
@onready var _filter_row:  HBoxContainer = $VBox/FilterScroll/FilterRow

func _ready() -> void:
	SceneManager.add_glass_background(self)
	$VBox/Header/BtnBack.pressed.connect(SceneManager.go_to_menu)
	$VBox/Actions/BtnTradeUp.pressed.connect(
		func(): SceneManager.go_to("res://scenes/trade_up/trade_up.tscn"))
	$VBox/Actions/BtnClear.pressed.connect(_on_clear)
	_refresh()

# ── Full refresh (inventory changed) ─────────────────────────────────────────

func _refresh() -> void:
	var items := SaveManager.inventory
	_count_label.text = "(%d)" % items.size() if items.size() > 0 else ""
	_actions.visible = not items.is_empty()

	_free_children(_filter_row)
	_free_children(_content)

	# Total hedge tokens (purple), shown above the item grid.
	var hedge := Label.new()
	hedge.text = "🟣  Hedge Tokens: %d" % SaveManager.hedge_tokens
	hedge.add_theme_font_size_override("font_size", 15)
	hedge.add_theme_color_override("font_color", Color(0.72, 0.45, 0.98))
	hedge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(hedge)

	if items.is_empty():
		_build_empty_state()
		return

	_build_filters(items)
	_build_grid(items)

# ── Filter bar ────────────────────────────────────────────────────────────────

func _build_filters(items: Array) -> void:
	var present: Dictionary = {}
	for item in items:
		var t := _item_type(item)
		if t != "":
			present[t] = true

	if _active_filter != "all" and not present.has(_active_filter):
		_active_filter = "all"

	for type_key in TYPE_ORDER:
		if type_key != "all" and not present.has(type_key):
			continue
		var btn := _make_pill(type_key)
		btn.set_meta("filter_key", type_key)
		_filter_row.add_child(btn)

func _make_pill(type_key: String) -> Button:
	var btn := Button.new()
	btn.text = TYPE_LABELS[type_key]
	btn.flat = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 34)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	_apply_pill_style(btn, type_key == _active_filter)

	btn.pressed.connect(_on_pill_pressed.bind(type_key))
	return btn

func _apply_pill_style(btn: Button, is_active: bool) -> void:
	var normal_bg  := PILL_ACTIVE_BG      if is_active else PILL_INACTIVE_BG
	var hover_bg   := PILL_ACTIVE_HOVER   if is_active else PILL_INACTIVE_HOVER
	var fg         := PILL_ACTIVE_FG      if is_active else PILL_INACTIVE_FG
	var hover_fg   := PILL_ACTIVE_FG      if is_active else PILL_INACTIVE_HFG

	btn.add_theme_stylebox_override("normal",  _pill_box(normal_bg))
	btn.add_theme_stylebox_override("hover",   _pill_box(hover_bg))
	btn.add_theme_stylebox_override("pressed", _pill_box(PILL_ACTIVE_BG))
	btn.add_theme_color_override("font_color",         fg)
	btn.add_theme_color_override("font_hover_color",   hover_fg)
	btn.add_theme_color_override("font_pressed_color", PILL_ACTIVE_FG)

func _pill_box(bg_col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.corner_radius_top_left     = 17
	s.corner_radius_top_right    = 17
	s.corner_radius_bottom_left  = 17
	s.corner_radius_bottom_right = 17
	s.content_margin_left        = 16.0
	s.content_margin_right       = 16.0
	s.content_margin_top         = 6.0
	s.content_margin_bottom      = 6.0
	s.bg_color = bg_col
	return s

func _on_pill_pressed(type_key: String) -> void:
	_active_filter = type_key
	# Restyle existing pills — no teardown/rebuild of the filter bar
	for child in _filter_row.get_children():
		if child is Button:
			_apply_pill_style(child, child.get_meta("filter_key", "") == _active_filter)
	_free_children(_content)
	_build_grid(SaveManager.inventory)

# ── Grid ──────────────────────────────────────────────────────────────────────

func _build_grid(items: Array) -> void:
	var filtered: Array = items if _active_filter == "all" \
		else items.filter(func(i): return _item_type(i) == _active_filter)

	if filtered.is_empty():
		_build_empty_state()
		return

	for rarity in ORDER:
		var group: Array = filtered.filter(func(i): return i.get("rarity", "") == rarity)
		if group.is_empty():
			continue
		_add_section(rarity, group)

func _item_type(item: Dictionary) -> String:
	if item.has("type"):
		return str(item.get("type", ""))
	var item_name := str(item.get("name", ""))
	for reg in ItemRegistry.ITEMS:
		if reg.get("name", "") == item_name:
			return str(reg.get("type", ""))
	return ""

# ── Sections ──────────────────────────────────────────────────────────────────

func _add_section(rarity: String, items: Array) -> void:
	var header := Label.new()
	header.text = "%s  %d" % [rarity.capitalize(), items.size()]
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", RARITY_LABEL[rarity])
	# Let touches fall through to the ScrollContainer so a drag started anywhere on the list
	# scrolls smoothly (same reasoning as item_list.gd's rows) — nothing here is tappable.
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(grid)

	for item in items:
		grid.add_child(_make_card(item))

func _make_card(item: Dictionary) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.custom_minimum_size = Vector2(CARD_SIZE, 0)
	wrapper.add_theme_constant_override("separation", 4)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tile := Control.new()
	tile.custom_minimum_size = Vector2(CARD_SIZE, CARD_SIZE)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = Vector2(CARD_SIZE, CARD_SIZE)
	bg.color = RARITY_BG.get(item.get("rarity", ""), Color(0.2, 0.2, 0.2)) as Color
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(bg)

	var tex := TextureRect.new()
	tex.position = Vector2.ZERO
	tex.size = Vector2(CARD_SIZE, CARD_SIZE)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path: String = "res://assets/icons/" + str(item.get("file", ""))
	tex.texture = load(path)
	tile.add_child(tex)

	wrapper.add_child(tile)

	var lbl := Label.new()
	lbl.text = str(item.get("name", ""))
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", Color(0.68, 0.71, 0.78))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(lbl)

	return wrapper

# ── Empty state ───────────────────────────────────────────────────────────────

func _build_empty_state() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 100)
	_content.add_child(spacer)

	for pair in [["🎒", 52], ["No items yet", 18], ["Open crates to find items", 14]]:
		var lbl := Label.new()
		lbl.text = pair[0]
		lbl.add_theme_font_size_override("font_size", pair[1])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_content.add_child(lbl)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _free_children(parent: Node) -> void:
	for c in parent.get_children():
		c.free()

# ── Actions ───────────────────────────────────────────────────────────────────

func _on_clear() -> void:
	SaveManager.clear_inventory()
	_active_filter = "all"
	_refresh()
