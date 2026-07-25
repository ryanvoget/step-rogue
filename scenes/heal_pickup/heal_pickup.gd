extends Area2D

# Small heal vial dropped by a Heal Dispenser Farm (see heal_dispenser.gd) — sits at a fixed
# spot until the player walks over it, heals them once, then disappears. Player-only
# (collision_mask = 1, set in the .tscn); enemies/bullets/walls never trigger it.

const ICON_TARGET_SIZE := 20.0

var _heal_amount := 5

@onready var _sprite: Sprite2D = $Sprite

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func configure(position: Vector2, heal_amount: int, tex: Texture2D = null) -> void:
	global_position = position
	_heal_amount = heal_amount
	if tex == null:
		return
	_sprite.texture = tex
	var size := tex.get_size()
	var largest: float = max(size.x, size.y)
	var scale_factor: float = ICON_TARGET_SIZE / largest if largest > 0.0 else 1.0
	_sprite.scale = Vector2(scale_factor, scale_factor)

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("heal"):
		body.heal(_heal_amount)
	queue_free()
