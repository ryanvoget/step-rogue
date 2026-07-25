extends Control

# Death screen shown by hud.gd (world/landscape). Two views:
#   1. GAME OVER panel with "Back to Menu" and "Statistics" buttons.
#   2. Run statistics — a cumulative-damage-per-floor line graph on the left, a stat list on the
#      right, and a "Return to Menu" button. Reads GameManager's stat_* counters.
# Built in code (the graph is data-driven) and lives on the HUD CanvasLayer so it renders in the
# game's landscape orientation. Styled glassy/space/futuristic to match the app. "Back to Menu"
# routes through SceneManager.go_to_menu() so the black fade + rotation back to portrait plays.

const GLASS_BG := preload("res://scenes/ui/glass_background.gd")

const ACCENT      := Color(0.35, 0.85, 1.00)
const TEXT        := Color(0.88, 0.92, 1.00)
const TEXT_DIM    := Color(0.60, 0.68, 0.82)
const DANGER      := Color(1.00, 0.35, 0.35)
const PANEL_BG    := Color(0.06, 0.09, 0.16, 0.92)
const PANEL_BORD  := Color(0.30, 0.60, 0.90, 0.55)
const GRAPH_LINE  := Color(0.35, 0.85, 1.00)
const GRAPH_AXIS  := Color(0.40, 0.55, 0.75, 0.45)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_show_game_over()

# ── iOS touch fallback: HUD-layer Buttons don't get InputEventMouseButton, so map a screen touch
# onto the button under it (same pattern as world.gd / menu.gd). ──
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		var btn := _find_button_at(self, event.position)
		if btn != null:
			btn.pressed.emit()
			get_viewport().set_input_as_handled()

# Hit-test via get_global_transform_with_canvas() (correct under the EXPAND stretch) against the
# raw touch position, rather than get_final_transform()/get_global_rect() which mismapped.
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

func _clear() -> void:
	for c in get_children():
		c.queue_free()

# ── View 1: GAME OVER ──────────────────────────────────────────────────────────
func _show_game_over() -> void:
	_clear()
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _glass_panel())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(340, 0)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", DANGER)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "You fell on floor %d" % GameManager.current_floor
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", TEXT_DIM)
	vbox.add_child(sub)

	vbox.add_child(_spacer(6))

	var stats_btn := _make_button("📊  Statistics", ACCENT)
	stats_btn.pressed.connect(_show_stats)
	vbox.add_child(stats_btn)

	var menu_btn := _make_button("Back to Menu", TEXT_DIM)
	menu_btn.pressed.connect(_to_menu)
	vbox.add_child(menu_btn)

# ── View 2: STATISTICS ─────────────────────────────────────────────────────────
func _show_stats() -> void:
	_clear()
	var bg: Control = GLASS_BG.new()
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "RUN STATISTICS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", ACCENT)
	root.add_child(title)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	# Left: graph panel
	var graph_panel := PanelContainer.new()
	graph_panel.add_theme_stylebox_override("panel", _glass_panel())
	graph_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_panel.size_flags_stretch_ratio = 1.25
	body.add_child(graph_panel)
	graph_panel.add_child(_build_graph())

	# Right: stat list panel
	var list_panel := PanelContainer.new()
	list_panel.add_theme_stylebox_override("panel", _glass_panel())
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(list_panel)
	list_panel.add_child(_build_stat_list())

	var menu_btn := _make_button("Return to Menu", ACCENT)
	menu_btn.custom_minimum_size = Vector2(0, 46)
	menu_btn.pressed.connect(_to_menu)
	root.add_child(menu_btn)

func _build_graph() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = "Cumulative Damage"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", TEXT_DIM)
	wrap.add_child(header)

	var graph := Control.new()
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.custom_minimum_size = Vector2(0, 240)
	graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graph.draw.connect(_render_graph.bind(graph))
	graph.resized.connect(graph.queue_redraw)
	wrap.add_child(graph)
	return wrap

# Cumulative-damage line, drawn via the CanvasItem `draw` signal (same technique as
# glass_background). Points are (floor, running-total damage) across floors 1..max.
func _render_graph(g: Control) -> void:
	var sz := g.size
	if sz.x <= 4.0 or sz.y <= 4.0:
		return
	var font := ThemeDB.fallback_font

	var by_floor: Dictionary = GameManager.stat_damage_by_floor
	var max_floor: int = maxi(GameManager.current_floor, 1)
	for k in by_floor.keys():
		max_floor = maxi(max_floor, int(k))

	# Build cumulative points.
	var pts: Array = []
	var cum := 0
	for f in range(1, max_floor + 1):
		cum += int(by_floor.get(f, 0))
		pts.append(Vector2(f, cum))
	var max_cum: int = cum

	var pad_l := 46.0
	var pad_b := 22.0
	var pad_t := 8.0
	var pad_r := 10.0
	var plot := Rect2(pad_l, pad_t, sz.x - pad_l - pad_r, sz.y - pad_t - pad_b)

	# Axes.
	g.draw_line(Vector2(plot.position.x, plot.position.y), Vector2(plot.position.x, plot.end.y), GRAPH_AXIS, 1.5)
	g.draw_line(Vector2(plot.position.x, plot.end.y), Vector2(plot.end.x, plot.end.y), GRAPH_AXIS, 1.5)

	if max_cum <= 0:
		g.draw_string(font, Vector2(plot.position.x + plot.size.x * 0.5 - 44, plot.position.y + plot.size.y * 0.5),
			"No damage dealt", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_DIM)
		return

	# Horizontal gridlines + y labels (0, mid, max).
	for i in range(0, 3):
		var frac := float(i) / 2.0
		var y := plot.end.y - plot.size.y * frac
		g.draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(0.4, 0.55, 0.75, 0.15), 1.0)
		var val := int(round(max_cum * frac))
		g.draw_string(font, Vector2(4, y + 4), str(val), HORIZONTAL_ALIGNMENT_LEFT, pad_l - 6, 10, TEXT_DIM)

	var fx := func(floor_x: float) -> float:
		if max_floor <= 1:
			return plot.position.x + plot.size.x * 0.5
		return plot.position.x + plot.size.x * (floor_x - 1.0) / float(max_floor - 1)
	var fy := func(v: float) -> float:
		return plot.end.y - plot.size.y * (v / float(max_cum))

	# X labels (first, mid, last floor).
	for f in [1, int(round((1 + max_floor) / 2.0)), max_floor]:
		g.draw_string(font, Vector2(fx.call(float(f)) - 4, plot.end.y + 16), str(f),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_DIM)

	# The line + points.
	var line_pts := PackedVector2Array()
	for p in pts:
		line_pts.append(Vector2(fx.call(p.x), fy.call(p.y)))
	if line_pts.size() >= 2:
		g.draw_polyline(line_pts, GRAPH_LINE, 2.5, true)
	# Cyan dots for every floor except the last — the floor the player died on gets a red X.
	for i in line_pts.size() - 1:
		g.draw_circle(line_pts[i], 3.0, GRAPH_LINE)
	if line_pts.size() > 0:
		var d: Vector2 = line_pts[line_pts.size() - 1]
		var r := 5.5
		var red := Color(1.0, 0.28, 0.28)
		g.draw_line(d + Vector2(-r, -r), d + Vector2(r, r), red, 2.5)
		g.draw_line(d + Vector2(-r, r), d + Vector2(r, -r), red, 2.5)
		g.draw_string(font, d + Vector2(-14, -10), "died", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, red)

func _build_stat_list() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	vbox.add_child(_stat_row("Floors Cleared", str(GameManager.stat_floors_cleared)))
	vbox.add_child(_stat_row("Total Damage", str(GameManager.stat_total_damage)))
	vbox.add_child(_stat_row("Enemies Slain", str(GameManager.stat_enemies_slain)))
	vbox.add_child(_stat_row("Bullet Accuracy", _accuracy(GameManager.stat_shots_hit, GameManager.stat_shots_fired)))
	vbox.add_child(_stat_row("Melee Accuracy", _accuracy(GameManager.stat_melee_hits, GameManager.stat_melee_attempts)))
	return vbox

func _accuracy(hit: int, total: int) -> String:
	if total <= 0:
		return "N/A"
	return "%d%%  (%d/%d)" % [int(round(100.0 * float(hit) / float(total))), hit, total]

func _stat_row(label_text: String, value_text: String) -> Control:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.15, 0.24, 0.55)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 9.0
	sb.content_margin_bottom = 9.0
	row.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	row.add_child(hb)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", TEXT_DIM)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lbl)

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 16)
	val.add_theme_color_override("font_color", TEXT)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(val)
	return row

# ── Shared styling ───────────────────────────────────────────────────────────
func _glass_panel() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	s.border_color = PANEL_BORD
	s.set_border_width_all(1)
	s.set_corner_radius_all(14)
	s.content_margin_left = 16.0
	s.content_margin_right = 16.0
	s.content_margin_top = 14.0
	s.content_margin_bottom = 14.0
	return s

func _make_button(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.add_theme_stylebox_override("normal",  _btn_box(accent, 0.16))
	b.add_theme_stylebox_override("hover",   _btn_box(accent, 0.30))
	b.add_theme_stylebox_override("pressed", _btn_box(accent, 0.42))
	b.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())
	return b

func _btn_box(accent: Color, fill: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(accent.r, accent.g, accent.b, fill)
	s.border_color = Color(accent.r, accent.g, accent.b, 0.7)
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_top = 10.0
	s.content_margin_bottom = 10.0
	return s

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _to_menu() -> void:
	GameManager.reset() # resets floor/coins and routes to the menu (fade + rotate to portrait)
