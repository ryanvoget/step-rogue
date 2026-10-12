extends Node2D

# A teleport pad on the floor — the replacement for the room's doors. One pad per exit the room
# used to have. Standing on it sends the player to that destination.
#
# The pad itself is the animated "Teleport Pad" sprite (7 frames, 32x32, drawn at 2x like the
# tile map). A faint column of light rises above it so it is still visible across the room.

const T := preload("res://scenes/ui/ui_theme.gd")
const PAD_TEXTURE := "res://assets/Teleport Pad.png"

# Teleport Pad.png: 7 frames, each 160px apart horizontally. Two floor variants of every frame —
# the light (lavender) floor on top, the dark floor 48px below it.
const FRAME_COUNT := 7
const FRAME_STRIDE := 160
const FRAME_SIZE := 32
const DARK_ROW_Y := 48
const PAD_FPS := 8.0
const PAD_SCALE := 2.0

const RADIUS := 32.0
const COLUMN_H := 54.0

@export var accent: Color = T.CYAN
@export var dark_floor := false # use the dark-floor variant of the pad art
var _t := 0.0
var _armed := false # pads ignore the player until they step OFF, so arriving can't re-trigger
var _sprite: AnimatedSprite2D

func _ready() -> void:
	z_index = 2 # on the floor, under the actors
	_setup_sprite()

func _setup_sprite() -> void:
	var tex: Texture2D = load(PAD_TEXTURE)
	var sf := SpriteFrames.new()
	sf.set_animation_loop("default", true)
	sf.set_animation_speed("default", PAD_FPS)
	var y := DARK_ROW_Y if dark_floor else 0
	for i in FRAME_COUNT:
		var frame := AtlasTexture.new()
		frame.atlas = tex
		frame.region = Rect2(i * FRAME_STRIDE, y, FRAME_SIZE, FRAME_SIZE)
		sf.add_frame("default", frame)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = sf
	_sprite.scale = Vector2(PAD_SCALE, PAD_SCALE)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Non-default exits (e.g. the challenge exit's red) tint the pad toward their accent.
	if not accent.is_equal_approx(T.CYAN):
		_sprite.modulate = Color.WHITE.lerp(accent, 0.45)
	add_child(_sprite)
	_sprite.play("default")

func arm() -> void:
	_armed = true

func is_armed() -> bool:
	return _armed

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var pulse := 0.55 + 0.45 * sin(_t * 2.2)
	# Column of light rising from the pad — what makes it visible across the room.
	for i in 5:
		var f := float(i) / 5.0
		var w := RADIUS * (1.0 - f * 0.55)
		var y := -COLUMN_H * f
		draw_rect(Rect2(-w, y - 3.0, w * 2.0, 6.0), Color(accent, 0.05 * (1.0 - f) * pulse))
	# Rising motes, so the column reads as moving upward.
	for i in 4:
		var phase := fmod(_t * 0.6 + float(i) * 0.25, 1.0)
		var y2 := -COLUMN_H * phase
		var a2 := (1.0 - phase) * 0.7
		draw_circle(Vector2(sin(_t * 1.7 + float(i)) * RADIUS * 0.4, y2), 2.5, Color(T.CYAN_HOT, a2))
