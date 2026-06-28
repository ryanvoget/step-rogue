extends CanvasLayer

signal game_started

@onready var _health_bar:    ProgressBar  = $Panel/VBox/HealthBar
@onready var _floor_label:   Label        = $Panel/VBox/FloorLabel
@onready var _step_label:    Label        = $Panel/VBox/StepLabel
@onready var _cleared_label: Label        = $ClearedLabel
@onready var _start_overlay: Control      = $StartOverlay
@onready var _equipped_row:  HBoxContainer = $EquippedRow

func _ready() -> void:
	GameManager.health_changed.connect(_on_health)
	GameManager.floor_changed.connect(_on_floor)
	GameManager.room_cleared.connect(_on_room_cleared)
	GameManager.player_died.connect(_on_died)
	$BtnMenu.pressed.connect(_on_menu_pressed)
	$StartOverlay/BtnStart.pressed.connect(_on_start_pressed)
	_health_bar.max_value = 100
	_health_bar.value     = 100
	_setup_equipped_icons()

func _setup_equipped_icons() -> void:
	for key in ["equipped_weapon", "equipped_equipment", "equipped_defensive"]:
		var item: Dictionary = SaveManager.get(key)
		var slot_bg := ColorRect.new()
		slot_bg.custom_minimum_size = Vector2(38, 38)
		slot_bg.color = Color(0.08, 0.1, 0.15, 0.85)
		if not item.is_empty():
			var tex_rect := TextureRect.new()
			tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			tex_rect.texture      = load("res://assets/icons/" + item["file"])
			tex_rect.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			slot_bg.add_child(tex_rect)
		_equipped_row.add_child(slot_bg)

func _on_start_pressed() -> void:
	_start_overlay.visible = false
	game_started.emit()

func _process(_delta: float) -> void:
	_step_label.text = "Steps: %d" % GameManager.step_bank

func _on_health(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value     = current

func _on_floor(num: int) -> void:
	_floor_label.text = "Floor %d" % num
	_cleared_label.visible = false

func _on_room_cleared() -> void:
	_cleared_label.visible = true

func _on_died() -> void:
	await get_tree().create_timer(2.0).timeout
	GameManager.reset()

func _on_menu_pressed() -> void:
	GameManager.current_floor = 1
	SceneManager.go_to_menu()
