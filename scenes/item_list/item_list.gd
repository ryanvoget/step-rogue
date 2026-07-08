extends Control

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
	"weapon":    "Weapon",
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

@onready var _content:    VBoxContainer = $VBox/ScrollArea/Content
@onready var _filter_row: HBoxContainer = $VBox/FilterScroll/FilterRow

func _ready() -> void:
	$VBox/Header/BtnBack.pressed.connect(func(): SceneManager.go_to("res://scenes/info/info.tscn"))
	_build_filters()
	_build_list()

func _build_filters() -> void:
	for type_key in TYPE_ORDER:
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
	for child in _filter_row.get_children():
		if child is Button:
			_apply_pill_style(child, child.get_meta("filter_key", "") == _active_filter)
	_free_children(_content)
	_build_list()

func _free_children(parent: Node) -> void:
	for c in parent.get_children():
		c.free()

func _build_list() -> void:
	var filtered: Array = ItemRegistry.ITEMS if _active_filter == "all" \
		else ItemRegistry.ITEMS.filter(func(i): return i.get("type", "") == _active_filter)

	for rarity in ORDER:
		var group: Array = filtered.filter(func(i): return i.get("rarity", "") == rarity)
		if group.is_empty():
			continue
		_add_section(rarity, group)

func _add_section(rarity: String, items: Array) -> void:
	var header := Label.new()
	header.text = "%s  %d" % [rarity.capitalize(), items.size()]
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", RARITY_LABEL[rarity])
	_content.add_child(header)

	for item in items:
		_content.add_child(_make_row(item))

func _make_row(item: Dictionary) -> Control:
	var rarity: String = item.get("rarity", "")

	var sb := StyleBoxFlat.new()
	sb.bg_color = RARITY_BG.get(rarity, Color(0.2, 0.2, 0.2))
	sb.corner_radius_top_left     = 10
	sb.corner_radius_top_right    = 10
	sb.corner_radius_bottom_left  = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left   = 12.0
	sb.content_margin_right  = 12.0
	sb.content_margin_top    = 8.0
	sb.content_margin_bottom = 8.0

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var name_col := VBoxContainer.new()
	name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.add_theme_constant_override("separation", 2)

	var lbl_name := Label.new()
	lbl_name.text = str(item.get("name", ""))
	lbl_name.add_theme_font_size_override("font_size", 15)
	name_col.add_child(lbl_name)

	var lbl_type := Label.new()
	lbl_type.text = TYPE_LABELS.get(str(item.get("type", "")), "")
	lbl_type.add_theme_font_size_override("font_size", 11)
	lbl_type.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	name_col.add_child(lbl_type)

	row.add_child(name_col)
	row.add_child(_make_stat_label(item))

	return panel

func _make_stat_label(item: Dictionary) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var damage = item.get("damage")
	var heal = item.get("heal")
	var block = item.get("block")

	if damage != null:
		lbl.text = "⚔ %s" % _fmt(damage)
		lbl.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45))
	elif heal != null:
		lbl.text = "❤ %s" % _fmt(heal)
		lbl.add_theme_color_override("font_color", Color(0.45, 0.90, 0.55))
	elif block != null:
		lbl.text = "🛡 %s" % _fmt(block)
		lbl.add_theme_color_override("font_color", Color(0.50, 0.75, 1.00))
	else:
		lbl.text = "Utility"
		lbl.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))

	return lbl

func _fmt(value) -> String:
	if float(value) == floor(float(value)):
		return str(int(value))
	return str(value)
