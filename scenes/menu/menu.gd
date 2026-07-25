extends Control

var _warn_label: Label = null # shown when Play is blocked by an over-budget loadout

func _ready() -> void:
	print("[Menu] _ready - scene loaded OK")
	var idle_tex := load("res://assets/Sprites/idle_spritesheet.png") as Texture2D
	var atlas := AtlasTexture.new()
	atlas.atlas = idle_tex
	atlas.region = Rect2(0, 0, 64, 64)
	$VBox/Header/Logo.texture = atlas
	$VBox/Buttons/PlayRow/BtnPlay.pressed.connect(_on_play_pressed)
	$VBox/Buttons/PlayRow/BtnTest.pressed.connect(SceneManager.go_to_sandbox)
	$VBox/Buttons/BtnSyncSteps.pressed.connect(func(): SceneManager.go_to("res://scenes/sync_steps/sync_steps.tscn"))
	$VBox/Buttons/BtnOpenCrate.pressed.connect(func(): SceneManager.go_to("res://scenes/open_crate/open_crate.tscn"))
	$VBox/Buttons/BtnInventory.pressed.connect(func(): SceneManager.go_to("res://scenes/inventory/inventory.tscn"))
	$VBox/Buttons/BtnCharacter.pressed.connect(func(): SceneManager.go_to("res://scenes/character/character.tscn"))
	$VBox/Buttons/BtnSettings.pressed.connect(func(): SceneManager.go_to("res://scenes/settings/settings.tscn"))
	$VBox/Buttons/BtnInfo.pressed.connect(func(): SceneManager.go_to("res://scenes/info/info.tscn"))
	SceneManager.add_glass_background(self)
	_apply_futuristic_theme()

	_warn_label = Label.new()
	_warn_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_warn_label.offset_top = -76.0
	_warn_label.offset_bottom = -40.0
	_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warn_label.add_theme_font_size_override("font_size", 15)
	_warn_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_warn_label.visible = false
	add_child(_warn_label)

# Start the run — but only if the equipped loadout is within the equipment-point budget.
func _on_play_pressed() -> void:
	if ItemRegistry.over_equipment_budget():
		_warn_label.text = "Loadout is %d / %d Equipment Points — trim it on the Character screen to play." % [
			ItemRegistry.equipped_points(), ItemRegistry.EQUIPMENT_POINT_BUDGET]
		_warn_label.visible = true
		await get_tree().create_timer(3.5).timeout
		if is_instance_valid(_warn_label):
			_warn_label.visible = false
		return
	SceneManager.go_to_game()

# ── Glassy-futuristic theme ─────────────────────────────────────────────────────────────────

func _apply_futuristic_theme() -> void:
	var t := Theme.new()
	t.set_stylebox("normal",  "Button", _glass_box(Color(0.30, 0.55, 0.85, 0.10), Color(0.35, 0.72, 0.95, 0.55), 1))
	t.set_stylebox("hover",   "Button", _glass_box(Color(0.32, 0.70, 0.95, 0.22), Color(0.55, 0.92, 1.0, 0.95), 2))
	t.set_stylebox("pressed", "Button", _glass_box(Color(0.18, 0.50, 0.85, 0.40), Color(0.60, 0.95, 1.0, 1.0), 2))
	t.set_stylebox("focus",   "Button", _glass_box(Color(0, 0, 0, 0),             Color(0.55, 0.92, 1.0, 0.6), 2))
	t.set_color("font_color",         "Button", Color(0.86, 0.95, 1.0))
	t.set_color("font_hover_color",   "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", Color(1, 1, 1))
	theme = t

	# Glowing cyan title via a soft outline; muted footer.
	var title: Label = $VBox/Header/Title
	title.add_theme_color_override("font_color", Color(0.62, 0.92, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.10, 0.55, 0.95, 0.85))
	title.add_theme_constant_override("outline_size", 6)
	$VBox/Footer.add_theme_color_override("font_color", Color(0.45, 0.58, 0.72))

	# Play button gets a warmer/brighter accent so it stands out as the primary action.
	var play: Button = $VBox/Buttons/PlayRow/BtnPlay
	play.add_theme_stylebox_override("normal",  _glass_box(Color(0.15, 0.65, 0.75, 0.18), Color(0.35, 0.95, 1.0, 0.8), 2))
	play.add_theme_stylebox_override("hover",   _glass_box(Color(0.20, 0.80, 0.90, 0.30), Color(0.60, 1.0, 1.0, 1.0), 2))
	play.add_theme_stylebox_override("pressed", _glass_box(Color(0.12, 0.60, 0.80, 0.45), Color(0.70, 1.0, 1.0, 1.0), 2))

func _glass_box(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(14)
	s.set_content_margin_all(10)
	return s

# No manual touch fallback: the buttons fire natively from InputEventScreenTouch (every other
# menu screen — inventory, settings, info, etc. — relies on this and works). The old manual
# fallback mismapped under the EXPAND stretch and, firing in addition to the native press, kicked
# off two scene changes in one frame → a crash on every button that navigates to another menu.
