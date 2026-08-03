extends Node2D

# Static, screen-filling room (no scrolling). The 520x240 "Hallway v2" art is drawn at MAP_SCALE (2x)
# with NEAREST filtering, so the world is a 1040x480 room at 1x camera zoom (see world.gd/sandbox.gd)
# — the same world scale the game used before any map images, so player/enemy speeds, ranges, sizes
# and collisions keep their original tuning. The 2x is baked into the sprite (keeps pixels chunky),
# not the camera. _play is the walkable floor inside the walls; reads GameManager.play_rect/room_w/h.
const MAP_SCALE := 2.0
const ROOM_W := 1040.0  # 520 art x MAP_SCALE
const ROOM_H := 480.0   # 240 art x MAP_SCALE

# Walkable floor rect (art floor measured at ~x58..461, y49..190, x2 for world scale, inset a touch).
var _play := Rect2(120.0, 102.0, 800.0, 276.0)

const WALL_T := 28.0   # collider thickness of the walls hugging the play area (pre-map value)
const TOP_WALL_LIFT := 40.0 # top wall collider raised this far so the player can walk in front of it
const MAP_TEXTURE_PATH := "res://assets/Sprites/Floor Types/Hallway v2.png"
var _map_sprite: Sprite2D = null # the Hallway v2 art, shown at MAP_SCALE behind everything
var _wall_bodies: Array = []     # the StaticBody2D walls, tracked so a rebuild can replace them

# Door sides — indices match world.gd's SIDE_OFFSETS grid directions.
const SIDE_TOP    := 0
const SIDE_BOTTOM := 1
const SIDE_LEFT   := 2
const SIDE_RIGHT  := 3
const DOOR_W := 128.0                   # door trigger width (matches the ~136px art openings)
const DOOR_ZONE_DEPTH := WALL_T + 24.0  # how far the trigger zone reaches into the room
const ENTRY_INSET := WALL_T + 40.0      # where the player lands after walking through a door

const DOOR_LOCKED_COLOR := Color(0.95, 0.25, 0.20, 0.9) # red — locked until the room is cleared
const DOOR_OPEN_COLOR   := Color(0.25, 0.95, 0.55, 0.9) # green — an unlocked exit
const DOOR_BACK_COLOR   := Color(0.30, 0.65, 1.00, 0.9) # blue — the door the player came in through

var player_spawn_pos: Vector2
var enemy_spawn_positions: Array
var door_sides: Array = []  # sides with visible doors — set by world.gd via set_doors
var entry_side: int = -1    # which of those the player entered through (drawn blue once unlocked)
var doors_locked: bool = true

func _ready() -> void:
	_build_map()

# Places the map art, publishes the fixed bounds, builds the walls, and lays out spawn points.
func _build_map() -> void:
	_setup_map_sprite()
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

func _setup_map_sprite() -> void:
	if _map_sprite == null:
		_map_sprite = Sprite2D.new()
		_map_sprite.texture = load(MAP_TEXTURE_PATH)
		_map_sprite.centered = false          # top-left at (0,0)
		_map_sprite.scale = Vector2(MAP_SCALE, MAP_SCALE) # 520x240 art -> 1040x480 world
		_map_sprite.z_index = -10             # behind enemies, player, doors
		_map_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_map_sprite)
		move_child(_map_sprite, 0)

# Swaps the room art to a specific Hallway variant (world.gd picks one whose baked-in doors match
# the room's entry/exit sides). All variants share the same floor + door positions, so only the
# texture changes — _play and the door geometry stay put.
func set_map_texture(path: String) -> void:
	if _map_sprite == null:
		_setup_map_sprite()
	var tex: Texture2D = load(path)
	if tex != null and tex != _map_sprite.texture:
		_map_sprite.texture = tex
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

# Trigger zone for a door: a thin band right at the door mouth, so the room only changes once the
# player has actually walked up to the door (his center within ~12px of how far he can push toward
# it) — not while still out on the floor. The player checked here is his center; the bands account
# for how close he can get per side (the top clamp lets him press further up, in front of the wall).
func door_zone(side: int) -> Rect2:
	var c := _play.get_center()
	match side:
		SIDE_TOP:    return Rect2(c.x - DOOR_W / 2.0, _play.position.y - 62.0, DOOR_W, 50.0)   # center.y <= 90
		SIDE_BOTTOM: return Rect2(c.x - DOOR_W / 2.0, _play.end.y - 28.0,      DOOR_W, 90.0)   # center.y >= 350
		SIDE_LEFT:   return Rect2(_play.position.x - 80.0, c.y - DOOR_W / 2.0, 108.0, DOOR_W)  # center.x <= 148
		SIDE_RIGHT:  return Rect2(_play.end.x - 28.0,      c.y - DOOR_W / 2.0, 108.0, DOOR_W)  # center.x >= 892
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

# Closed outline (world coords) tracing each door's true trapezoid — the openings are perspective
# tunnels, wider at the outer map edge and narrower where they meet the floor. Measured from the PNG
# (art px x MAP_SCALE): e.g. top opening goes art (226,0)-(293,0) at the edge to (237,48)-(282,48)
# at the floor. So the status outline hugs the real door instead of a square.
func _door_outline(side: int) -> PackedVector2Array:
	match side:
		SIDE_TOP:    return PackedVector2Array([Vector2(452,0),   Vector2(586,0),   Vector2(564,96),  Vector2(474,96),  Vector2(452,0)])
		SIDE_BOTTOM: return PackedVector2Array([Vector2(474,382), Vector2(564,382), Vector2(586,478), Vector2(452,478), Vector2(474,382)])
		SIDE_LEFT:   return PackedVector2Array([Vector2(0,172),   Vector2(0,306),   Vector2(114,284), Vector2(114,194), Vector2(0,172)])
		SIDE_RIGHT:  return PackedVector2Array([Vector2(1040,172),Vector2(1040,306),Vector2(926,284), Vector2(926,194), Vector2(1040,172)])
	return PackedVector2Array()

func _draw() -> void:
	# The floor, walls and door openings all come from the Hallway art. Only the door status outlines
	# are drawn on top — a coloured trapezoid tracing each active door (red locked, blue = way back,
	# green = open exit) so the player can read which exits are available.
	for side in door_sides:
		var frame_col := DOOR_LOCKED_COLOR
		if not doors_locked:
			frame_col = DOOR_BACK_COLOR if side == entry_side else DOOR_OPEN_COLOR
		draw_polyline(_door_outline(side), frame_col, 3.0)

# Four walls hugging the walkable floor, extending outward into the dark wall art.
func _build_walls() -> void:
	for w in _wall_bodies:
		if is_instance_valid(w):
			w.queue_free()
	_wall_bodies.clear()
	var p := _play
	# The top wall collider is lifted TOP_WALL_LIFT above the floor edge so the player can walk up in
	# front of it (his feet reach the floor/wall line, body overlapping the wall) before colliding —
	# see player.gd's TOP_FEET_OVERLAP, which relaxes the top clamp to match.
	_wall(Vector2(p.position.x - WALL_T, p.position.y - WALL_T - TOP_WALL_LIFT), Vector2(p.size.x + 2.0 * WALL_T, WALL_T)) # top
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
