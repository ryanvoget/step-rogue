extends Node2D

# The room has two layouts, switched by world.gd via configure(kind):
#  • "combat"/"start": the 520x240 "Hallway v2" art drawn at MAP_SCALE (2x) → a 1040x480 room shown
#    at 1x camera zoom, exactly screen-filling (fixed camera). This is the original room.
#  • "bar": a 2080x480 room (2x the hallway width) with a low-detail placeholder floor drawn in code
#    (no PNG yet), which the camera SCROLLS across as the player moves (see world.gd's camera update).
# _play is the walkable floor; world reads GameManager.play_rect / room_w / room_h for all bounds.
const MAP_SCALE := 2.0
const COMBAT_W := 1040.0
const COMBAT_H := 480.0
const BAR_W := 2080.0 # 2x the hallway width; scrolls horizontally
const BAR_H := 480.0

var _kind := "combat"
var _room_w := COMBAT_W
var _room_h := COMBAT_H
# Walkable floor rect. Combat: measured to the hallway art. Bar: a wide band with wall margins.
var _play := Rect2(120.0, 102.0, 800.0, 276.0)

const WALL_T := 28.0   # collider thickness of the walls hugging the play area
const TOP_WALL_LIFT := 40.0 # top wall collider raised this far so the player can walk in front of it
const MAP_TEXTURE_PATH := "res://assets/Sprites/Floor Types/Hallway v2.png"
var _map_sprite: Sprite2D = null # the Hallway v2 art (combat only; hidden for the bar)
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

# Bar placeholder palette (low-detail; a PNG will replace this later).
const BAR_FLOOR_COLOR   := Color(0.14, 0.12, 0.20)
const BAR_WALL_COLOR    := Color(0.07, 0.06, 0.11)
const BAR_COUNTER_COLOR := Color(0.30, 0.22, 0.14)
const BAR_COUNTER_TOP   := Color(0.42, 0.31, 0.19)

var player_spawn_pos: Vector2
var enemy_spawn_positions: Array
var door_sides: Array = []  # sides with visible doors — set by world.gd via set_doors
var entry_side: int = -1    # which of those the player entered through (drawn blue once unlocked)
var doors_locked: bool = true

func _ready() -> void:
	configure("combat")

# Switches the room layout. Publishes bounds to GameManager, rebuilds the walls, lays out spawn
# points, and shows/hides the hallway art. Called by world.gd on every room change.
func configure(kind: String) -> void:
	_kind = kind
	if kind == "bar":
		_room_w = BAR_W
		_room_h = BAR_H
		_play = Rect2(90.0, 150.0, BAR_W - 180.0, 210.0) # wide walkable band with wall margins
	else:
		_room_w = COMBAT_W
		_room_h = COMBAT_H
		_play = Rect2(120.0, 102.0, 800.0, 276.0)
	_setup_map_sprite()
	_map_sprite.visible = (kind != "bar") # bar uses the drawn placeholder instead of the art
	GameManager.room_w = _room_w
	GameManager.room_h = _room_h
	GameManager.play_rect = _play
	_build_walls()
	player_spawn_pos = _play.get_center()
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

# Swaps the combat art to a specific Hallway variant (world.gd picks one whose baked-in doors match
# the room's entry/exit sides). All variants share the same floor + door positions, so only the
# texture changes — _play and the door geometry stay put. (No-op for bar rooms.)
func set_map_texture(path: String) -> void:
	if _map_sprite == null:
		_setup_map_sprite()
	if _kind == "bar":
		return
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
# player has actually walked up to the door. Uses _play, so it adapts to both room sizes.
func door_zone(side: int) -> Rect2:
	var c := _play.get_center()
	match side:
		SIDE_TOP:    return Rect2(c.x - DOOR_W / 2.0, _play.position.y - 62.0, DOOR_W, 50.0)
		SIDE_BOTTOM: return Rect2(c.x - DOOR_W / 2.0, _play.end.y - 28.0,      DOOR_W, 90.0)
		SIDE_LEFT:   return Rect2(_play.position.x - 80.0, c.y - DOOR_W / 2.0, 108.0, DOOR_W)
		SIDE_RIGHT:  return Rect2(_play.end.x - 28.0,      c.y - DOOR_W / 2.0, 108.0, DOOR_W)
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

# Closed outline (world coords) tracing each combat door's true trapezoid (hallway art perspective).
func _door_outline(side: int) -> PackedVector2Array:
	match side:
		SIDE_TOP:    return PackedVector2Array([Vector2(452,0),   Vector2(586,0),   Vector2(564,96),  Vector2(474,96),  Vector2(452,0)])
		SIDE_BOTTOM: return PackedVector2Array([Vector2(474,382), Vector2(564,382), Vector2(586,478), Vector2(452,478), Vector2(474,382)])
		SIDE_LEFT:   return PackedVector2Array([Vector2(0,172),   Vector2(0,306),   Vector2(114,284), Vector2(114,194), Vector2(0,172)])
		SIDE_RIGHT:  return PackedVector2Array([Vector2(1040,172),Vector2(1040,306),Vector2(926,284), Vector2(926,194), Vector2(1040,172)])
	return PackedVector2Array()

# Simple rectangular door marker at the play-area edge (used for the bar's drawn doors).
func _bar_door_rect(side: int) -> Rect2:
	var c := _play.get_center()
	match side:
		SIDE_TOP:    return Rect2(c.x - DOOR_W / 2.0, _play.position.y - 18.0, DOOR_W, 18.0)
		SIDE_BOTTOM: return Rect2(c.x - DOOR_W / 2.0, _play.end.y, DOOR_W, 18.0)
		SIDE_LEFT:   return Rect2(_play.position.x - 18.0, c.y - DOOR_W / 2.0, 18.0, DOOR_W)
		SIDE_RIGHT:  return Rect2(_play.end.x, c.y - DOOR_W / 2.0, 18.0, DOOR_W)
	return Rect2()

func _draw() -> void:
	if _kind == "bar":
		_draw_bar()
		return
	# Combat: the floor/walls come from the Hallway art; only the door status outlines are drawn.
	for side in door_sides:
		var frame_col := DOOR_LOCKED_COLOR
		if not doors_locked:
			frame_col = DOOR_BACK_COLOR if side == entry_side else DOOR_OPEN_COLOR
		draw_polyline(_door_outline(side), frame_col, 3.0)

# Low-detail placeholder for the bar (a PNG will replace this): dark walls, a lighter floor band, a
# bar counter across the middle, and coloured door markers on the edges.
func _draw_bar() -> void:
	draw_rect(Rect2(0.0, 0.0, _room_w, _room_h), BAR_WALL_COLOR)
	draw_rect(_play, BAR_FLOOR_COLOR)
	# Bar counter in the middle — a long rectangle with a lighter top edge (the bartender stands behind).
	var c := _play.get_center()
	var counter := Rect2(c.x - 180.0, c.y - 8.0, 360.0, 46.0)
	draw_rect(counter, BAR_COUNTER_COLOR)
	draw_rect(Rect2(counter.position.x, counter.position.y, counter.size.x, 8.0), BAR_COUNTER_TOP)
	# A few stools in front of the counter.
	for i in range(5):
		var sx := counter.position.x + 40.0 + i * 70.0
		draw_circle(Vector2(sx, counter.end.y + 26.0), 9.0, BAR_COUNTER_TOP)
	# Door markers (green — bar doors are always open).
	for side in door_sides:
		var col := DOOR_BACK_COLOR if side == entry_side else DOOR_OPEN_COLOR
		draw_rect(_bar_door_rect(side), col)

# Four walls hugging the walkable floor.
func _build_walls() -> void:
	for w in _wall_bodies:
		if is_instance_valid(w):
			w.queue_free()
	_wall_bodies.clear()
	var p := _play
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
