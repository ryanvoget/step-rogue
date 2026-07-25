extends Node2D

# The game is played in landscape and the room FILLS the actual screen: ROOM_W/ROOM_H are set to
# the live viewport size in _fit_to_viewport (called on ready and whenever the viewport resizes),
# so the map reaches the phone's edges and scales to any device — see SceneManager's EXPAND
# stretch aspect. Defaults match the base landscape canvas until the first fit runs.
var ROOM_W := 854.0
var ROOM_H := 480.0
const WALL_T := 28.0
# The bottom wall sits BOTTOM_INSET px above the canvas bottom, leaving a strip below the play
# area for the on-screen controls (joysticks/buttons drawn by mobile_controls). Left/right/top
# borders are unchanged — only the bottom is raised. PLAY_H is the resulting inner play height;
# all vertical geometry below derives from it so the whole room re-flows.
const BOTTOM_INSET := 100.0
var PLAY_H := ROOM_H - BOTTOM_INSET
var _wall_bodies: Array = [] # the StaticBody2D walls, tracked so a resize can rebuild them

# Door sides — indices match world.gd's SIDE_OFFSETS grid directions.
const SIDE_TOP    := 0
const SIDE_BOTTOM := 1
const SIDE_LEFT   := 2
const SIDE_RIGHT  := 3
const DOOR_W := 96.0 # width of the door gap along the wall
const DOOR_ZONE_DEPTH := WALL_T + 20.0 # how far the trigger zone reaches into the room — the
                                        # player (radius 14) pressed against the wall sits at
                                        # WALL_T + 14, comfortably inside this
const ENTRY_INSET := WALL_T + 40.0 # where the player lands after walking through a door —
                                    # past DOOR_ZONE_DEPTH so arriving never instantly re-triggers

const DOOR_LOCKED_COLOR := Color(0.95, 0.25, 0.20, 0.9) # red — locked until the room is cleared
const DOOR_OPEN_COLOR   := Color(0.25, 0.95, 0.55, 0.9) # green — an unlocked exit
const DOOR_BACK_COLOR   := Color(0.30, 0.65, 1.00, 0.9) # blue — the door the player came in through

var player_spawn_pos: Vector2
var enemy_spawn_positions: Array
var door_sides: Array = []  # sides with visible doors — set by world.gd via set_doors
var entry_side: int = -1    # which of those the player entered through (drawn blue once unlocked)
var doors_locked: bool = true

func _ready() -> void:
	_fit_to_viewport()
	# Re-fit whenever the canvas changes size (device rotation settling on load, or a different
	# device) so the map always fills the screen.
	get_viewport().size_changed.connect(_fit_to_viewport)
	# The stretch may not have settled on the exact same frame the scene loads (rotation is async),
	# so re-fit once more after this frame to pick up the final size.
	call_deferred("_fit_to_viewport")

# Resizes the room to the current viewport (canvas) size, rebuilds the walls, recomputes the
# spawn/door geometry, and publishes the bounds to GameManager for everything else to read.
func _fit_to_viewport() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return
	ROOM_W = vp.x
	ROOM_H = vp.y
	PLAY_H = ROOM_H - BOTTOM_INSET
	GameManager.room_w = ROOM_W
	GameManager.play_h = PLAY_H
	_build_walls()
	player_spawn_pos = Vector2(ROOM_W * 0.5, PLAY_H - 60.0)
	# More candidate spots than the max enemy count (5), so world.gd can pick the ones farthest
	# from the door the player just entered through and never spawn one right on top of them.
	enemy_spawn_positions = [
		Vector2(ROOM_W * 0.5,  100.0),
		Vector2(120.0,          PLAY_H * 0.35),
		Vector2(ROOM_W - 120.0, PLAY_H * 0.35),
		Vector2(120.0,          PLAY_H * 0.70),
		Vector2(ROOM_W - 120.0, PLAY_H * 0.70),
		Vector2(ROOM_W * 0.5,   PLAY_H * 0.5),
		Vector2(ROOM_W * 0.32,  PLAY_H * 0.5),
		Vector2(ROOM_W * 0.68,  PLAY_H * 0.5),
	]
	queue_redraw()

# All doors are drawn from the moment the player enters — red while locked (until the room is
# cleared), then the entry door turns blue (the way back) and the exits green.
func set_doors(p_entry_side: int, p_exit_sides: Array, p_locked: bool) -> void:
	entry_side = p_entry_side
	door_sides = p_exit_sides.duplicate()
	if p_entry_side != -1 and not door_sides.has(p_entry_side):
		door_sides.append(p_entry_side)
	doors_locked = p_locked
	queue_redraw()

# Trigger zone for a door: covers the wall gap and extends DOOR_ZONE_DEPTH into the room, so
# the player walking into the (still-solid) wall behind the gap overlaps it — world.gd polls
# these against the player position, no Area2D needed.
func door_zone(side: int) -> Rect2:
	match side:
		SIDE_TOP:    return Rect2(ROOM_W / 2.0 - DOOR_W / 2.0, 0.0, DOOR_W, DOOR_ZONE_DEPTH)
		SIDE_BOTTOM: return Rect2(ROOM_W / 2.0 - DOOR_W / 2.0, PLAY_H - DOOR_ZONE_DEPTH, DOOR_W, DOOR_ZONE_DEPTH)
		SIDE_LEFT:   return Rect2(0.0, PLAY_H / 2.0 - DOOR_W / 2.0, DOOR_ZONE_DEPTH, DOOR_W)
		SIDE_RIGHT:  return Rect2(ROOM_W - DOOR_ZONE_DEPTH, PLAY_H / 2.0 - DOOR_W / 2.0, DOOR_ZONE_DEPTH, DOOR_W)
	return Rect2()

# Where the player appears when entering a room through the door on this side.
func entry_position(side: int) -> Vector2:
	match side:
		SIDE_TOP:    return Vector2(ROOM_W / 2.0, ENTRY_INSET)
		SIDE_BOTTOM: return Vector2(ROOM_W / 2.0, PLAY_H - ENTRY_INSET)
		SIDE_LEFT:   return Vector2(ENTRY_INSET, PLAY_H / 2.0)
		SIDE_RIGHT:  return Vector2(ROOM_W - ENTRY_INSET, PLAY_H / 2.0)
	return player_spawn_pos

# The wall-thickness rect a door gap occupies, for drawing.
func _door_gap_rect(side: int) -> Rect2:
	match side:
		SIDE_TOP:    return Rect2(ROOM_W / 2.0 - DOOR_W / 2.0, 0.0, DOOR_W, WALL_T)
		SIDE_BOTTOM: return Rect2(ROOM_W / 2.0 - DOOR_W / 2.0, PLAY_H - WALL_T, DOOR_W, WALL_T)
		SIDE_LEFT:   return Rect2(0.0, PLAY_H / 2.0 - DOOR_W / 2.0, WALL_T, DOOR_W)
		SIDE_RIGHT:  return Rect2(ROOM_W - WALL_T, PLAY_H / 2.0 - DOOR_W / 2.0, WALL_T, DOOR_W)
	return Rect2()

func _draw() -> void:
	# Floor — only the play area (down to PLAY_H).
	draw_rect(Rect2(0, 0, ROOM_W, PLAY_H), Color(0.05, 0.04, 0.14))
	# Walls
	var wc := Color(0.14, 0.13, 0.32)
	# Bottom border band — the control strip below the play area, filled with the wall/border
	# colour so it reads as the map's bottom border (the on-screen joysticks/buttons sit on it,
	# off the playable floor) rather than a mismatched grey void.
	draw_rect(Rect2(0, PLAY_H, ROOM_W, ROOM_H - PLAY_H), wc)
	draw_rect(Rect2(0,            0,             ROOM_W, WALL_T), wc)
	draw_rect(Rect2(0,            PLAY_H-WALL_T, ROOM_W, WALL_T), wc)
	draw_rect(Rect2(0,            0,             WALL_T, PLAY_H), wc)
	draw_rect(Rect2(ROOM_W-WALL_T, 0,            WALL_T, PLAY_H), wc)
	# Doors: darker "opening" over the wall with a colored frame — red while locked, blue for
	# the door the player came in through, green for the unlocked exits.
	for side in door_sides:
		var gap := _door_gap_rect(side)
		var frame_col := DOOR_LOCKED_COLOR
		if not doors_locked:
			frame_col = DOOR_BACK_COLOR if side == entry_side else DOOR_OPEN_COLOR
		draw_rect(gap, Color(0.03, 0.10, 0.06) if not doors_locked else Color(0.10, 0.04, 0.04))
		draw_rect(gap, frame_col, false, 3.0)

func _build_walls() -> void:
	for w in _wall_bodies:
		if is_instance_valid(w):
			w.queue_free()
	_wall_bodies.clear()
	_wall(Vector2(0,             0            ), Vector2(ROOM_W, WALL_T))
	_wall(Vector2(0,             PLAY_H-WALL_T), Vector2(ROOM_W, WALL_T))
	_wall(Vector2(0,             0            ), Vector2(WALL_T, PLAY_H))
	_wall(Vector2(ROOM_W-WALL_T, 0            ), Vector2(WALL_T, PLAY_H))

func _wall(pos: Vector2, size: Vector2) -> void:
	var body  := StaticBody2D.new()
	body.position        = pos
	body.collision_layer = 8
	body.collision_mask  = 0

	var col   := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size   = size
	col.shape    = shape
	col.position = size * 0.5
	body.add_child(col)
	add_child(body)
	_wall_bodies.append(body)
