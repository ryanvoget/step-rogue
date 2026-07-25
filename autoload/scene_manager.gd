extends Node

const GLASS_BACKGROUND := preload("res://scenes/ui/glass_background.gd")

# Portrait viewport (480×854) for menus/UI; landscape (854×480) for the game — see
# _change_scene_covered. The game is played with the phone held sideways (the iOS host rotates to
# landscape when target_orientation flips), while every other screen stays portrait as before.
const PORTRAIT_SIZE  := Vector2i(480, 854)
const LANDSCAPE_SIZE := Vector2i(854, 480)
const ROTATE_COVER_TIME := 0.7 # seconds to wait for the device to finish rotating before the
                                # canvas is resized and the target scene loaded (all under the cover)
const FADE_TIME := 0.22 # black-screen fade in/out duration

var _is_landscape := false
var _cover: CanvasLayer = null
var _cover_rect: ColorRect = null
var _transitioning := false
var _default_aspect := -1 # the project's normal stretch aspect, captured once and restored after
                          # each rotation (we force IGNORE only while the cover is up)

func go_to(scene_path: String) -> void:
	# Menus are portrait. If we're leaving the landscape game, cover the rotation back to
	# portrait; menu→menu (already portrait) just swaps instantly with no cover.
	if _is_landscape:
		_change_scene_covered(scene_path, false)
	else:
		get_tree().change_scene_to_file(scene_path)

# Attaches the shared glassy-futuristic backdrop behind a menu/UI screen — hides any existing
# flat "Background" node and inserts the glass one at the back. Call from a screen's _ready.
func add_glass_background(screen: Control) -> void:
	var existing := screen.get_node_or_null("Background")
	if existing != null:
		existing.visible = false
	var bg: Control = GLASS_BACKGROUND.new()
	screen.add_child(bg)
	screen.move_child(bg, 0)

func go_to_menu() -> void:
	go_to("res://scenes/menu/menu.tscn")

func go_to_game() -> void:
	_change_scene_covered("res://scenes/world/world.tscn", true)

func go_to_sandbox() -> void:
	_change_scene_covered("res://scenes/sandbox/sandbox.tscn", true)

# Changes scene while the device rotates between portrait and landscape, hiding the awkward
# mid-rotation squish behind a full-screen loading cover. The trick is the stretch aspect:
# everything on screen — including the cover — lives in the Godot canvas, so with the normal
# "keep" aspect the canvas (and the cover with it) letterboxes/squishes as the window animates
# from one orientation to the other. While the cover is up we force IGNORE aspect, which stretches
# the canvas to always fill the window; on a solid cover that stretch is invisible, so the cover
# stays edge-to-edge through the whole rotation. Once rotated we resize the canvas to the new
# orientation, restore the real aspect, load the scene, and only then drop the cover.
func _change_scene_covered(scene_path: String, landscape: bool) -> void:
	if _transitioning:
		return
	_transitioning = true
	var win := get_window()
	if _default_aspect == -1 and win != null:
		_default_aspect = win.content_scale_aspect
	# Fade the current (correctly-oriented) scene down to black.
	_show_cover()
	await _fade_cover(1.0)
	# Fully black now — nothing visible to squish, so rotate. IGNORE aspect keeps the black rect
	# filling the window edge-to-edge as it animates (a solid black stretch is invisible).
	if win != null:
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	SaveManager.target_orientation = "landscape" if landscape else "portrait"
	await get_tree().create_timer(ROTATE_COVER_TIME).timeout
	# Rotation done: match the canvas to the new orientation and set the aspect. The game uses
	# EXPAND so the canvas grows to fill the whole screen edge-to-edge (room.gd resizes the map to
	# match); menus keep the project's normal aspect.
	_is_landscape = landscape
	if win != null:
		win.content_scale_size = LANDSCAPE_SIZE if landscape else PORTRAIT_SIZE
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND if landscape else _default_aspect
	get_tree().change_scene_to_file(scene_path)
	await get_tree().create_timer(0.15).timeout # let the new scene paint before revealing it
	# Fade the black back out to reveal the loaded scene in its new orientation.
	await _fade_cover(0.0)
	_hide_cover()
	_transitioning = false

# Tweens the black cover's opacity and waits for it to finish.
func _fade_cover(target_alpha: float) -> void:
	if _cover_rect == null or not is_instance_valid(_cover_rect):
		return
	var tw := create_tween()
	tw.tween_property(_cover_rect, "modulate:a", target_alpha, FADE_TIME)
	await tw.finished

# Full-screen plain-black cover on a top CanvasLayer, parented to the tree root so it survives
# change_scene_to_file. Starts fully transparent (modulate.a = 0) and is faded in/out by
# _fade_cover. Being solid black with no content, it never shows any stretch/squish while the
# window rotates underneath it.
func _show_cover() -> void:
	if _cover != null and is_instance_valid(_cover):
		return
	var layer := CanvasLayer.new()
	layer.layer = 128 # above every in-game (20) / menu layer
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(0, 0, 0, 1)
	rect.modulate = Color(1, 1, 1, 0) # faded in by _fade_cover
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(rect)
	get_tree().root.add_child(layer)
	_cover = layer
	_cover_rect = rect

func _hide_cover() -> void:
	if _cover != null and is_instance_valid(_cover):
		_cover.queue_free()
	_cover = null
	_cover_rect = null
