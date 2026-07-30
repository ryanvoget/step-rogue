extends Node2D

# Static, screen-filling room (no scrolling). The world is drawn at 2x camera zoom (see
# world.gd/sandbox.gd's fixed camera), so this 522x240 room exactly fills an iPhone screen.
# The playable floor is tiled with the 32x32 "Tile Start" texture; walls hug the play area;
# doors sit on the four sides. Everything reads GameManager.play_rect / room_w / room_h for bounds.
const ROOM_W := 522.0   # full-bleed width of the widest iPhone at 2x zoom (854/2 safe .. 1044/2 full)
const ROOM_H := 240.0   # locked screen height at 2x zoom (480/2)
const TILE := 32.0      # one floor tile (Tile Start.png is 32x32)

# Playable area: 15x6 whole tiles (480x192), centered. Kept within the 2x-zoom safe width so the
# player can never walk off-screen in this no-scroll room, with a wall border around it.
const PLAY_TILES_X := 15
const PLAY_TILES_Y := 6
var _play := Rect2(
	(ROOM_W - PLAY_TILES_X * TILE) * 0.5,   # 21
	(ROOM_H - PLAY_TILES_Y * TILE) * 0.5,   # 24
	PLAY_TILES_X * TILE,                    # 480
	PLAY_TILES_Y * TILE)                    # 192

const WALL_T := 16.0   # collider thickness of the walls hugging the play area
const TILE_TEXTURE_PATH := "res://assets/Sprites/Floor Types/Tile Start.png"
var _floor_tex: Texture2D = load(TILE_TEXTURE_PATH)
var _wall_bodies: Array = [] # the StaticBody2D walls, tracked so a rebuild can replace them

const BORDER_COLOR := Color(0.07, 0.08, 0.12) # dark fill outside the play area (behind the walls)

# Door sides — indices match world.gd's SIDE_OFFSETS grid directions.
const SIDE_TOP    := 0
const SIDE_BOTTOM := 1
const SIDE_LEFT   := 2
const SIDE_RIGHT  := 3
const DOOR_W := 64.0                    # door gap width (2 tiles)
const DOOR_ZONE_DEPTH := WALL_T + 16.0  # how far the trigger zone reaches into the room
const ENTRY_INSET := WALL_T + 24.0      # where the player lands after walking through a door

const DOOR_LOCKED_COLOR := Color(0.95, 0.25, 0.20, 0.9) # red — locked until the room is cleared
const DOOR_OPEN_COLOR   := Color(0.25, 0.95, 0.55, 0.9) # green — an unlocked exit
const DOOR_BACK_COLOR   := Color(0.30, 0.65, 1.00, 0.9) # blue — the door the player came in through

var player_spawn_pos: Vector2
var enemy_spawn_positions: Array
var door_sides: Array = []  # sides with visible doors — set by world.gd via set_doors
var entry_side: int = -1    # which of those the player entered through (drawn blue once unlocked)
var doors_locked: bool = true

func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED # lets the floor draw_texture_rect tile
	_build_map()

# Publishes the fixed bounds, builds the walls, and lays out spawn points.
func _build_map() -> void:
	GameManager.room_w = ROOM_W
	GameManager.room_h = ROOM_H
	GameManager.play_rect = _play
	_build_walls()
	player_spawn_pos = _play.get_center()
	# Candidate enemy spots spread across the play area (more than the max count so world.gd can
	# pick the ones farthest from the entry door).
	var cy := _play.get_center().y
	enemy_spawn_positions = []
	for fx in [0.18, 0.32, 0.50, 0.68, 0.82, 0.40, 0.60, 0.25]:
		var x: float = _play.position.x + _play.size.x * fx
		enemy_spawn_positions.append(Vector2(x, cy))
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

# Trigger zone for a door: covers the wall gap at the play-area edge and reaches DOOR_ZONE_DEPTH
# inward, so the player walking into the (solid) wall behind the gap overlaps it (world.gd polls).
func door_zone(side: int) -> Rect2:
	var c := _play.get_center()
	match side:
		SIDE_TOP:    return Rect2(c.x - DOOR_W / 2.0, _play.position.y, DOOR_W, DOOR_ZONE_DEPTH)
		SIDE_BOTTOM: return Rect2(c.x - DOOR_W / 2.0, _play.end.y - DOOR_ZONE_DEPTH, DOOR_W, DOOR_ZONE_DEPTH)
		SIDE_LEFT:   return Rect2(_play.position.x, c.y - DOOR_W / 2.0, DOOR_ZONE_DEPTH, DOOR_W)
		SIDE_RIGHT:  return Rect2(_play.end.x - DOOR_ZONE_DEPTH, c.y - DOOR_W / 2.0, DOOR_ZONE_DEPTH, DOOR_W)
	return Rect2()

# Where the player appears when entering a room through the door on this side.
func entry_position(side: int) -> Vector2:
	var c := _play.get_center()
	match side:
		SIDE_TOP:    return Vector2(c.x, _play.position.y + ENTRY_INSET)
		SIDE_BOTTOM: return Vector2(c.x, _play.end.y - ENTRY_INSET)
		SIDE_LEFT:   return Vector2(_play.position.x + ENTRY_INSET, c.y)
		SIDE_RIGHT:  return Vector2(_play.end.x - ENTRY_INSET, c.y)
	return player_spawn_pos

# The wall-thickness rect a door gap occupies, for drawing the indicator.
func _door_gap_rect(side: int) -> Rect2:
	var c := _play.get_center()
	match side:
		SIDE_TOP:    return Rect2(c.x - DOOR_W / 2.0, _play.position.y - WALL_T, DOOR_W, WALL_T)
		SIDE_BOTTOM: return Rect2(c.x - DOOR_W / 2.0, _play.end.y, DOOR_W, WALL_T)
		SIDE_LEFT:   return Rect2(_play.position.x - WALL_T, c.y - DOOR_W / 2.0, WALL_T, DOOR_W)
		SIDE_RIGHT:  return Rect2(_play.end.x, c.y - DOOR_W / 2.0, WALL_T, DOOR_W)
	return Rect2()

func _draw() -> void:
	# Dark border fills the whole room; the playable floor is the 32x32 Tile Start texture tiled
	# across the play area; door indicators sit on top of the wall band.
	draw_rect(Rect2(0.0, 0.0, ROOM_W, ROOM_H), BORDER_COLOR)
	if _floor_tex != null:
		draw_texture_rect(_floor_tex, _play, true) # tile=true -> repeats the 32x32 tile
	for side in door_sides:
		var gap := _door_gap_rect(side)
		var frame_col := DOOR_LOCKED_COLOR
		if not doors_locked:
			frame_col = DOOR_BACK_COLOR if side == entry_side else DOOR_OPEN_COLOR
		draw_rect(gap, Color(0.03, 0.10, 0.06) if not doors_locked else Color(0.10, 0.04, 0.04))
		draw_rect(gap, frame_col, false, 2.0)

# Four walls hugging the playable area, extending outward into the dark border.
func _build_walls() -> void:
	for w in _wall_bodies:
		if is_instance_valid(w):
			w.queue_free()
	_wall_bodies.clear()
	var p := _play
	_wall(Vector2(p.position.x - WALL_T, p.position.y - WALL_T), Vector2(p.size.x + 2.0 * WALL_T, WALL_T)) # top
	_wall(Vector2(p.position.x - WALL_T, p.end.y),               Vector2(p.size.x + 2.0 * WALL_T, WALL_T)) # bottom
	_wall(Vector2(p.position.x - WALL_T, p.position.y),          Vector2(WALL_T, p.size.y))                # left
	_wall(Vector2(p.end.x,               p.position.y),          Vector2(WALL_T, p.size.y))                # right

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
