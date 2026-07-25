extends Node2D

# The shop keeper: same idle sprite as the player, recolored with a black shirt (via
# shirt_recolor.gdshader's make_black mode) so it reads as a distinct character. Purely visual —
# world.gd spawns one in every shop room (floor 10/20/...) and opens the shop dialog when the
# player walks within SHOP_TALK_RANGE of it (see world.gd's _physics_process).

const FRAME_W  := 64
const FRAME_H  := 64
const IDLE_FPS := 8.0

func _ready() -> void:
	var idle_tex: Texture2D = load("res://assets/Sprites/idle_spritesheet.png")
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("idle")
	sf.set_animation_speed("idle", IDLE_FPS)
	sf.set_animation_loop("idle", true)
	for i in range(5):
		var atlas := AtlasTexture.new()
		atlas.atlas = idle_tex
		atlas.region = Rect2(i * FRAME_W, 0, FRAME_W, FRAME_H)
		sf.add_frame("idle", atlas)

	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = sf
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scenes/character/shirt_recolor.gdshader")
	mat.set_shader_parameter("make_black", true)
	sprite.material = mat
	sprite.play("idle")
	add_child(sprite)

	# Floating "SHOP" tag above the keeper's head.
	var lbl := Label.new()
	lbl.text = "🛒 SHOP"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size = Vector2(80, 20)
	lbl.position = Vector2(-40, -46)
	add_child(lbl)
