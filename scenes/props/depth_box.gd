extends StaticBody2D

# A free-standing box placed by hand on a tile map (small_box.tscn / big_box.tscn). The map draws
# behind everything, so on its own the player would always walk over the box. Instead the box picks
# its draw layer each frame: when the player's feet are above the box's base line (they're behind
# it) it draws over the player, otherwise under.

const FRONT_Z := 1  # over the player (z 0)
const BACK_Z := -1  # under the player, still over the map (-10)

# Where the player's feet sit below their origin (player.gd's TOP_FEET_OVERLAP).
const PLAYER_FEET := 24.0

@onready var _collision: CollisionShape2D = $Collision
var _player: Node2D

func _ready() -> void:
	z_as_relative = false # the map parent is at z -10; pick absolute layers instead
	z_index = BACK_Z

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			return
	# The base line is the middle of the box's collision — the player can't stand inside it, so
	# their feet are always clearly above (behind) or below (in front of) it.
	var base_y := _collision.global_position.y
	z_index = FRONT_Z if _player.global_position.y + PLAYER_FEET < base_y else BACK_Z
