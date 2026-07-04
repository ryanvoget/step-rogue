extends Control

func _ready() -> void:
	print("[Menu] _ready - scene loaded OK")
	var idle_tex := load("res://assets/Sprites/idle_spritesheet.png") as Texture2D
	var atlas := AtlasTexture.new()
	atlas.atlas = idle_tex
	atlas.region = Rect2(0, 0, 64, 64)
	$VBox/Header/Logo.texture = atlas
	$VBox/Buttons/PlayRow/BtnPlay.pressed.connect(SceneManager.go_to_game)
	$VBox/Buttons/PlayRow/BtnTest.pressed.connect(SceneManager.go_to_sandbox)
	$VBox/Buttons/BtnSyncSteps.pressed.connect(func(): SceneManager.go_to("res://scenes/sync_steps/sync_steps.tscn"))
	$VBox/Buttons/BtnOpenCrate.pressed.connect(func(): SceneManager.go_to("res://scenes/open_crate/open_crate.tscn"))
	$VBox/Buttons/BtnInventory.pressed.connect(func(): SceneManager.go_to("res://scenes/inventory/inventory.tscn"))
	$VBox/Buttons/BtnCharacter.pressed.connect(func(): SceneManager.go_to("res://scenes/character/character.tscn"))
	$VBox/Buttons/BtnSettings.pressed.connect(func(): SceneManager.go_to("res://scenes/settings/settings.tscn"))

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		print("[Menu] ScreenTouch pressed=", event.pressed, " pos=", event.position)
		if event.pressed:
			_handle_screen_touch(event.position)
	elif event is InputEventMouseButton:
		print("[Menu] MouseButton pressed=", event.pressed, " pos=", event.position)

# Direct touch fallback: ButtonNode.pressed only fires on InputEventMouseButton,
# but the embedded display server may not run emulate_mouse_from_touch.
# This manually checks which button the touch landed on and emits its signal.
func _handle_screen_touch(pixel_pos: Vector2) -> void:
	# pixel_pos comes from InputEventScreenTouch.position (screen pixels).
	# get_global_rect() returns canvas-space coords, so convert first.
	var canvas_pos := get_viewport().get_final_transform().affine_inverse() * pixel_pos
	print("[Menu] pixel=", pixel_pos, " canvas=", canvas_pos)
	var buttons := [
		$VBox/Buttons/PlayRow/BtnPlay,
		$VBox/Buttons/PlayRow/BtnTest,
		$VBox/Buttons/BtnSyncSteps,
		$VBox/Buttons/BtnOpenCrate,
		$VBox/Buttons/BtnInventory,
		$VBox/Buttons/BtnCharacter,
		$VBox/Buttons/BtnSettings,
	]
	for btn in buttons:
		if btn.get_global_rect().has_point(canvas_pos):
			print("[Menu] Touch activated: ", btn.name)
			btn.pressed.emit()
			get_viewport().set_input_as_handled()
			return
