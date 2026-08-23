extends Node2D

# The room has six layouts, switched by world.gd via configure(kind). Art is authored at one of two
# scales: the "hallway convention" (half size, drawn at MAP_SCALE 2x) or 1:1. The player sprite is
# itself drawn at 2x, so hallway-convention art matches its pixel density and 1:1 art does not.
#  • "combat" (also shop/boss): a 520x240 "Hallway" variant at 2x -> 1040x480, exactly screen
#    filling, fixed camera. The original room.
#  • "control": the round Control Room, 1041x960 authored 1:1. Taller than the view, so the camera
#    scrolls vertically. Its walkable floor is a CIRCLE — see _build_ring_walls.
#  • "cockpit": 780x240 at 2x -> 1560x480. Same height as a hallway, half again as wide, scrolls
#    horizontally. Its doors are not centred on their edges, so it carries explicit door rects.
#  • "docking": 1041x960 authored 1:1, animated (26 frames). Only the lower slab is walkable;
#    the top half is the starfield window. No top door.
#  • "start": the Holding Bay lobby, 1041x960 at 2x -> 2082x1920, animated (6 frames). One door, at
#    the top of a corridor, and T-shaped bounds — see _build_lobby_walls.
#  • "bar": the cantina, 1041x960 authored 1:1. All four edges have a door.
# Rooms bigger than the view scroll (world.gd's _update_camera follows the player, clamped to the
# map). _play is the walkable floor; world reads GameManager.play_rect / room_w / room_h for bounds.
const MAP_SCALE := 2.0
const COMBAT_W := 1040.0
const COMBAT_H := 480.0
# "Bar": the cantina. Drawn 1:1 like the Control Room, so the room is exactly the art's 1041x960
# and every BAR_* value below is a raw measured art coordinate. All four edges have a door, each
# a rectangle jutting out of the floor slab at the map edge (see _door_outline).
const BAR_W := 1041.0
const BAR_H := 960.0
const BAR_TEXTURE := "res://assets/Sprites/Floor Types/Bar.png"
const BAR_PLAY := Rect2(45.0, 72.0, 954.0, 841.0) # floor slab (30,57)-(1014,928), inset
const BAR_COUNTER := Vector2(519.0, 479.0) # centre of the oval counter ring
const BAR_SCREEN := Vector2(163.0, 106.0)  # the blue screen, top-left
const BAR_DOOR_TOP := Rect2(451.0, 0.0, 138.0, 57.0)
const BAR_DOOR_BOTTOM := Rect2(451.0, 928.0, 138.0, 32.0)
const BAR_DOOR_LEFT := Rect2(0.0, 419.0, 30.0, 122.0)
const BAR_DOOR_RIGHT := Rect2(1014.0, 419.0, 27.0, 122.0)
# Starting room: the "Holding Bay" art (1041x960) drawn at MAP_SCALE like the hallways, so its
# pixel density matches the player sprite and the room comes out 2082x1920 — twice the width of a
# 1040-wide hallway room. Bigger than the view on both axes, so the camera scrolls to follow.
# Every LOBBY_* rect below is in WORLD units, i.e. the measured art coordinate x2.
const LOBBY_W := 2082.0
const LOBBY_H := 1920.0
const LOBBY_TEXTURE := "res://assets/Sprites/Floor Types/Holding Bay f%d.png"
const LOBBY_FRAMES := 6      # Holding Bay is a 6-frame loop (a sparkle on the console)
const LOBBY_FRAME_TIME := 0.1 # 100ms per frame, matching the source GIF
# Measured from the art: the floor slab the player can walk on (the corridor above it is art —
# the top door is a trigger at the slab's edge, like every other door), and the two barred
# holding cells at the bottom that the player starts inside.
const LOBBY_SLAB := Rect2(112.0, 808.0, 1856.0, 992.0)             # art (56,404,928,496) x2
const LOBBY_CELLS := [Vector2(386.0, 1594.0), Vector2(1690.0, 1594.0)] # art (193,797)/(845,797) x2
const LOBBY_CONSOLE := Vector2(1038.0, 1190.0)                     # art (519,595) x2 — the blue circle
# The long corridor running up out of the slab. It IS walkable (the walls are T-shaped — see
# _build_lobby_walls), and the door sits at the far top end of it rather than where it meets the
# slab, so the run opens with a walk up the full hallway.
const LOBBY_CORRIDOR_X0 := 924.0  # art 462 x2
const LOBBY_CORRIDOR_X1 := 1156.0 # art 578 x2
const LOBBY_CORRIDOR_TOP := 152.0 # art 76 x2 — player walks up to here; the dark doorway is above
const LOBBY_DOOR_RECT := Rect2(924.0, 0.0, 232.0, 152.0)
# "Control Room": a round room, also authored 1:1 at 1041x960 and also vertically scrolling. Its
# walkable floor is a CIRCLE, so _build_walls rings it with rotated segments instead of 4 rects.
# The four corridors in the art are decorative — doors are trigger zones at the wall, not openings.
const CONTROL_W := 1041.0
const CONTROL_H := 960.0
const CONTROL_TEXTURE := "res://assets/Sprites/Floor Types/Control Room.png"
const CONTROL_CENTER := Vector2(519.5, 479.5) # measured from the art
const CONTROL_RADIUS := 466.0                 # ...as is the floor circle's radius
const CONTROL_WALL_SEGMENTS := 40             # ring resolution; segments overlap slightly
# "Cockpit": hallway-convention art (780x240 drawn at 2x = 1560x480), so it's the same height as a
# hallway but half again as wide, and the camera scrolls horizontally. Its doors are NOT centred on
# each edge the way every other layout's are, so it carries explicit door rects. No RIGHT door —
# that edge is the windscreen. All rects are world units (measured art coordinates x2).
const COCKPIT_W := 1560.0
const COCKPIT_H := 480.0
const COCKPIT_TEXTURE := "res://assets/Sprites/Floor Types/Cockpit.png"
const COCKPIT_PLAY := Rect2(110.0, 60.0, 1350.0, 360.0)
const COCKPIT_DOOR_TOP := Rect2(446.0, 0.0, 134.0, 44.0)     # art x223..290
const COCKPIT_DOOR_BOTTOM := Rect2(448.0, 436.0, 134.0, 44.0) # art x224..291
const COCKPIT_DOOR_LEFT := Rect2(0.0, 172.0, 44.0, 134.0)     # art y86..153
# "Docking Bay": 1041x960 drawn 1:1, animated (26 frames of a ship crossing the window). Only the
# lower slab is walkable — the top half is the window. Doors are LEFT/RIGHT/BOTTOM (no top door,
# the window is there), each a rectangle jutting out of the slab's edge. Raw art coordinates.
const DOCK_W := 1041.0
const DOCK_H := 960.0
const DOCK_TEXTURE := "res://assets/Sprites/Floor Types/Docking Bay f%d.png"
const DOCK_FRAMES := 26
const DOCK_FRAME_TIME := 0.1
const DOCK_PLAY := Rect2(75.0, 540.0, 890.0, 395.0) # floor slab (60,526)-(980,949), inset
const DOCK_DOOR_LEFT := Rect2(29.0, 695.0, 31.0, 90.0)
const DOCK_DOOR_RIGHT := Rect2(980.0, 693.0, 27.0, 112.0)
const DOCK_DOOR_BOTTOM := Rect2(433.0, 935.0, 122.0, 25.0)

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

var player_spawn_pos: Vector2
var enemy_spawn_positions: Array
var door_sides: Array = []  # sides with visible doors — set by world.gd via set_doors
var entry_side: int = -1    # which of those the player entered through (drawn blue once unlocked)
var doors_locked: bool = true
var challenge_side: int = -1 # an exit that leads to a challenge room — drawn as a flashing red door

func _ready() -> void:
	configure("combat")

# Switches the room layout. Publishes bounds to GameManager, rebuilds the walls, lays out spawn
# points, and shows/hides the hallway art. Called by world.gd on every room change.
func configure(kind: String) -> void:
	_kind = kind
	if kind == "bar":
		_room_w = BAR_W
		_room_h = BAR_H
		_play = BAR_PLAY
	elif kind == "start":
		# The Holding Bay: one door at the top. The walkable slab is (32,380)-(1007,922) in the art
		# — everything above that is the corridor, which is scenery — inset so the player can't
		# stand inside the wall trim.
		_room_w = LOBBY_W
		_room_h = LOBBY_H
		# NOTE: _play must span the corridor as well as the slab. player.gd hard-clamps the player
		# to GameManager.play_rect every frame, so a slab-only rect makes the corridor unreachable
		# — an invisible wall across the hallway, no matter what the colliders say. The T shape is
		# enforced by _build_lobby_walls; this rect is just the outer bound.
		_play = Rect2(LOBBY_SLAB.position.x, LOBBY_CORRIDOR_TOP, LOBBY_SLAB.size.x, LOBBY_SLAB.end.y - LOBBY_CORRIDOR_TOP)
	elif kind == "control":
		# Round room. _play is the square the door zones hang off (door_zone/entry_position derive
		# from it), sized so each zone lands right at the circle's edge by its corridor mouth. The
		# actual walkable bound is the wall ring built in _build_walls, not this rect.
		_room_w = CONTROL_W
		_room_h = CONTROL_H
		_play = Rect2(120.0, 80.0, 800.0, 800.0)
	elif kind == "cockpit":
		_room_w = COCKPIT_W
		_room_h = COCKPIT_H
		_play = COCKPIT_PLAY
	elif kind == "docking":
		# Only the lower slab is walkable; the window above it is scenery.
		_room_w = DOCK_W
		_room_h = DOCK_H
		_play = DOCK_PLAY
	else:
		_room_w = COMBAT_W
		_room_h = COMBAT_H
		_play = Rect2(120.0, 102.0, 800.0, 276.0)
	_setup_map_sprite()
	# Hallway, Cockpit and Holding Bay art are drawn at MAP_SCALE (2x); Control Room, Bar and
	# Docking Bay are drawn 1:1, so those rooms are exactly their art's pixel dimensions.
	var one_to_one := kind == "control" or kind == "bar" or kind == "docking"
	_map_sprite.scale = Vector2.ONE if one_to_one else Vector2(MAP_SCALE, MAP_SCALE)
	_map_sprite.visible = true # every layout has real art now
	_set_map_animation(kind)
	if kind == "control":
		_map_sprite.texture = load(CONTROL_TEXTURE)
	elif kind == "cockpit":
		_map_sprite.texture = load(COCKPIT_TEXTURE)
	elif kind == "bar":
		_map_sprite.texture = load(BAR_TEXTURE)
	elif kind != "start" and kind != "docking": # those two are set by _set_map_animation
		# Reset to a hallway texture so a combat room entered straight after a Control Room never
		# briefly shows the round art; world.gd's set_map_texture then picks the matching variant.
		_map_sprite.texture = load(MAP_TEXTURE_PATH)
	GameManager.room_w = _room_w
	GameManager.room_h = _room_h
	GameManager.play_rect = _play
	_build_walls()
	# Lobby: start locked in one of the two holding cells (picked at random), so the run opens
	# with a walk up out of the cell toward the single top door.
	if kind == "start":
		player_spawn_pos = LOBBY_CELLS[randi() % LOBBY_CELLS.size()]
	else:
		player_spawn_pos = _play.get_center()
	var cy := _play.get_center().y
	enemy_spawn_positions = []
	for fx in [0.18, 0.32, 0.50, 0.68, 0.82, 0.40, 0.60, 0.25]:
		var x: float = _play.position.x + _play.size.x * fx
		enemy_spawn_positions.append(Vector2(x, cy))
	queue_redraw()

# ── Animated room art ────────────────────────────────────────────────────────────────────────
# Two rooms are frame animations extracted from source GIFs: the Holding Bay (6 frames, a sparkle
# on the console) and the Docking Bay (26 frames, a ship crossing the window). Frames are loaded
# once per room and cycled by a Timer rather than an AnimatedSprite2D, so the rest of the room code
# keeps treating _map_sprite as a plain Sprite2D with a swappable texture (set_map_texture, scale,
# z_index...). _anim_kind records which room the loaded frames belong to, so switching rooms
# reloads instead of playing the previous room's frames.
var _anim_frames: Array[Texture2D] = []
var _anim_kind := ""
var _anim_index := 0
var _anim_timer: Timer = null

# Starts (or restarts) the frame loop for `kind`, or stops it when that kind isn't animated.
func _set_map_animation(kind: String) -> void:
	var path_fmt := ""
	var count := 0
	var frame_time := 0.1
	if kind == "start":
		path_fmt = LOBBY_TEXTURE
		count = LOBBY_FRAMES
		frame_time = LOBBY_FRAME_TIME
	elif kind == "docking":
		path_fmt = DOCK_TEXTURE
		count = DOCK_FRAMES
		frame_time = DOCK_FRAME_TIME
	else:
		if _anim_timer != null:
			_anim_timer.stop()
		_anim_kind = ""
		return
	if _anim_kind != kind:
		_anim_frames.clear()
		for i in range(count):
			var t: Texture2D = load(path_fmt % i)
			if t != null:
				_anim_frames.append(t)
		_anim_kind = kind
	if _anim_frames.is_empty():
		return # art missing — leave whatever texture is set rather than blanking the room
	_anim_index = 0
	_map_sprite.texture = _anim_frames[0]
	if _anim_timer == null:
		_anim_timer = Timer.new()
		_anim_timer.timeout.connect(_advance_map_frame)
		add_child(_anim_timer)
	_anim_timer.wait_time = frame_time
	_anim_timer.start()

func _advance_map_frame() -> void:
	if _anim_frames.is_empty() or _anim_kind != _kind:
		return
	_anim_index = (_anim_index + 1) % _anim_frames.size()
	_map_sprite.texture = _anim_frames[_anim_index]

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
	if _kind == "bar" or _kind == "start" or _kind == "control":
		return # these own their own art (drawn placeholder / animated lobby / the round room);
		       # only combat/shop/boss swap between the interchangeable hallway variants
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
	challenge_side = -1 # cleared each room; world.gd re-marks it via set_challenge_door if needed
	set_process(false)
	queue_redraw()

# Marks one exit as leading to a challenge room, so it's drawn as a flashing red door. _process is
# enabled only while such a door is showing, to animate the pulse.
func set_challenge_door(side: int) -> void:
	challenge_side = side
	set_process(true)
	queue_redraw()

func _process(_delta: float) -> void:
	if challenge_side != -1 and not doors_locked:
		queue_redraw() # animate the challenge door's pulse
	else:
		set_process(false)

# Trigger zone for a door: a thin band right at the door mouth, so the room only changes once the
# player has actually walked up to the door. Uses _play, so it adapts to both room sizes.
func door_zone(side: int) -> Rect2:
	# Holding Bay: the door is at the FAR top of the corridor, not where it meets the slab, so the
	# trigger band sits just below the doorway rather than being derived from _play.
	# Cockpit's doors sit where the art puts them, not centred on each edge, so its trigger bands
	# are derived from the explicit door rects (grown inward so the player meets them at the wall).
	if _kind == "cockpit":
		match side:
			SIDE_TOP:    return Rect2(COCKPIT_DOOR_TOP.position.x, 0.0, COCKPIT_DOOR_TOP.size.x, COCKPIT_PLAY.position.y + 20.0)
			SIDE_BOTTOM: return Rect2(COCKPIT_DOOR_BOTTOM.position.x, COCKPIT_PLAY.end.y - 20.0, COCKPIT_DOOR_BOTTOM.size.x, COCKPIT_H - COCKPIT_PLAY.end.y + 20.0)
			SIDE_LEFT:   return Rect2(0.0, COCKPIT_DOOR_LEFT.position.y, COCKPIT_PLAY.position.x + 20.0, COCKPIT_DOOR_LEFT.size.y)
		return Rect2() # no right door — that edge is the windscreen
	if _kind == "start" and side == SIDE_TOP:
		# Deep band (down the top of the corridor) so it fires well before the player reaches the
		# cap wall — the transition should never feel like walking into a dead end.
		return Rect2(LOBBY_CORRIDOR_X0, LOBBY_CORRIDOR_TOP, LOBBY_CORRIDOR_X1 - LOBBY_CORRIDOR_X0, 200.0)
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
	# Round room: the doors are the four rectangular bays where the circle breaks out into a
	# straight-sided nub at the map edge. Measured from the art (top/bottom bays are 128 wide and
	# 25 deep; the left/right ones are 104 tall and ~59 deep, since the circle is inset more
	# horizontally than vertically in a 1041x960 frame).
	if _kind == "control":
		match side:
			SIDE_TOP:    return PackedVector2Array([Vector2(456,0),   Vector2(584,0),   Vector2(584,25),  Vector2(456,25),  Vector2(456,0)])
			SIDE_BOTTOM: return PackedVector2Array([Vector2(456,935), Vector2(584,935), Vector2(584,960), Vector2(456,960), Vector2(456,935)])
			SIDE_LEFT:   return PackedVector2Array([Vector2(0,428),   Vector2(59,428),  Vector2(59,532),  Vector2(0,532),   Vector2(0,428)])
			SIDE_RIGHT:  return PackedVector2Array([Vector2(1041,431),Vector2(981,431), Vector2(981,529), Vector2(1041,529),Vector2(1041,431)])
		return PackedVector2Array()
	# Cockpit: explicit door rects (see door_zone) — they aren't centred on their edges.
	if _kind == "cockpit":
		var cr := Rect2()
		match side:
			SIDE_TOP:    cr = COCKPIT_DOOR_TOP
			SIDE_BOTTOM: cr = COCKPIT_DOOR_BOTTOM
			SIDE_LEFT:   cr = COCKPIT_DOOR_LEFT
			_:           return PackedVector2Array()
		return PackedVector2Array([cr.position, Vector2(cr.end.x, cr.position.y), cr.end, Vector2(cr.position.x, cr.end.y), cr.position])
	# Docking Bay: the three rectangles jutting out of the slab's edge (no top door — window there).
	if _kind == "docking":
		var dr := Rect2()
		match side:
			SIDE_LEFT:   dr = DOCK_DOOR_LEFT
			SIDE_RIGHT:  dr = DOCK_DOOR_RIGHT
			SIDE_BOTTOM: dr = DOCK_DOOR_BOTTOM
			_:           return PackedVector2Array()
		return PackedVector2Array([dr.position, Vector2(dr.end.x, dr.position.y), dr.end, Vector2(dr.position.x, dr.end.y), dr.position])
	# Bar: the four rectangles jutting out of the floor slab, one per edge.
	if _kind == "bar":
		var br := Rect2()
		match side:
			SIDE_TOP:    br = BAR_DOOR_TOP
			SIDE_BOTTOM: br = BAR_DOOR_BOTTOM
			SIDE_LEFT:   br = BAR_DOOR_LEFT
			SIDE_RIGHT:  br = BAR_DOOR_RIGHT
		return PackedVector2Array([br.position, Vector2(br.end.x, br.position.y), br.end, Vector2(br.position.x, br.end.y), br.position])
	# Holding Bay: one door, drawn around the dark mouth at the far top end of the corridor.
	if _kind == "start":
		if side == SIDE_TOP:
			var d := LOBBY_DOOR_RECT
			return PackedVector2Array([d.position, Vector2(d.end.x, d.position.y), d.end, Vector2(d.position.x, d.end.y), d.position])
		return PackedVector2Array()
	match side:
		SIDE_TOP:    return PackedVector2Array([Vector2(452,0),   Vector2(586,0),   Vector2(564,96),  Vector2(474,96),  Vector2(452,0)])
		SIDE_BOTTOM: return PackedVector2Array([Vector2(474,382), Vector2(564,382), Vector2(586,478), Vector2(452,478), Vector2(474,382)])
		SIDE_LEFT:   return PackedVector2Array([Vector2(0,172),   Vector2(0,306),   Vector2(114,284), Vector2(114,194), Vector2(0,172)])
		SIDE_RIGHT:  return PackedVector2Array([Vector2(1040,172),Vector2(1040,306),Vector2(926,284), Vector2(926,194), Vector2(1040,172)])
	return PackedVector2Array()

func _draw() -> void:
	# Every layout is textured now — the bar and lobby placeholders were replaced by real art. A
	# code-drawn background here would paint straight over the sprite (z_index -10), so _draw only
	# adds the door status outlines on top of whatever art the room is showing.
	for side in door_sides:
		var outline := _door_outline(side)
		if outline.size() < 2:
			continue # this layout has no marker for that side (e.g. the lobby's single top door)
		var frame_col := DOOR_LOCKED_COLOR
		var width := 3.0
		if not doors_locked:
			if side == challenge_side:
				# Flashing red challenge door (pulses between dim and bright red).
				var f := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 110.0)
				frame_col = Color(0.55, 0.02, 0.02).lerp(Color(1.0, 0.20, 0.15), f)
				width = 5.0
			else:
				frame_col = DOOR_BACK_COLOR if side == entry_side else DOOR_OPEN_COLOR
		draw_polyline(outline, frame_col, width)

# Four walls hugging the walkable floor.
func _build_walls() -> void:
	for w in _wall_bodies:
		if is_instance_valid(w):
			w.queue_free()
	_wall_bodies.clear()
	# Round room: ring the circular floor with overlapping rotated segments. A rect box would let
	# the player walk into the black corners outside the circle (its diagonal exceeds the radius).
	if _kind == "control":
		_build_ring_walls(CONTROL_CENTER, CONTROL_RADIUS, CONTROL_WALL_SEGMENTS)
		return
	if _kind == "start":
		_build_lobby_walls()
		return
	var p := _play
	_wall(Vector2(p.position.x - WALL_T, p.position.y - WALL_T - TOP_WALL_LIFT), Vector2(p.size.x + 2.0 * WALL_T, WALL_T)) # top
	_wall(Vector2(p.position.x - WALL_T, p.end.y),               Vector2(p.size.x + 2.0 * WALL_T, WALL_T)) # bottom
	_wall(Vector2(p.position.x - WALL_T, p.position.y),          Vector2(WALL_T, p.size.y))                # left
	_wall(Vector2(p.end.x,               p.position.y),          Vector2(WALL_T, p.size.y))                # right

# T-shaped bounds for the Holding Bay: the floor slab, plus the corridor running up out of the
# middle of its top edge. The slab's top wall is split into two segments so the corridor mouth is
# open, and the corridor is capped at LOBBY_CORRIDOR_TOP where the doorway begins.
func _build_lobby_walls() -> void:
	var p := LOBBY_SLAB
	var x0 := LOBBY_CORRIDOR_X0
	var x1 := LOBBY_CORRIDOR_X1
	_wall(Vector2(p.position.x - WALL_T, p.end.y), Vector2(p.size.x + 2.0 * WALL_T, WALL_T))       # slab bottom
	_wall(Vector2(p.position.x - WALL_T, p.position.y), Vector2(WALL_T, p.size.y))                 # slab left
	_wall(Vector2(p.end.x, p.position.y), Vector2(WALL_T, p.size.y))                               # slab right
	# Slab top, either side of the corridor mouth.
	_wall(Vector2(p.position.x - WALL_T, p.position.y - WALL_T), Vector2(x0 - (p.position.x - WALL_T), WALL_T))
	_wall(Vector2(x1, p.position.y - WALL_T), Vector2(p.end.x + WALL_T - x1, WALL_T))
	# Corridor sides, from the doorway down to the slab.
	var corr_h := p.position.y - LOBBY_CORRIDOR_TOP
	_wall(Vector2(x0 - WALL_T, LOBBY_CORRIDOR_TOP), Vector2(WALL_T, corr_h))
	_wall(Vector2(x1, LOBBY_CORRIDOR_TOP), Vector2(WALL_T, corr_h))
	# Cap at the top — the player stops here, at the door.
	_wall(Vector2(x0 - WALL_T, LOBBY_CORRIDOR_TOP - WALL_T), Vector2(x1 - x0 + 2.0 * WALL_T, WALL_T))

# Approximates a circular wall with `count` rotated segments sitting just outside `radius`. Each
# segment is made 1.25x its exact arc length so neighbours overlap and no gap opens up between
# them at this resolution (a player pushing into a seam would otherwise squeeze through).
func _build_ring_walls(center: Vector2, radius: float, count: int) -> void:
	var seg_len := (TAU * radius / float(count)) * 1.25
	for i in range(count):
		var a := TAU * float(i) / float(count)
		var dir := Vector2(cos(a), sin(a))
		var body := StaticBody2D.new()
		body.position = center + dir * (radius + WALL_T * 0.5)
		body.rotation = a + PI * 0.5 # long axis tangent to the circle
		body.collision_layer = 8
		body.collision_mask = 0
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(seg_len, WALL_T)
		col.shape = shape # centred on the body, unlike the axis-aligned _wall below
		body.add_child(col)
		add_child(body)
		_wall_bodies.append(body)

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
