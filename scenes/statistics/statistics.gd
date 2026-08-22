extends Control

# Statistics screen (Info → Statistics). Aggregates SaveManager.run_history — one record per finished
# run (recorded on death in world.gd's _record_run) — into balance-focused insights: where runs end,
# how far each weapon/rarity gets, average damage/economy, and a recent-runs log. Built entirely in
# code (like game_over.gd) so it adapts to however many runs exist.

const TEXT     := Color(0.90, 0.95, 1.0)
const TEXT_DIM := Color(0.60, 0.68, 0.80)
const ACCENT   := Color(0.30, 0.85, 1.0)
const WARN     := Color(1.0, 0.55, 0.35)
const GOOD     := Color(0.45, 0.90, 0.55)
const FIRST_BOSS_FLOOR := 15 # BOSS_FLOORS[0] — "before the first boss" means dying under this

const RARITY_COLOR := {
	"common": Color(0.70, 0.70, 0.75), "uncommon": Color(0.40, 0.90, 0.50),
	"rare": Color(0.35, 0.60, 1.0), "epic": Color(0.80, 0.45, 1.0), "legendary": Color(1.0, 0.82, 0.2),
}

@onready var _content: VBoxContainer = $VBox/Scroll/Content
var _clear_armed := false

func _ready() -> void:
	SceneManager.add_glass_background(self)
	$VBox/Header/BtnBack.pressed.connect(func(): SceneManager.go_to("res://scenes/info/info.tscn"))
	_rebuild()

func _rebuild() -> void:
	for c in _content.get_children():
		c.queue_free()
	var runs: Array = SaveManager.run_history
	if runs.is_empty():
		var empty := Label.new()
		empty.text = "No runs recorded yet.\nPlay a run — your stats show up here when it ends."
		empty.add_theme_font_size_override("font_size", 15)
		empty.add_theme_color_override("font_color", TEXT_DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_content.add_child(empty)
		return

	var n := runs.size()
	var wins := 0
	var early_deaths := 0 # died before the first boss
	var sum_floor := 0
	var best_floor := 0
	var sum_dmg := 0
	var sum_taken := 0
	var sum_kills := 0
	var sum_earned := 0
	var sum_spent := 0
	var sum_shots := 0
	var sum_hits := 0
	var sum_matt := 0
	var sum_mhit := 0
	var bands := [[1, 4], [5, 9], [10, 14], [15, 24], [25, 34], [35, 99999]]
	var band_labels := ["1–4", "5–9", "10–14", "15–24", "25–34", "35+"]
	var band_counts := [0, 0, 0, 0, 0, 0]
	var by_weapon := {}   # weapon -> {count, sum_floor, wins}
	var by_rarity := {}   # rarity -> {count, sum_floor}

	for r in runs:
		var fl: int = int(r.get("floor_died", 0))
		if bool(r.get("won", false)):
			wins += 1
		if fl < FIRST_BOSS_FLOOR and not bool(r.get("won", false)):
			early_deaths += 1
		sum_floor += fl
		best_floor = maxi(best_floor, fl)
		sum_dmg += int(r.get("damage_dealt", 0))
		sum_taken += int(r.get("damage_taken", 0))
		sum_kills += int(r.get("enemies_slain", 0))
		sum_earned += int(r.get("gold_earned", 0))
		sum_spent += int(r.get("gold_spent", 0))
		sum_shots += int(r.get("shots_fired", 0))
		sum_hits += int(r.get("shots_hit", 0))
		sum_matt += int(r.get("melee_attempts", 0))
		sum_mhit += int(r.get("melee_hits", 0))
		for i in bands.size():
			if fl >= bands[i][0] and fl <= bands[i][1]:
				band_counts[i] += 1
				break
		var wname: String = str(r.get("weapon", "(none)"))
		var wrec: Dictionary = by_weapon.get(wname, {"count": 0, "sum_floor": 0, "wins": 0})
		wrec["count"] += 1
		wrec["sum_floor"] += fl
		wrec["wins"] += 1 if bool(r.get("won", false)) else 0
		by_weapon[wname] = wrec
		var rar: String = str(r.get("weapon_rarity", ""))
		if rar != "":
			var rrec: Dictionary = by_rarity.get(rar, {"count": 0, "sum_floor": 0})
			rrec["count"] += 1
			rrec["sum_floor"] += fl
			by_rarity[rar] = rrec

	# ── Overview ─────────────────────────────────────────────────────────
	_add_section("Overview")
	_add_stat("Total Runs", str(n))
	_add_stat("Wins", "%d  (%d%%)" % [wins, int(round(100.0 * wins / n))])
	_add_stat("Avg Floor Reached", "%.1f" % (float(sum_floor) / n))
	_add_stat("Best Floor", str(best_floor))

	# The headline balance insight the user asked for.
	var early_pct := int(round(100.0 * early_deaths / n))
	_add_note("💀  %d of %d runs (%d%%) ended before the first boss (floor %d)." % [early_deaths, n, early_pct, FIRST_BOSS_FLOOR],
		WARN if early_pct >= 40 else TEXT_DIM)

	# ── Where runs end ───────────────────────────────────────────────────
	_add_section("Where Runs End (by floor)")
	var max_band: int = band_counts.max()
	for i in bands.size():
		var frac := float(band_counts[i]) / float(maxi(max_band, 1))
		var col: Color = WARN if i < 3 else GOOD
		_add_bar(band_labels[i], band_counts[i], frac, col)

	# ── Economy & combat averages ────────────────────────────────────────
	_add_section("Averages Per Run")
	_add_stat("Damage Dealt", str(int(round(float(sum_dmg) / n))))
	_add_stat("Damage Taken", str(int(round(float(sum_taken) / n))))
	_add_stat("Enemies Slain", str(int(round(float(sum_kills) / n))))
	_add_stat("Gold Earned", str(int(round(float(sum_earned) / n))))
	_add_stat("Gold Spent", str(int(round(float(sum_spent) / n))))
	_add_stat("Bullet Accuracy", _accuracy(sum_hits, sum_shots))
	_add_stat("Melee Accuracy", _accuracy(sum_mhit, sum_matt))

	# ── By starting weapon ───────────────────────────────────────────────
	_add_section("By Starting Weapon")
	var wkeys: Array = by_weapon.keys()
	wkeys.sort_custom(func(a, b): return by_weapon[a]["count"] > by_weapon[b]["count"])
	for wname in wkeys:
		var wr: Dictionary = by_weapon[wname]
		_add_stat("%s  ×%d" % [wname, wr["count"]], "avg floor %.1f" % (float(wr["sum_floor"]) / wr["count"]))

	# ── By weapon rarity ─────────────────────────────────────────────────
	if not by_rarity.is_empty():
		_add_section("By Weapon Rarity")
		for rar in ["legendary", "epic", "rare", "uncommon", "common"]:
			if not by_rarity.has(rar):
				continue
			var rr: Dictionary = by_rarity[rar]
			var row := _add_stat("%s  ×%d" % [rar.capitalize(), rr["count"]], "avg floor %.1f" % (float(rr["sum_floor"]) / rr["count"]))
			var lbl: Label = row.get_meta("label")
			lbl.add_theme_color_override("font_color", RARITY_COLOR.get(rar, TEXT_DIM))

	# ── Recent runs ──────────────────────────────────────────────────────
	_add_section("Recent Runs")
	var recent := runs.slice(maxi(0, n - 12))
	recent.reverse()
	for r in recent:
		var won: bool = bool(r.get("won", false))
		var head := "🏆 Won" if won else "☠ Floor %d" % int(r.get("floor_died", 0))
		var sub := "%s · %s" % [str(r.get("weapon", "?")), str(r.get("date", "")).left(16)]
		_add_run_row(head, sub, GOOD if won else WARN)

	# ── Clear ────────────────────────────────────────────────────────────
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	_content.add_child(spacer)
	var clear := Button.new()
	clear.text = "🗑  Clear Statistics"
	clear.custom_minimum_size = Vector2(0, 46)
	clear.add_theme_color_override("font_color", WARN)
	clear.pressed.connect(_on_clear.bind(clear))
	_content.add_child(clear)

func _on_clear(btn: Button) -> void:
	if not _clear_armed:
		_clear_armed = true
		btn.text = "⚠  Tap again to confirm"
		return
	SaveManager.clear_run_history()
	_clear_armed = false
	_rebuild()

# ── UI helpers ───────────────────────────────────────────────────────────
func _add_section(title: String) -> void:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 6)
	_content.add_child(sp)
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", ACCENT)
	_content.add_child(lbl)

func _add_stat(label_text: String, value_text: String) -> PanelContainer:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.15, 0.24, 0.55)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	row.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	row.add_child(hb)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", TEXT_DIM)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lbl)
	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 15)
	val.add_theme_color_override("font_color", TEXT)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(val)
	row.set_meta("label", lbl)
	_content.add_child(row)
	return row

func _add_bar(bar_name: String, count: int, frac: float, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = bar_name
	lbl.custom_minimum_size = Vector2(60, 0)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", TEXT_DIM)
	row.add_child(lbl)
	var track := HBoxContainer.new()
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.custom_minimum_size = Vector2(0, 18)
	var fill := ColorRect.new()
	fill.color = color
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.size_flags_stretch_ratio = maxf(frac, 0.0001)
	fill.custom_minimum_size = Vector2(0, 18)
	var rest := Control.new()
	rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rest.size_flags_stretch_ratio = maxf(1.0 - frac, 0.0001)
	track.add_child(fill)
	track.add_child(rest)
	row.add_child(track)
	var val := Label.new()
	val.text = str(count)
	val.custom_minimum_size = Vector2(32, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_font_size_override("font_size", 13)
	val.add_theme_color_override("font_color", TEXT)
	row.add_child(val)
	_content.add_child(row)

func _add_run_row(head: String, sub: String, color: Color) -> void:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.18, 0.5)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 7.0
	sb.content_margin_bottom = 7.0
	row.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	row.add_child(hb)
	var h := Label.new()
	h.text = head
	h.add_theme_font_size_override("font_size", 14)
	h.add_theme_color_override("font_color", color)
	h.custom_minimum_size = Vector2(96, 0)
	hb.add_child(h)
	var s := Label.new()
	s.text = sub
	s.add_theme_font_size_override("font_size", 12)
	s.add_theme_color_override("font_color", TEXT_DIM)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.clip_text = true
	hb.add_child(s)
	_content.add_child(row)

func _add_note(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(lbl)

func _accuracy(hit: int, total: int) -> String:
	if total <= 0:
		return "N/A"
	return "%d%%  (%d/%d)" % [int(round(100.0 * hit / total)), hit, total]
