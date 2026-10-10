extends Control

const T := preload("res://scenes/ui/ui_theme.gd")

# Item-row backings. Dark slabs tinted toward the rarity rather than saturated blocks of it —
# the same rule the reference console follows, where the panel is dark and only the content
# glows. The "(e)" element tags below were contrast-checked against the OLD brighter values and
# clear 4.5:1 comfortably against these darker ones too.
const RARITY_BG := {
	"common":    Color(0.098, 0.114, 0.149),
	"uncommon":  Color(0.047, 0.169, 0.106),
	"rare":      Color(0.047, 0.106, 0.251),
	"epic":      Color(0.157, 0.063, 0.239),
	"legendary": Color(0.231, 0.165, 0.027),
}
const RARITY_LABEL := {
	"common":    Color(0.561, 0.639, 0.714),
	"uncommon":  Color(0.306, 0.902, 0.510),
	"rare":      Color(0.310, 0.639, 1.000),
	"epic":      Color(0.761, 0.420, 1.000),
	"legendary": Color(1.000, 0.737, 0.200),
}
const ORDER := ["legendary", "epic", "rare", "uncommon", "common"]

# "(e)" marker shown after the name of any item carrying an `element`, tinted by which element.
# These are deliberately light rather than fully saturated: the tag sits on RARITY_BG, and a pure
# red (1,0,0) only manages 2.2:1 on the uncommon green and 3.3:1 on legendary — unreadable. Every
# colour here clears 4.5:1 (WCAG AA) against all five rarity backgrounds, so the tag stays legible
# whatever rarity an item is given later. Fire reads as coral for that reason.
const ELEMENT_TAG_COLORS := {
	"electric": Color(1.00, 0.85, 0.15), # yellow
	"fire":     Color(1.00, 0.62, 0.50), # red
	"ice":      Color(0.55, 0.85, 1.00), # light blue
	"void":     Color(0.97, 0.58, 1.00), # magenta — Wave Ray Gun; not specified, chosen to match
}

# Returns the "(e)" tag for an elemental item, or null for everything else.
func _make_element_tag(item: Dictionary, font_size: int) -> Label:
	var el := str(item.get("element", ""))
	if not ELEMENT_TAG_COLORS.has(el):
		return null
	var lbl := Label.new()
	lbl.text = "(e)"
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", ELEMENT_TAG_COLORS[el])
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.tooltip_text = el.capitalize()
	return lbl

const TYPE_ORDER  := ["all", "weapon", "equipment", "defensive", "artifact", "fused"]
const TYPE_LABELS := {
	"all":       "All",
	"weapon":    "Weapon",
	"equipment": "Equipment",
	"defensive": "Defense",
	"artifact":  "Artifact",
	"fused":     "Fusion",
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
	SceneManager.add_glass_background(self)
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
	btn.add_theme_font_size_override("font_size", 12)
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
	# Tight horizontal padding: six pills have to fit inside the 480px viewport, and the row only
	# scrolls by drag — which the buttons themselves swallow, so anything past the edge is
	# unreachable rather than merely off-screen.
	s.content_margin_left        = 9.0
	s.content_margin_right       = 9.0
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
	# The Fusion filter isn't a list at all — it's the workbench (see _build_fusion_tab).
	if _active_filter == "fused":
		_build_fusion_tab()
		return
	# Artifacts (from ItemRegistry.ARTIFACTS) are listed under the regular items on "All", or on
	# their own with the "Artifact" filter. Everything else comes from ItemRegistry.ITEMS.
	var filtered: Array
	if _active_filter == "artifact":
		filtered = ItemRegistry.ARTIFACTS.duplicate()
	elif _active_filter == "all":
		filtered = ItemRegistry.ITEMS + ItemRegistry.ARTIFACTS
	else:
		filtered = ItemRegistry.ITEMS.filter(func(i): return i.get("type", "") == _active_filter)

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
		var row := _make_row(item)
		_content.add_child(row)
		_animate_row_in(row, _content.get_child_count())

# Rows fade and slide up as the list builds, staggered down the page — so a long list reads as
# loading in rather than appearing all at once. Capped so the bottom of a big list is not left
# waiting on a long queue of delays.
func _animate_row_in(row: Control, index: int) -> void:
	row.modulate.a = 0.0
	var tw := row.create_tween()
	tw.tween_interval(minf(float(index) * 0.022, 0.5))
	tw.tween_property(row, "modulate:a", 1.0, 0.22)

func _make_row(item: Dictionary) -> Control:
	var rarity: String = item.get("rarity", "")

	var accent: Color = RARITY_LABEL.get(rarity, T.TEXT_DIM)
	var sb := StyleBoxFlat.new()
	sb.bg_color = RARITY_BG.get(rarity, Color(0.1, 0.11, 0.15))
	sb.border_color = Color(accent, 0.45)
	sb.set_border_width_all(1)
	sb.border_width_left = 3 # the emitter rail, matching every other panel in the game
	sb.corner_radius_top_left     = 10
	sb.corner_radius_top_right    = 10
	sb.corner_radius_bottom_left  = 10
	sb.corner_radius_bottom_right = 10
	sb.shadow_color = Color(accent, 0.14)
	sb.shadow_size = 5
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

	# Name plus, for elemental items, a colour-coded "(e)" right after it.
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_theme_constant_override("separation", 4)
	var lbl_name := Label.new()
	lbl_name.text = str(item.get("name", ""))
	lbl_name.add_theme_font_size_override("font_size", 15)
	name_row.add_child(lbl_name)
	var el_tag := _make_element_tag(item, 13)
	if el_tag != null:
		name_row.add_child(el_tag)
	name_col.add_child(name_row)

	var lbl_type := Label.new()
	# Artifacts show their effect description right in the row; other items show their type.
	if item.get("type", "") == "artifact":
		lbl_type.text = str(item.get("effect", ""))
		lbl_type.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl_type.custom_minimum_size = Vector2(180, 0)
	else:
		# Weapons show Melee/Ranged too — weapons only fuse within their own kind, so this is
		# the difference that decides whether two of them can be combined at all.
		var kind := ItemRegistry.weapon_kind_label(item)
		lbl_type.text = "%s · %s" % [TYPE_LABELS.get(str(item.get("type", "")), ""), kind] if kind != "" \
			else TYPE_LABELS.get(str(item.get("type", "")), "")
	lbl_type.add_theme_font_size_override("font_size", 11)
	lbl_type.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	name_col.add_child(lbl_type)

	row.add_child(name_col)
	row.add_child(_make_stat_label(item))

	# Invisible full-size button layered over the row so tapping anywhere on it opens the
	# detail popup. PanelContainer sizes/positions every direct child to fill its content
	# rect, so this just needs to exist as a sibling of `row` — no manual anchoring needed.
	# A real Button (not a raw gui_input hookup) since that's the pattern already proven to
	# work with touch elsewhere in this project (menus, HUD) — see project gotchas re:
	# emulate_touch_from_mouse being intentionally off.
	var tap_btn := Button.new()
	tap_btn.flat = true
	tap_btn.focus_mode = Control.FOCUS_NONE
	# PASS (not the Button default of STOP) lets the touch also reach the ScrollContainer
	# ancestor for drag-to-scroll detection — with STOP, every row was swallowing the initial
	# touch of a scroll gesture, which is what made scrolling feel interrupted/jerky.
	tap_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	var empty_box := StyleBoxEmpty.new()
	tap_btn.add_theme_stylebox_override("normal", empty_box)
	tap_btn.add_theme_stylebox_override("hover", empty_box)
	tap_btn.add_theme_stylebox_override("pressed", empty_box)
	tap_btn.add_theme_stylebox_override("focus", empty_box)
	tap_btn.pressed.connect(_show_item_popup.bind(item))
	panel.add_child(tap_btn)

	return panel

func _make_stat_label(item: Dictionary) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	if item.get("type", "") == "artifact":
		lbl.text = "🏺"
		lbl.add_theme_color_override("font_color", Color(0.80, 0.55, 1.00))
		return lbl

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

# ── Item detail popup ────────────────────────────────────────────────────

func _show_item_popup(item: Dictionary) -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	# Tapping anywhere on the dimmed background closes the popup.
	var dim_btn := Button.new()
	dim_btn.flat = true
	dim_btn.focus_mode = Control.FOCUS_NONE
	dim_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	var empty_box := StyleBoxEmpty.new()
	dim_btn.add_theme_stylebox_override("normal", empty_box)
	dim_btn.add_theme_stylebox_override("hover", empty_box)
	dim_btn.add_theme_stylebox_override("pressed", empty_box)
	dim_btn.add_theme_stylebox_override("focus", empty_box)
	dim_btn.pressed.connect(overlay.queue_free)
	overlay.add_child(dim_btn)

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	# set_anchors_preset only sets the anchor point — grow direction defaults to END, so
	# without this the card expands off the right edge as its content grows past its
	# initial near-zero size instead of staying centered.
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(300, 0)

	var rarity: String = item.get("rarity", "")
	var sb := StyleBoxFlat.new()
	sb.bg_color = RARITY_BG.get(rarity, Color(0.18, 0.18, 0.22))
	sb.border_color = RARITY_LABEL.get(rarity, Color(0.5, 0.5, 0.55))
	sb.border_width_left   = 2
	sb.border_width_right  = 2
	sb.border_width_top    = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left     = 16
	sb.corner_radius_top_right    = 16
	sb.corner_radius_bottom_left  = 16
	sb.corner_radius_bottom_right = 16
	sb.content_margin_left   = 18.0
	sb.content_margin_right  = 18.0
	sb.content_margin_top    = 16.0
	sb.content_margin_bottom = 16.0
	card.add_theme_stylebox_override("panel", sb)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var lbl_name := Label.new()
	lbl_name.text = str(item.get("name", ""))
	lbl_name.add_theme_font_size_override("font_size", 19)
	lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	header.add_child(lbl_name)
	var el_tag := _make_element_tag(item, 17)
	if el_tag != null:
		header.add_child(el_tag)

	var btn_close := Button.new()
	btn_close.text = "✕"
	btn_close.focus_mode = Control.FOCUS_NONE
	btn_close.custom_minimum_size = Vector2(34, 34)
	btn_close.pressed.connect(overlay.queue_free)
	header.add_child(btn_close)
	outer.add_child(header)

	var lbl_sub := Label.new()
	var kind_lbl := ItemRegistry.weapon_kind_label(item)
	lbl_sub.text = "%s · %s%s" % [rarity.capitalize(), TYPE_LABELS.get(str(item.get("type", "")), ""),
		" · " + kind_lbl if kind_lbl != "" else ""]
	lbl_sub.add_theme_font_size_override("font_size", 12)
	lbl_sub.add_theme_color_override("font_color", RARITY_LABEL.get(rarity, Color(0.7, 0.7, 0.75)))
	outer.add_child(lbl_sub)

	var content_row := HBoxContainer.new()
	content_row.add_theme_constant_override("separation", 16)

	var icon := TextureRect.new()
	var icon_path := "res://assets/icons/" + str(item.get("file", ""))
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(104, 104)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE # let custom_minimum_size govern the box
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content_row.add_child(icon)

	var stats_col := VBoxContainer.new()
	stats_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Without a width cap, autowrap-enabled Labels report their unwrapped single-line width
	# as their minimum size, so the whole card grows to fit the longest stat line instead of
	# actually wrapping — this forces the wrap.
	stats_col.custom_minimum_size = Vector2(170, 0)
	stats_col.add_theme_constant_override("separation", 5)
	var lines := _build_stat_lines(item)
	if lines.is_empty():
		lines = ["No additional stats."]
	for line in lines:
		var lbl := Label.new()
		lbl.text = line
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		stats_col.add_child(lbl)
	content_row.add_child(stats_col)

	outer.add_child(content_row)
	card.add_child(outer)
	overlay.add_child(card)
	add_child(overlay)

# Data-driven: reads whatever gameplay fields ItemRegistry set on this item and turns them
# into readable lines, so a new weapon/equipment field automatically shows up here without
# needing per-item or per-weapon-type popup code.
func _build_stat_lines(item: Dictionary) -> Array:
	# Artifacts are passive — their whole description is the effect line.
	if item.get("type", "") == "artifact":
		return ["Passive artifact", str(item.get("effect", "")), "Found during a run (bar slot machine). Up to 3 stack."]
	var lines: Array = []
	var is_beam: bool       = item.get("beam_range") != null
	var is_melee: bool      = item.get("melee_range") != null
	var is_throwable: bool  = item.get("throwable", false)
	var is_placeable: bool  = item.get("placeable", false)
	var is_launcher: bool   = item.get("launcher", false)
	var is_gravity_well: bool = is_launcher and item.get("gravity_duration", 0.0) > 0.0
	var is_mine: bool       = item.get("mine", false)

	var dmg = item.get("damage")
	if dmg != null:
		var suffix := "/sec" if is_beam \
			else ("/tick" if is_gravity_well else (" AOE" if (is_throwable or is_launcher or is_mine) else " per hit"))
		lines.append("Damage: %s%s" % [_fmt(dmg), suffix])
	if item.get("heal") != null:
		lines.append("Heal: %s" % _fmt(item["heal"]))
	if item.get("block") != null:
		lines.append("Block: %s" % _fmt(item["block"]))

	if item.get("heal_item", false):
		lines.append("Use: tap the blue heal button")
		if item.get("heal_full", false):
			lines.append("Heals to full")
		elif item.get("heal_instant") != null:
			lines.append("Heals %s instantly" % _fmt(item["heal_instant"]))
		if item.get("heal_regen_amount") != null:
			var interval: float = item["heal_regen_interval"] if item.get("heal_regen_interval") != null else 1.0
			lines.append("Regen: %s HP every %ss for %ss" % [_fmt(item["heal_regen_amount"]), _fmt(interval), _fmt(item["heal_regen_duration"])])
		if item.get("speed_boost_multiplier") != null:
			lines.append("Speed: %sx for %ss" % [_fmt(item["speed_boost_multiplier"]), _fmt(item.get("speed_boost_duration", 0.0))])
		if item.get("heal_dispenser", false):
			var d_interval: float = item.get("dispenser_interval", 5.0)
			var d_duration: float = item.get("dispenser_duration", 20.0)
			lines.append("Places a dispenser that drops a %s HP vial every %ss for %ss" % [
				_fmt(item.get("dispenser_heal_amount", 0)), _fmt(d_interval), _fmt(d_duration)])
			lines.append("Walk over a vial to heal — it disappears after one use")
		if item.get("shield", false):
			lines.append("Tap to toggle on/off — blocks all damage while on")
			lines.append("Absorbs %s HP total (persists across toggles), then breaks for good" % _fmt(item.get("block", 0)))
			lines.append("Button + HP bar stay up until it breaks, then both vanish")
			if item.get("shield_reflect", false):
				lines.append("Also reflects melee and laser hits straight back at the attacker")

	if item.get("fire_rate") != null:
		lines.append("Fire Rate: every %ss" % _fmt(item["fire_rate"]))
	if is_beam:
		var tick: float = item["beam_tick_interval"] if item.get("beam_tick_interval") != null else 1.0
		lines.append("Damage Tick: every %ss" % _fmt(tick))
	if item.get("sniper_charge_time") != null:
		lines.append("Charge Time: %ss (tap bar, then tap target)" % _fmt(item["sniper_charge_time"]))
	if item.get("thrown_melee", false):
		var t_radius: float = item["thrown_radius"] if item.get("thrown_radius") != null else 100.0
		lines.append("Hitbox Radius: %spx (out and back)" % _fmt(t_radius))
		lines.append("Thrown — flies until it hits a wall, then returns")

	var range_val = item.get("melee_range") if is_melee else item.get("beam_range")
	if range_val != null:
		lines.append("Range: %spx" % _fmt(range_val))

	if is_melee or is_beam:
		var arc = item.get("melee_arc_degrees") if is_melee else item.get("beam_arc_degrees")
		if arc == null and is_melee:
			arc = 100.0 # matches player.gd's DEFAULT_MELEE_ARC_DEGREES
		if arc != null:
			lines.append("Hitbox Cone: %s°" % _fmt(arc))

	if item.get("melee_hits") != null and item["melee_hits"] > 1:
		lines.append("Hits per Swing: %d (staggered)" % item["melee_hits"])

	if item.get("knockback") != null:
		lines.append("Knockback: %s px/s" % _fmt(item["knockback"]))

	if item.get("stun") != null and item["stun"] > 0.0:
		lines.append("Stun: %ss" % _fmt(item["stun"]))

	if item.get("freeze_duration") != null and item["freeze_duration"] > 0.0:
		lines.append("Freeze: %ss" % _fmt(item["freeze_duration"]))
		lines.append("Thaws into a 50% speed slow for 3s")

	if item.get("burn_damage") != null and item.get("burn_duration") != null:
		lines.append("Burn: %s dmg/s for %ss" % [_fmt(item["burn_damage"]), _fmt(item["burn_duration"])])

	if item.get("wave_max_width") != null:
		lines.append("Max Wave Width: %spx" % _fmt(item["wave_max_width"]))

	if item.get("barrel_offset") != null and item["barrel_offset"] > 0.0:
		lines.append("Throws Two, Staggered" if item.get("thrown_melee", false) else "Dual Barrel")

	if item.get("bullet_speed") != null:
		lines.append("Bullet Speed: %s px/s" % _fmt(item["bullet_speed"]))

	if is_placeable:
		lines.append("Deployable Turret")

	if item.get("grapple", false):
		lines.append("Aim the green joystick, release to fire")
		lines.append("Hits a wall: dashes you to it")
		lines.append("Hits an enemy: drags it 20px in front of you")
		if item.get("scaleable_throw", false):
			lines.append("Range scales with how far you drag the joystick")
	elif item.get("teleport", false):
		lines.append("Aim anywhere on the map with the green joystick")
		lines.append("Shows a floating dotted circle — release to teleport there")
		if item.get("throw_distance") != null:
			lines.append("Max Range: %spx" % _fmt(item["throw_distance"]))
	elif is_throwable:
		if item.get("throw_distance") != null:
			if item.get("scaleable_throw", false):
				lines.append("Throw Distance: up to %spx (scales with joystick drag)" % _fmt(item["throw_distance"]))
			else:
				lines.append("Throw Distance: %spx" % _fmt(item["throw_distance"]))
		if item.get("aoe_radius") != null:
			lines.append("Blast Radius: %spx" % _fmt(item["aoe_radius"]))
		if item.get("explode_delay") != null:
			lines.append("Fuse: %ss" % _fmt(item["explode_delay"]))
		if item.get("confuse_duration") != null and item["confuse_duration"] > 0.0:
			lines.append("Confuses enemies in the blast for %ss (reversed movement)" % _fmt(item["confuse_duration"]))
		if item.get("linger_duration") != null and item["linger_duration"] > 0.0:
			lines.append("Fire lingers for %ss: burns for %s dmg/s for %ss" % [
				_fmt(item["linger_duration"]), _fmt(item.get("linger_burn_damage", 0)), _fmt(item.get("linger_burn_duration", 0.0))])
		if item.get("distract_duration") != null and item["distract_duration"] > 0.0:
			lines.append("Pulls every enemy on the map toward it for %ss (no damage)" % _fmt(item["distract_duration"]))
		if item.get("flash_duration") != null and item["flash_duration"] > 0.0:
			lines.append("Blinds enemies in the blast for %ss: their attacks/shots miss you" % _fmt(item["flash_duration"]))
		if item.get("mesh_count") != null and item["mesh_count"] > 0:
			var mesh_radius: float = item.get("aoe_radius", 0.0) * item.get("mesh_radius_ratio", 0.25)
			lines.append("Then pops %d mini grenades around the blast edge, each %s dmg in a %spx radius (stacks if overlapping)" % [
				item["mesh_count"], _fmt(item.get("mesh_damage", 0)), _fmt(mesh_radius)])

	if item.get("sticky", false):
		lines.append("Direct hit: sticks for %ss, then %s dmg" % [_fmt(item.get("sticky_delay", 0.0)), _fmt(item.get("sticky_damage", 0))])
		lines.append("Miss: explodes for the AOE damage/radius above instead")

	if is_mine:
		lines.append("Use: tap the green equipment button to place")
		lines.append("Button turns red once armed — tap again to detonate")
		if item.get("aoe_radius") != null:
			lines.append("Blast Radius: %spx" % _fmt(item["aoe_radius"]))

	if item.get("force_push", false):
		lines.append("Use: aim and hold the green joystick")
		if item.get("force_push_range") != null:
			lines.append("Push Range: %spx" % _fmt(item["force_push_range"]))
		if item.get("force_push_arc_degrees") != null:
			lines.append("Hitbox Cone: %s°" % _fmt(item["force_push_arc_degrees"]))
		lines.append("Mana: %s, drains %s/sec while held (does not regenerate)" % [
			_fmt(item.get("force_push_mana_max", 0.0)), _fmt(item.get("force_push_mana_drain_rate", 0.0))])

	if item.get("barrier", false):
		lines.append("Use: tap the green equipment button to start tracing")
		lines.append("Button turns red while tracing — tap again to finish early")
		if item.get("barrier_max_length") != null:
			lines.append("Max Length: %spx" % _fmt(item["barrier_max_length"]))
		lines.append("Blocks player/enemy movement — bullets and thrown equipment pass through")

	if item.get("hoverboard", false):
		lines.append("Use: tap the green equipment button to mount/dismount")
		if item.get("hoverboard_speed_multiplier") != null:
			lines.append("Speed: %sx while mounted" % _fmt(item["hoverboard_speed_multiplier"]))
		lines.append("No timer — stays on until you tap again")

	if item.get("invincible", false):
		lines.append("Use: tap the green equipment button to toggle")
		lines.append("Immune to all damage while active (purple glow)")
		lines.append("Mana: %s, drains %s/sec while active (does not regenerate)" % [
			_fmt(item.get("invincible_mana_max", 0.0)), _fmt(item.get("invincible_mana_drain_rate", 0.0))])

	if item.get("sidekick", false):
		lines.append("Passive — no button, active the whole run once equipped")
		lines.append("Follows 25px behind you and auto-fires at the nearest enemy")

	if item.get("summon", false):
		lines.append("Use: tap the gold \"%s\" button to summon" % item.get("summon_label", "SUMMON"))
		lines.append("Fires at the same rate/damage as the Assault Rifle Blaster")
		lines.append("Every 5s throws a random grenade at the nearest enemy")

	if item.get("battery", false):
		lines.append("Use: tap the green equipment button")
		if item.get("speed_boost_multiplier") != null:
			lines.append("Speed: %sx while active" % _fmt(item["speed_boost_multiplier"]))
		lines.append("Active: %ss per use" % _fmt(item.get("battery_active_duration", 0.0)))
		lines.append("5 uses per run (no recharge)")

	if is_launcher:
		if item.get("throw_distance") != null:
			lines.append("Fires: %spx ahead" % _fmt(item["throw_distance"]))
		if item.get("aoe_radius") != null:
			lines.append("AOE Radius: %spx" % _fmt(item["aoe_radius"]))
		if item.get("explode_delay") != null:
			lines.append("Fuse: %ss" % _fmt(item["explode_delay"]))
		if is_gravity_well:
			lines.append("Gravity Well: pulls enemies in for %ss" % _fmt(item["gravity_duration"]))
			var g_interval: float = item["gravity_tick_interval"] if item.get("gravity_tick_interval") != null else 0.5
			lines.append("Damage Tick: every %ss" % _fmt(g_interval))

	return lines

# ── Fusion workbench ─────────────────────────────────────────────────────────────────────────
# A drag-and-drop calculator for the fusion system: two slots, and every fusable weapon laid out
# below them. Drag a weapon into each slot and the result appears between them. Dragging a weapon
# back out of a slot empties it. Reference only — nothing here changes the save or the run.
#
# Drag-and-drop uses Godot's built-in Control drag protocol (_get_drag_data/_can_drop_data/
# _drop_data), which runs on mouse events; touch reaches it via the engine's default
# emulate_mouse_from_touch. The slots and chips are inner classes purely so they can override
# those three virtuals — everything else about them is built here.

const SLOT_EMPTY_BG  := Color(0.10, 0.13, 0.19)
const SLOT_FILLED_BG := Color(0.16, 0.21, 0.30)
const SLOT_HOVER_BG  := Color(0.20, 0.34, 0.55)
const FUSE_ICON      := 60.0
const CHIP_ICON      := 44.0

var _slot_a: Control = null
var _slot_b: Control = null
var _result_box: VBoxContainer = null

class FusionSlot extends PanelContainer:
	var list: Node = null
	var item_name := ""
	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("weapon")
	func _drop_data(_pos: Vector2, data: Variant) -> void:
		list._fill_slot(self, str(data["weapon"]))
	func _get_drag_data(_pos: Vector2) -> Variant:
		if item_name == "":
			return null
		var carried := item_name
		set_drag_preview(list._make_drag_preview(carried))
		list._fill_slot(self, "") # pulled out of the box = removed, per the drop rules
		return {"weapon": carried}

class FusionChip extends PanelContainer:
	var list: Node = null
	var item_name := ""
	func _get_drag_data(_pos: Vector2) -> Variant:
		set_drag_preview(list._make_drag_preview(item_name))
		return {"weapon": item_name}

# Every weapon that appears as a component of some fusion, in registry order.
func _fusable_weapons() -> Array:
	var names := {}
	for key in ItemRegistry.COMBINATIONS:
		for part in str(key).split("+"):
			names[part] = true
	var out: Array = []
	for it in ItemRegistry.ITEMS:
		if names.has(it.get("name", "")):
			out.append(it)
	return out

func _icon_for(item: Dictionary, size: float) -> TextureRect:
	var tex := TextureRect.new()
	tex.custom_minimum_size = Vector2(size, size)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path: String = "res://assets/icons/" + str(item.get("file", ""))
	if ResourceLoader.exists(path):
		tex.texture = load(path)
	return tex

func _box(bg: Color, radius: int = 12, pad: float = 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s

func _make_drag_preview(item_name: String) -> Control:
	var item: Dictionary = ItemRegistry.get_item_by_name(item_name)
	# A copy of the palette chip — same box, icon and name — so what follows your finger is
	# visibly the item you picked up. Offset so it sits above the touch point rather than under it.
	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = Vector2(92, 78)
	wrap.add_theme_stylebox_override("panel", _box(RARITY_BG.get(item.get("rarity",""), SLOT_FILLED_BG), 10, 6.0))
	wrap.modulate = Color(1, 1, 1, 0.9)
	wrap.position = Vector2(-46, -90)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	var icon := _icon_for(item, CHIP_ICON)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(icon)
	var nm := Label.new()
	nm.text = item_name
	nm.add_theme_font_size_override("font_size", 9)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	wrap.add_child(col)
	# set_drag_preview centres on the cursor; wrapping in a Control lets the offset above apply.
	var holder := Control.new()
	holder.add_child(wrap)
	return holder

func _build_fusion_tab() -> void:
	_slot_a = null
	_slot_b = null

	var hint := Label.new()
	hint.text = "Drag two weapons into the boxes to see what they fuse into.\nDrag one back out to clear it. Melee fuses with melee, ranged with ranged."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", PILL_INACTIVE_FG)
	_content.add_child(hint)

	# The two drop boxes, with a "+" between them.
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 10)
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_a = _make_slot("A")
	_slot_b = _make_slot("B")
	slots.add_child(_slot_a)
	var plus := Label.new()
	plus.text = "+"
	plus.add_theme_font_size_override("font_size", 26)
	plus.add_theme_color_override("font_color", PILL_INACTIVE_FG)
	plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slots.add_child(plus)
	slots.add_child(_slot_b)
	_content.add_child(slots)

	# Result panel, refreshed by _refresh_fusion_result.
	_result_box = VBoxContainer.new()
	_result_box.add_theme_constant_override("separation", 6)
	_content.add_child(_result_box)

	var sep := HSeparator.new()
	_content.add_child(sep)

	var palette_hdr := Label.new()
	var fusable := _fusable_weapons()
	palette_hdr.text = "Fusable weapons  %d" % fusable.size()
	palette_hdr.add_theme_font_size_override("font_size", 15)
	palette_hdr.add_theme_color_override("font_color", RARITY_LABEL["rare"])
	_content.add_child(palette_hdr)

	# Melee and ranged are listed separately, since a fusion can only pair like with like.
	for kind in ["Melee", "Ranged"]:
		var group: Array = fusable.filter(func(i): return ItemRegistry.weapon_kind_label(i) == kind)
		if group.is_empty():
			continue
		var sub := Label.new()
		sub.text = kind
		sub.add_theme_font_size_override("font_size", 12)
		sub.add_theme_color_override("font_color", PILL_INACTIVE_FG)
		_content.add_child(sub)
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		for it in group:
			grid.add_child(_make_chip(it))
		_content.add_child(grid)

	_refresh_fusion_result()

func _make_slot(label_text: String) -> Control:
	var slot := FusionSlot.new()
	slot.list = self
	slot.custom_minimum_size = Vector2(120, 120)
	slot.add_theme_stylebox_override("panel", _box(SLOT_EMPTY_BG))
	slot.set_meta("label", label_text)
	_paint_slot(slot)
	return slot

# Rebuilds a slot's contents from its item_name — empty shows the placeholder letter.
func _paint_slot(slot: Control) -> void:
	for c in slot.get_children():
		c.queue_free()
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	if slot.item_name == "":
		slot.add_theme_stylebox_override("panel", _box(SLOT_EMPTY_BG))
		var ph := Label.new()
		ph.text = str(slot.get_meta("label", ""))
		ph.add_theme_font_size_override("font_size", 30)
		ph.add_theme_color_override("font_color", Color(0.35, 0.40, 0.50))
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(ph)
	else:
		var item: Dictionary = ItemRegistry.get_item_by_name(slot.item_name)
		slot.add_theme_stylebox_override("panel", _box(RARITY_BG.get(item.get("rarity",""), SLOT_FILLED_BG)))
		var icon := _icon_for(item, FUSE_ICON)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(icon)
		var nm := Label.new()
		nm.text = slot.item_name
		nm.add_theme_font_size_override("font_size", 10)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(nm)
	slot.add_child(col)

func _fill_slot(slot: Control, item_name: String) -> void:
	slot.item_name = item_name
	_paint_slot(slot)
	_refresh_fusion_result()

func _make_chip(item: Dictionary) -> Control:
	var chip := FusionChip.new()
	chip.list = self
	chip.item_name = str(item.get("name", ""))
	chip.custom_minimum_size = Vector2(92, 78)
	chip.tooltip_text = chip.item_name
	chip.add_theme_stylebox_override("panel", _box(RARITY_BG.get(item.get("rarity",""), SLOT_FILLED_BG), 10, 6.0))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	var icon := _icon_for(item, CHIP_ICON)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(icon)
	var nm := Label.new()
	nm.text = chip.item_name
	nm.add_theme_font_size_override("font_size", 9)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	chip.add_child(col)
	return chip

# Shows the fused weapon for whatever the two slots currently hold: its icon, name, rarity and
# description, or the reason there's no result (nothing chosen / mismatched types / no such pair).
func _refresh_fusion_result() -> void:
	if _result_box == null or not is_instance_valid(_result_box):
		return
	_free_children(_result_box)
	var a: String = _slot_a.item_name if _slot_a != null else ""
	var b: String = _slot_b.item_name if _slot_b != null else ""

	if a == "" or b == "":
		_result_box.add_child(_status_label("Fill both boxes to see the fusion.", PILL_INACTIVE_FG))
		return

	var result: Dictionary = ItemRegistry.fusion_result(a, b)
	if result.is_empty():
		var ka := ItemRegistry.weapon_kind_label(ItemRegistry.get_item_by_name(a))
		var kb := ItemRegistry.weapon_kind_label(ItemRegistry.get_item_by_name(b))
		var why := "%s and %s don't fuse." % [a, b]
		if ka != kb:
			why = "%s is %s and %s is %s — a fusion needs two of the same type." % [a, ka, b, kb]
		_result_box.add_child(_status_label(why, Color(1.0, 0.55, 0.45)))
		return

	var rarity: String = result.get("rarity", "")
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(RARITY_BG.get(rarity, SLOT_FILLED_BG), 12, 12.0))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	row.add_child(_icon_for(result, FUSE_ICON))

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)

	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_theme_constant_override("separation", 4)
	var nm := Label.new()
	nm.text = str(result.get("name", ""))
	nm.add_theme_font_size_override("font_size", 17)
	name_row.add_child(nm)
	var tag := _make_element_tag(result, 13)
	if tag != null:
		name_row.add_child(tag)
	col.add_child(name_row)

	var sub := Label.new()
	sub.text = "%s  ·  %s" % [rarity.capitalize(), ItemRegistry.weapon_kind_label(result)]
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", RARITY_LABEL.get(rarity, PILL_INACTIVE_FG))
	col.add_child(sub)

	# Stats on the left, the weapon's own description to their right.
	var body := HBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 10)

	var stats: Array = _build_stat_lines(result)
	if not stats.is_empty():
		var d := Label.new()
		d.text = "\n".join(stats)
		d.custom_minimum_size = Vector2(118, 0)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_theme_font_size_override("font_size", 11)
		d.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
		body.add_child(d)

	var blurb := str(result.get("effect", ""))
	if blurb != "":
		var bl := Label.new()
		bl.text = blurb
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.add_theme_font_size_override("font_size", 11)
		bl.add_theme_color_override("font_color", Color(0.66, 0.72, 0.82))
		body.add_child(bl)

	col.add_child(body)

	row.add_child(col)
	panel.add_child(row)
	_result_box.add_child(panel)

func _status_label(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", col)
	return l
