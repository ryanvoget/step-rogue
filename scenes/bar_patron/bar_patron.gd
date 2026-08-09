extends Node2D

# Ambient cantina patron: the player idle sprite recolored with a black shirt (same as the shop
# keeper), no interaction — purely decorative crowd for bar rooms. world.gd scatters a few of these.

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
	sprite.frame = randi() % 5 # desync their idle bob a little
	sprite.play("idle")
	add_child(sprite)
