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

const TYPE_ORDER  := ["all", "weapon", "equipment", "defensive", "artifact"]
const TYPE_LABELS := {
	"all":       "All",
	"weapon":    "Weapon",
	"equipment": "Equipment",
	"defensive": "Defense",
	"artifact":  "Artifact",
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
	# Artifacts show their effect description right in the row; other items show their type.
	if item.get("type", "") == "artifact":
		lbl_type.text = str(item.get("effect", ""))
		lbl_type.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl_type.custom_minimum_size = Vector2(180, 0)
	else:
		lbl_type.text = TYPE_LABELS.get(str(item.get("type", "")), "")
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

	var btn_close := Button.new()
	btn_close.text = "✕"
	btn_close.focus_mode = Control.FOCUS_NONE
	btn_close.custom_minimum_size = Vector2(34, 34)
	btn_close.pressed.connect(overlay.queue_free)
	header.add_child(btn_close)
	outer.add_child(header)

	var lbl_sub := Label.new()
	lbl_sub.text = "%s · %s" % [rarity.capitalize(), TYPE_LABELS.get(str(item.get("type", "")), "")]
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
