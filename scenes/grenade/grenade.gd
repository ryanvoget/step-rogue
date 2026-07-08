extends Node2D

# Thrown equipment (e.g. Blast Grenade), deployed the same way the Turret is: via
# mobile_controls' green deploy button. Flies from the player to a landing spot in front
# of them, waits explode_delay seconds, then deals flat AOE damage to every enemy within
# radius and disappears. Configured post-instantiate via configure().

const ICON_TARGET_SIZE := 32.0
const THROW_DURATION := 0.15 # seconds to visually travel from origin to landing spot
const EXPLOSION_FLASH_DURATION := 0.15 # seconds the AOE ring stays drawn after exploding

var _damage := 0
var _radius := 0.0
var _exploded := false

@onready var _sprite: Sprite2D = $Sprite
@onready var _explode_timer: Timer = $ExplodeTimer

func _ready() -> void:
	_explode_timer.timeout.connect(_explode)

# Applies an item's tuned stats (damage/aoe_radius/explode_delay from ItemRegistry) and
# icon, then tweens from origin to landing_pos before starting the explode_delay fuse.
func configure(tex: Texture2D, origin: Vector2, landing_pos: Vector2, damage: int, radius: float, explode_delay: float) -> void:
	_damage = damage
	_radius = radius
	_sprite.texture = tex
	var size := tex.get_size()
	var largest: float = max(size.x, size.y)
	var scale_factor: float = ICON_TARGET_SIZE / largest if largest > 0.0 else 1.0
	_sprite.scale = Vector2(scale_factor, scale_factor)

	global_position = origin
	_explode_timer.wait_time = explode_delay
	var tween := create_tween()
	tween.tween_property(self, "global_position", landing_pos, THROW_DURATION)
	tween.finished.connect(_explode_timer.start)

func _explode() -> void:
	_exploded = true
	_sprite.visible = false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(enemy.global_position) <= _radius and enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
	queue_redraw()
	get_tree().create_timer(EXPLOSION_FLASH_DURATION).timeout.connect(queue_free)

func _draw() -> void:
	if not _exploded:
		return
	draw_circle(Vector2.ZERO, _radius, Color(1.0, 0.5, 0.1, 0.35))
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 32, Color(1.0, 0.6, 0.15, 0.9), 3.0)
