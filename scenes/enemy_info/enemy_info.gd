extends Control

# Enemy bestiary. Pulls the live gameplay stats (HP, size, weapon, special, gold, color) straight
# from enemy_basic.gd's TYPES/WEAPON_DMG/WEAPON_CD so this screen can never drift from the actual
# enemies, and layers on presentation-only metadata (display names, weapon labels, readable
# special descriptions, and which floors each appears on). Rows tap to a detail popup — same
# smooth-scroll pattern as item_list.gd (decorative children pass touches through so a drag
# started anywhere scrolls the list).

const E := preload("res://scenes/enemies/enemy_basic.gd")

const ENEMY_ORDER := ["M", "L", "Void", "Warp", "Crater", "Cryo", "Solar", "Nebula", "Nova", "Boss1", "Boss2"]
const ENEMY_NAMES := {
	"M": "M Unit", "L": "L Unit", "Void": "Void Unit", "Warp": "Warp Unit",
	"Crater": "Crater Unit", "Cryo": "Cryo Unit", "Solar": "Solar Unit",
	"Nebula": "Nebula Unit", "Nova": "Nova Unit", "Boss1": "Boss 1", "Boss2": "Boss 2",
}
const COLOR_NAMES := {
	"M": "Orange", "L": "Blue", "Void": "Dark Grey", "Warp": "Purple",
	"Crater": "Brown", "Cryo": "Light Blue", "Solar": "Red",
	"Nebula": "Pink", "Nova": "Green", "Boss1": "Peach", "Boss2": "Black",
}
const APPEARS := {
	"M": "Any floor", "L": "Any floor",
	"Void": "Floor 10+", "Warp": "Floor 10+", "Crater": "Floor 10+",
	"Cryo": "Floor 20+", "Solar": "Floor 20+", "Nebula": "Floor 20+", "Nova": "Floor 20+",
	"Boss1": "Floor 15 (boss)", "Boss2": "Floor 25 (boss)",
}
const SPECIAL_DESC := {
	"": "None",
	"fast_fire":  "Fires twice as fast",
	"fast_swing": "Swings twice as fast",
	"teleport":   "Teleports to a random spot every 3s",
	"grenade":    "Throws a blast grenade every 3s",
	"boss1":      "Swings 3x as fast",
	"boss2":      "Fires 4x fast; every 10s teleports, then fires 8x for 2s",
}

const ROW_ICON := 44.0 # circle diameter used in the list rows (real size shown in the popup)

@onready var _content: VBoxContainer = $VBox/ScrollArea/Content

func _ready() -> void:
	SceneManager.add_glass_background(self)
	$VBox/Header/BtnBack.pressed.connect(func(): SceneManager.go_to("res://scenes/info/info.tscn"))
	for key in ENEMY_ORDER:
		_content.add_child(_make_row(key))

func _weapon_name(w: int) -> String:
	match w:
		E.Weapon.STAFF:  return "Staff"
		E.Weapon.LASER:  return "Laser Blaster"
		E.Weapon.FREEZE: return "Freeze Gun"
		E.Weapon.WAVE:   return "Wave Ray Gun"
		E.Weapon.FLAME:  return "Flame Thrower"
	return "?"

# fast_fire/fast_swing halve the base cooldown (matches enemy_basic.gd's configure_type).
func _fire_cd(w: int, special: String) -> float:
	var cd: float = E.WEAPON_CD[w]
	if special == "fast_fire" or special == "fast_swing":
		cd *= 0.5
	elif special == "boss1":
		cd /= 3.0
	elif special == "boss2":
		cd /= 4.0 # base rate (ramps to 8x for 2s after each teleport)
	return cd

func _fmt(value) -> String:
	if float(value) == floor(float(value)):
		return str(int(value))
	return "%.2f" % float(value)

# A flat circle in the enemy's color, used as its "icon" (enemies are drawn circles, no sprites).
func _make_circle(color: Color, diameter: float) -> Control:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	var r := int(diameter / 2.0)
	box.corner_radius_top_left     = r
	box.corner_radius_top_right    = r
	box.corner_radius_bottom_left  = r
	box.corner_radius_bottom_right = r
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box)
	panel.custom_minimum_size = Vector2(diameter, diameter)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel

func _make_row(key: String) -> Control:
	var t: Dictionary = E.TYPES[key]

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.13, 0.18)
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
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	row.add_child(_make_circle(t["color"], ROW_ICON))

	var name_col := VBoxContainer.new()
	name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.add_theme_constant_override("separation", 2)

	var lbl_name := Label.new()
	lbl_name.text = ENEMY_NAMES.get(key, key)
	lbl_name.add_theme_font_size_override("font_size", 15)
	lbl_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(lbl_name)

	var lbl_sub := Label.new()
	lbl_sub.text = "%s · %s" % [_weapon_name(t["weapon"]), APPEARS.get(key, "")]
	lbl_sub.add_theme_font_size_override("font_size", 11)
	lbl_sub.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	lbl_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(lbl_sub)

	row.add_child(name_col)

	var lbl_hp := Label.new()
	lbl_hp.text = "❤ %d" % int(t["hp"])
	lbl_hp.add_theme_font_size_override("font_size", 15)
	lbl_hp.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45))
	lbl_hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl_hp)

	# Invisible full-size tap button (PASS so drags still reach the ScrollContainer) — same
	# proven touch pattern as item_list.gd.
	var tap_btn := Button.new()
	tap_btn.flat = true
	tap_btn.focus_mode = Control.FOCUS_NONE
	tap_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	var empty_box := StyleBoxEmpty.new()
	tap_btn.add_theme_stylebox_override("normal",  empty_box)
	tap_btn.add_theme_stylebox_override("hover",   empty_box)
	tap_btn.add_theme_stylebox_override("pressed", empty_box)
	tap_btn.add_theme_stylebox_override("focus",   empty_box)
	tap_btn.pressed.connect(_show_enemy_popup.bind(key))
	panel.add_child(tap_btn)

	return panel

# ── Enemy detail popup ───────────────────────────────────────────────────

func _show_enemy_popup(key: String) -> void:
	var t: Dictionary = E.TYPES[key]

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	var dim_btn := Button.new()
	dim_btn.flat = true
	dim_btn.focus_mode = Control.FOCUS_NONE
	dim_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	var empty_box := StyleBoxEmpty.new()
	dim_btn.add_theme_stylebox_override("normal",  empty_box)
	dim_btn.add_theme_stylebox_override("hover",   empty_box)
	dim_btn.add_theme_stylebox_override("pressed", empty_box)
	dim_btn.add_theme_stylebox_override("focus",   empty_box)
	dim_btn.pressed.connect(overlay.queue_free)
	overlay.add_child(dim_btn)

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(300, 0)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.15, 0.21)
	sb.border_color = t["color"]
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
	lbl_name.text = ENEMY_NAMES.get(key, key)
	lbl_name.add_theme_font_size_override("font_size", 19)
	lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(lbl_name)
	var btn_close := Button.new()
	btn_close.text = "✕"
	btn_close.focus_mode = Control.FOCUS_NONE
	btn_close.custom_minimum_size = Vector2(34, 34)
	btn_close.pressed.connect(overlay.queue_free)
	header.add_child(btn_close)
	outer.add_child(header)

	var lbl_color := Label.new()
	lbl_color.text = "%s · %s" % [COLOR_NAMES.get(key, ""), APPEARS.get(key, "")]
	lbl_color.add_theme_font_size_override("font_size", 12)
	lbl_color.add_theme_color_override("font_color", t["color"])
	outer.add_child(lbl_color)

	var content_row := HBoxContainer.new()
	content_row.add_theme_constant_override("separation", 16)

	var icon_box := CenterContainer.new()
	icon_box.custom_minimum_size = Vector2(72, 72)
	icon_box.add_child(_make_circle(t["color"], float(t["radius"]) * 2.0))
	content_row.add_child(icon_box)

	var stats_col := VBoxContainer.new()
	stats_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_col.custom_minimum_size = Vector2(170, 0)
	stats_col.add_theme_constant_override("separation", 5)
	for line in _build_stat_lines(key):
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

func _build_stat_lines(key: String) -> Array:
	var t: Dictionary = E.TYPES[key]
	var w: int = t["weapon"]
	var special: String = t["special"]
	var lines: Array = []
	lines.append("HP: %d" % int(t["hp"]))
	lines.append("Size: %dpx diameter" % int(float(t["radius"]) * 2.0))
	lines.append("Weapon: %s" % _weapon_name(w))
	lines.append("Damage: %d per hit" % int(E.WEAPON_DMG[w]))
	lines.append("Attack Speed: every %ss" % _fmt(_fire_cd(w, special)))
	lines.append("Special: %s" % SPECIAL_DESC.get(special, "None"))
	lines.append("Gold Dropped: %d" % int(t["gold"]))
	return lines
