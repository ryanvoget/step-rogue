extends Control

@onready var _bank_total: Label  = $VBox/BankCard/CardVBox/BankTotal
@onready var _bank_meta:  Label  = $VBox/BankCard/CardVBox/BankMeta
@onready var _feedback:   Label  = $VBox/Feedback
@onready var _day_row:    HBoxContainer   = $VBox/DayScroll/DayRow
@onready var _day_scroll: ScrollContainer = $VBox/DayScroll

var _bridge: Node = null
# { "YYYY-MM-DD": total_steps_from_healthkit }
var _hk_by_day: Dictionary = {}
# Ordered oldest → newest; index 5 is today.
var _date_keys: Array = []
# Parallel array of PanelContainers, same order as _date_keys.
var _day_boxes: Array = []

# Tap tracking — distinguishes tap (sync day) from drag (scroll).
var _touch_start: Vector2 = Vector2.ZERO
var _dragging: bool = false
const _DRAG_THRESHOLD := 12.0

func _ready() -> void:
	$VBox/Header/BtnBack.pressed.connect(SceneManager.go_to_menu)
	$VBox/BtnSync.pressed.connect(_on_sync_pressed)
	$VBox/BtnClear.pressed.connect(_on_clear_pressed)
	_date_keys = _build_date_keys()
	_build_day_boxes()
	_refresh_bank()
	_connect_bridge()
	SaveManager.swift_request = "preview_steps"
	call_deferred("_scroll_to_today")

func _scroll_to_today() -> void:
	_day_scroll.scroll_horizontal = int(_day_scroll.get_h_scroll_bar().max_value)

# --- Date helpers (local time, not UTC) ---

func _build_date_keys() -> Array:
	var keys := []
	var today := Time.get_datetime_dict_from_system()
	var y := int(today["year"])
	var m := int(today["month"])
	var d := int(today["day"])
	for i in range(5, -1, -1):  # 5 days ago → today
		var date := _date_minus(y, m, d, i)
		keys.append("%04d-%02d-%02d" % [date[0], date[1], date[2]])
	return keys

func _date_minus(y: int, m: int, d: int, days: int) -> Array:
	d -= days
	while d < 1:
		m -= 1
		if m < 1:
			m = 12
			y -= 1
		d += _month_days(m, y)
	return [y, m, d]

func _month_days(m: int, y: int) -> int:
	var md := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if m == 2 and (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)):
		return 29
	return md[m - 1]

# --- Day boxes ---

func _build_day_boxes() -> void:
	var today_wd := int(Time.get_datetime_dict_from_system().get("weekday", 0))
	var names := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	for i in range(_date_keys.size()):
		var days_ago := 5 - i
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(90, 90)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.11, 0.16, 1.0)
		sb.corner_radius_top_left = 10
		sb.corner_radius_top_right = 10
		sb.corner_radius_bottom_right = 10
		sb.corner_radius_bottom_left = 10
		sb.content_margin_left = 8.0
		sb.content_margin_right = 8.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		panel.add_theme_stylebox_override("panel", sb)
		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		var lbl_day := Label.new()
		lbl_day.name = "LblDay"
		lbl_day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_day.add_theme_font_size_override("font_size", 11)
		if days_ago == 0:
			lbl_day.text = "Today"
			lbl_day.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
		else:
			var wd := (today_wd - days_ago + 70) % 7
			lbl_day.text = names[wd]
			lbl_day.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		var lbl_steps := Label.new()
		lbl_steps.name = "LblSteps"
		lbl_steps.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_steps.add_theme_font_size_override("font_size", 26)
		lbl_steps.text = "–"
		lbl_steps.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		var lbl_unit := Label.new()
		lbl_unit.name = "LblUnit"
		lbl_unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_unit.add_theme_font_size_override("font_size", 10)
		lbl_unit.text = "steps"
		lbl_unit.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		vbox.add_child(lbl_day)
		vbox.add_child(lbl_steps)
		vbox.add_child(lbl_unit)
		panel.add_child(vbox)
		_day_row.add_child(panel)
		_day_boxes.append(panel)

func _refresh_day_boxes() -> void:
	for i in range(_date_keys.size()):
		var key: String = _date_keys[i]
		var panel: PanelContainer = _day_boxes[i]
		var vbox := panel.get_child(0) as VBoxContainer
		var lbl_steps := vbox.get_node("LblSteps") as Label
		if not _hk_by_day.has(key):
			lbl_steps.text = "–"
			lbl_steps.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		else:
			var hk_total := int(_hk_by_day[key])
			var already  := int(SaveManager.synced_steps_by_day.get(key, 0))
			var unsynced: int = max(0, hk_total - already)
			lbl_steps.text = "%d" % unsynced
			if unsynced == 0:
				lbl_steps.add_theme_color_override("font_color", Color(0.3, 0.75, 0.35))
			else:
				lbl_steps.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))

# --- Touch tap detection ---

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_start = event.position
			_dragging = false
		else:
			if not _dragging:
				_check_day_box_tap(event.position)
	elif event is InputEventScreenDrag:
		if (event.position - _touch_start).length() > _DRAG_THRESHOLD:
			_dragging = true

func _check_day_box_tap(screen_pos: Vector2) -> void:
	for i in range(_day_boxes.size()):
		if _day_boxes[i].get_global_rect().has_point(screen_pos):
			_sync_day(_date_keys[i])
			return

func _sync_day(key: String) -> void:
	if not _hk_by_day.has(key):
		_show_feedback("info", "Tap '👟 Sync with Phone' to load step data first.")
		return
	var hk_total := int(_hk_by_day[key])
	var already  := int(SaveManager.synced_steps_by_day.get(key, 0))
	var unsynced: int = max(0, hk_total - already)
	if unsynced == 0:
		_show_feedback("info", "No new steps for %s." % key)
		return
	var new_count := SaveManager.process_synced_steps({key: hk_total})
	_refresh_bank()
	_refresh_day_boxes()
	_show_feedback("success", "+%d steps synced from %s!" % [new_count, key])

# --- Bank ---

func _refresh_bank() -> void:
	_bank_total.text = "%d" % SaveManager.step_bank
	var last := SaveManager.last_sync_date
	_bank_meta.text = "Last sync: " + ("Never" if last.is_empty() else last)

# --- Bridge ---

func _connect_bridge() -> void:
	_bridge = get_tree().root.get_node_or_null("__swiftgodotkit_bridge__")
	if _bridge == null:
		return
	_bridge.message_from_host.connect(_on_bridge_message)

# --- Button actions ---

func _on_sync_pressed() -> void:
	_show_feedback("info", "Syncing with Health app...")
	SaveManager.swift_request = "sync_steps"

func _on_clear_pressed() -> void:
	SaveManager.step_bank = 0
	SaveManager.last_sync_date = ""
	SaveManager.synced_steps_by_day = {}
	SaveManager.save()
	_hk_by_day = {}
	_refresh_bank()
	_refresh_day_boxes()
	_show_feedback("info", "Steps cleared. Fetching fresh data...")
	SaveManager.swift_request = "preview_steps"

# --- Bridge message handler ---

func _on_bridge_message(msg: Dictionary) -> void:
	var action := msg.get("action", "") as String
	match action:
		"steps_preview":
			for key in msg:
				if key != "action":
					_hk_by_day[key] = int(msg[key])
			_refresh_day_boxes()
		"steps_ready":
			var days := {}
			for key in msg:
				if key != "action":
					days[key] = int(msg[key])
					_hk_by_day[key] = int(msg[key])
			var new_count := SaveManager.process_synced_steps(days)
			_refresh_bank()
			_refresh_day_boxes()
			if new_count > 0:
				_show_feedback("success", "+%d steps synced from Health!" % new_count)
			else:
				_show_feedback("info", "Already up to date — no new steps.")
		"steps_unavailable":
			_show_feedback("error", "Health data unavailable.\nCheck Settings → Privacy → Health → Parsec.")

func _show_feedback(type: String, msg: String) -> void:
	_feedback.text = msg
	_feedback.visible = true
	var col: Color
	match type:
		"success": col = Color(0.2, 0.85, 0.35)
		"error":   col = Color(0.9, 0.3, 0.25)
		_:         col = Color(0.6, 0.8, 1.0)
	_feedback.add_theme_color_override("font_color", col)
