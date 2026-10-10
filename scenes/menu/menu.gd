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

# ── Holo theme ───────────────────────────────────────────────────────────────────────────────

const T := preload("res://scenes/ui/ui_theme.gd")
const HOLO_RING := preload("res://scenes/ui/holo_ring.gd")

func _apply_futuristic_theme() -> void:
	T.style_all_buttons($VBox/Buttons, T.CYAN)
	# Play is the primary action, so it takes the warm accent — the one amber element on a
	# screen that is otherwise entirely cyan, which is exactly how the reference console uses it.
	T.style_button($VBox/Buttons/PlayRow/BtnPlay, T.AMBER, 17)
	for b in [$VBox/Buttons/PlayRow/BtnPlay, $VBox/Buttons/PlayRow/BtnTest]:
		b.custom_minimum_size = Vector2(0, 52)

	var title: Label = $VBox/Header/Title
	title.add_theme_color_override("font_color", T.CYAN_HOT)
	title.add_theme_color_override("font_outline_color", Color(T.CYAN, 0.75))
	title.add_theme_constant_override("outline_size", 7)
	title.add_theme_font_size_override("font_size", 40)
	$VBox/Footer.add_theme_color_override("font_color", T.TEXT_DIM)

	_build_emblem()
	_play_intro()

# The rotating emblem sits BEHIND the character sprite, so the logo reads as a figure standing in
# a projection rather than as a badge next to one.
func _build_emblem() -> void:
	var logo: TextureRect = $VBox/Header/Logo
	var ring := HOLO_RING.new()
	ring.custom_minimum_size = Vector2(190, 190)
	ring.set_anchors_preset(Control.PRESET_CENTER)
	ring.size = Vector2(190, 190)
	ring.z_index = -1
	logo.add_child(ring)
	logo.resized.connect(func(): ring.position = logo.size * 0.5 - ring.size * 0.5)
	ring.position = logo.size * 0.5 - ring.size * 0.5
	logo.custom_minimum_size = Vector2(0, 150)

# Staggered entrance: the title fades down, then each button slides in from the left a beat
# apart. Cheap, but it makes the screen feel like it powers on rather than just appearing.
func _play_intro() -> void:
	var header: Control = $VBox/Header
	header.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(header, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC)

	# NEVER animate `position` here: these are children of a VBoxContainer, which owns their
	# positions and rewrites them on every sort. Reading position during _ready (before the first
	# layout pass) returned (0,0) for every button, and tweening them to that stacked all eight on
	# one spot — unselectable. `modulate` and `scale` are not container-managed, so the entrance
	# uses those instead and can never fight the layout.
	var i := 0
	for row in $VBox/Buttons.get_children():
		if not (row is Control):
			continue
		var c := row as Control
		c.modulate.a = 0.0
		var t2 := create_tween()
		t2.tween_interval(0.10 + 0.055 * float(i))
		t2.tween_property(c, "modulate:a", 1.0, 0.26)
		i += 1

# No manual touch fallback: the buttons fire natively from InputEventScreenTouch (every other
# menu screen — inventory, settings, info, etc. — relies on this and works). The old manual
# fallback mismapped under the EXPAND stretch and, firing in addition to the native press, kicked
# off two scene changes in one frame → a crash on every button that navigates to another menu.
