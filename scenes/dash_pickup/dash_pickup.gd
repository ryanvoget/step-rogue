extends Node2D

# The Teleportation Bracelet pickup, placed in the starting lobby. Walk over it to unlock the dash
# (GameManager.dash_unlocked) for the run — world.gd polls proximity and frees it on pickup. Purely a
# floating icon + label with a gentle bob.

const ICON_PATH := "res://assets/icons/Teleportation_Bracelet_Asset.png"
const BOB_AMPL := 6.0
var _t := 0.0
var _base_y := 0.0
@onready var _sprite := Sprite2D.new()

func _ready() -> void:
	var tex: Texture2D = load(ICON_PATH)
	if tex != null:
		_sprite.texture = tex
		var s := tex.get_size()
		var scale_f: float = 40.0 / maxf(s.x, s.y) if maxf(s.x, s.y) > 0.0 else 1.0
		_sprite.scale = Vector2(scale_f, scale_f)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_base_y = 0.0
	var lbl := Label.new()
	lbl.text = "Teleportation\nBracelet"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size = Vector2(100, 34)
	lbl.position = Vector2(-50, 24)
	add_child(lbl)

func _process(delta: float) -> void:
	_t += delta
	_sprite.position.y = _base_y + sin(_t * 3.0) * BOB_AMPL
