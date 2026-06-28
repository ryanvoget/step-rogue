extends Control

@onready var _bank_total: Label    = $VBox/BankCard/CardVBox/BankTotal
@onready var _bank_meta:  Label    = $VBox/BankCard/CardVBox/BankMeta
@onready var _input:      LineEdit = $VBox/SyncForm/StepsInput
@onready var _feedback:   Label    = $VBox/Feedback

var _hk_bridge = null

func _ready() -> void:
	$VBox/Header/BtnBack.pressed.connect(SceneManager.go_to_menu)
	$VBox/BtnSync.pressed.connect(_on_sync)
	_input.text_submitted.connect(func(_t): _on_sync())
	_refresh_bank()
	_try_health_bridge()

func _refresh_bank() -> void:
	_bank_total.text = "%d" % SaveManager.step_bank
	var last := SaveManager.last_sync_date
	_bank_meta.text = "Last sync: " + ("Never" if last.is_empty() else last)

func _try_health_bridge() -> void:
	if ClassDB.class_exists("HealthKitBridge"):
		_init_bridge("HealthKitBridge")
	elif ClassDB.class_exists("HealthConnectBridge"):
		_init_bridge("HealthConnectBridge")

func _init_bridge(class_name: String) -> void:
	_hk_bridge = ClassDB.instantiate(class_name)
	_hk_bridge.connect("steps_ready", _on_steps_ready)
	_hk_bridge.connect("health_unavailable", _on_health_unavailable)
	_show_feedback("info", "Reading health data...")
	_hk_bridge.request_and_fetch()

func _on_steps_ready(count: int) -> void:
	_input.text = str(count)
	_show_feedback("info", "Auto-filled %d steps. Tap Sync to deposit." % count)

func _on_health_unavailable() -> void:
	_feedback.visible = false

func _on_sync() -> void:
	var steps := _input.text.strip_edges().to_int()
	if steps <= 0:
		_show_feedback("error", "Please enter a valid step count.")
		return
	SaveManager.add_steps(steps)
	_input.text = ""
	_bank_total.text = "%d" % SaveManager.step_bank
	_bank_meta.text = "Last sync: Just now"
	_show_feedback("success", "+%d steps deposited!" % steps)

func _show_feedback(type: String, msg: String) -> void:
	_feedback.text = msg
	_feedback.visible = true
	var col: Color
	match type:
		"success": col = Color(0.2, 0.85, 0.35)
		"error":   col = Color(0.9, 0.3, 0.25)
		_:         col = Color(0.6, 0.8, 1.0)
	_feedback.add_theme_color_override("font_color", col)
