extends Control

@onready var _bank_total: Label    = $VBox/BankCard/CardVBox/BankTotal
@onready var _bank_meta:  Label    = $VBox/BankCard/CardVBox/BankMeta
@onready var _input:      LineEdit = $VBox/SyncForm/StepsInput
@onready var _feedback:   Label    = $VBox/Feedback

func _ready() -> void:
	$VBox/Header/BtnBack.pressed.connect(SceneManager.go_to_menu)
	$VBox/BtnSync.pressed.connect(_on_sync)
	_input.text_submitted.connect(func(_t): _on_sync())
	_refresh_bank()

func _refresh_bank() -> void:
	_bank_total.text = "%d" % SaveManager.step_bank
	var last := SaveManager.last_sync_date
	_bank_meta.text = "Last sync: " + ("Never" if last.is_empty() else last)

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
	var col := Color(0.2, 0.85, 0.35) if type == "success" else Color(0.9, 0.3, 0.25)
	_feedback.add_theme_color_override("font_color", col)
