extends Node2D

# Heal Dispenser Farm: placed at the player's position via the blue heal button (see
# item_registry.gd's heal_dispenser field docs), then periodically drops a heal_pickup.tscn
# instance — visually the "Small Heal Vial" item, see _spawn_pickup — at a random nearby spot
# every dispenser_interval seconds, for dispenser_duration seconds total (e.g. every 5s for
# 20s = 4 vials), before removing itself. Each pickup heals whoever walks over it once, then
# disappears on its own — see heal_pickup.gd.

const ICON_TARGET_SIZE := 40.0
const PICKUP_SCENE := preload("res://scenes/heal_pickup/heal_pickup.tscn")
const SPAWN_RADIUS := 70.0 # how far from the dispenser each vial can land

const WALL_T := 28.0 # matches room.gd's WALL_T
const EDGE_MARGIN := 20.0 # keeps a dropped vial clear of the wall face — room bounds come from
                          # GameManager.room_w/play_h (see room.gd), so vials land in the real area

var _interval := 5.0
var _duration := 20.0
var _heal_amount := 5
var _elapsed := 0.0
var _tick_timer := 0.0

@onready var _sprite: Sprite2D = $Sprite

func configure(tex: Texture2D, position: Vector2, interval: float, duration: float, heal_amount: int) -> void:
	global_position = position
	_interval = interval
	_duration = duration
	_heal_amount = heal_amount
	_tick_timer = interval
	_sprite.texture = tex
	var size := tex.get_size()
	var largest: float = max(size.x, size.y)
	var scale_factor: float = ICON_TARGET_SIZE / largest if largest > 0.0 else 1.0
	_sprite.scale = Vector2(scale_factor, scale_factor)

func _process(delta: float) -> void:
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer += _interval
		_spawn_pickup()
	_elapsed += delta
	if _elapsed >= _duration:
		queue_free()

func _spawn_pickup() -> void:
	var offset := Vector2(randf_range(-SPAWN_RADIUS, SPAWN_RADIUS), randf_range(-SPAWN_RADIUS, SPAWN_RADIUS))
	var pos := global_position + offset
	var min_x := WALL_T + EDGE_MARGIN
	var max_x := GameManager.room_w - WALL_T - EDGE_MARGIN
	var min_y := WALL_T + EDGE_MARGIN
	var max_y := GameManager.play_h - WALL_T - EDGE_MARGIN
	pos.x = clampf(pos.x, min_x, max_x)
	pos.y = clampf(pos.y, min_y, max_y)

	var vial_item: Dictionary = ItemRegistry.get_item_by_name("Small Heal Vial")
	var tex: Texture2D = load("res://assets/icons/" + vial_item["file"]) if not vial_item.is_empty() else null
	var pickup: Node2D = PICKUP_SCENE.instantiate()
	get_parent().add_child(pickup)
	pickup.configure(pos, _heal_amount, tex)
