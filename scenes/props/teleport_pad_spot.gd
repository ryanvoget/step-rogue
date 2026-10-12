@tool
extends Marker2D

# Drop these into a tile map (e.g. boss map1.tscn) to choose where the exit teleport pads appear.
# Nothing shows here in game: world.gd's _spawn_exit_pads puts the real pads on these spots only
# once the room is finished (fight cleared and the reward crate picked). One pad per exit, filling
# spots in scene-tree order; exits beyond the number of spots fall back to the default row.

const GROUP := "teleport_pad_spot"

func _enter_tree() -> void:
	add_to_group(GROUP)

func _ready() -> void:
	visible = Engine.is_editor_hint()
	z_index = 50 # editor preview draws over the tile layers wherever it sits in the tree

func _draw() -> void:
	# Editor preview: the pad's 64px footprint.
	draw_rect(Rect2(-32, -32, 64, 64), Color(0.3, 0.85, 1.0, 0.25))
	draw_rect(Rect2(-32, -32, 64, 64), Color(0.3, 0.85, 1.0, 0.9), false, 2.0)
	draw_circle(Vector2.ZERO, 3.0, Color(0.3, 0.85, 1.0, 0.9))
