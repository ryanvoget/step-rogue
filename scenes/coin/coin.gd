extends Node2D

# A gold coin dropped by a defeated enemy (see enemy_basic.gd's _drop_coins). Bursts outward
# from the death spot, decelerating, then magnets toward the player when they come close and is
# collected on contact — adding VALUE to GameManager.coins. Distance-based (no Area2D) since the
# player is the only thing that can pick it up.

const VALUE := 5
const FRICTION := 360.0        # px/s^2 the initial burst velocity decays
const MAGNET_RANGE := 78.0     # pulled toward the player within this range
const MAGNET_SPEED := 270.0
const PICKUP_RADIUS := 22.0    # player radius (~14) + coin radius + a little grace
const PICKUP_DELAY := 0.18     # brief grace so it visibly pops out before it can be grabbed

var _vel := Vector2.ZERO
var _player: Node2D = null
var _age := 0.0
var _value := VALUE # how much this coin is worth on pickup (set per-coin so a drop can total exactly
                    # the enemy's gold — see enemy_basic.gd _drop_coins)

func burst(pos: Vector2, dir: Vector2, speed: float, value: int = VALUE) -> void:
	global_position = pos
	_vel = dir * speed
	_value = value

func _physics_process(delta: float) -> void:
	_age += delta
	if _player == null or not is_instance_valid(_player):
		var hits := get_tree().get_nodes_in_group("player")
		_player = hits[0] if hits.size() > 0 else null
	if _player != null:
		var to := _player.global_position - global_position
		var d := to.length()
		if d <= MAGNET_RANGE and d > 0.1:
			_vel = (to / d) * MAGNET_SPEED
		else:
			_vel = _vel.move_toward(Vector2.ZERO, FRICTION * delta)
		if _age >= PICKUP_DELAY and d <= PICKUP_RADIUS:
			GameManager.add_coins(_value)
			_spawn_pickup_text()
			queue_free()
			return
	else:
		_vel = _vel.move_toward(Vector2.ZERO, FRICTION * delta)
	global_position += _vel * delta

# Credit-denomination colours: 1 silver, 5 gold, 10 green, 25 blue (higher odd amounts fall to the
# nearest tier). Returns [outer_ring, main, highlight].
func _credit_colors() -> Array:
	if _value >= 25:
		return [Color(0.10, 0.28, 0.60), Color(0.30, 0.60, 1.00), Color(0.75, 0.90, 1.00)] # blue
	if _value >= 10:
		return [Color(0.10, 0.45, 0.15), Color(0.30, 0.85, 0.35), Color(0.75, 1.00, 0.78)] # green
	if _value >= 5:
		return [Color(0.75, 0.55, 0.05), Color(1.00, 0.82, 0.20), Color(1.00, 0.96, 0.65)] # gold
	return [Color(0.52, 0.54, 0.60), Color(0.82, 0.84, 0.90), Color(0.97, 0.98, 1.00)]     # silver

# Floating "+N" that drifts up and fades over half a second, next to the player.
func _spawn_pickup_text() -> void:
	if _player == null or get_parent() == null:
		return
	var lbl := Label.new()
	lbl.text = "+%d" % _value
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", _credit_colors()[1])
	lbl.z_index = 100
	lbl.position = _player.global_position + Vector2(randf_range(-6.0, 10.0), -24.0)
	get_parent().add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 22.0, 0.5)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.5)
	tw.tween_callback(lbl.queue_free)

func _draw() -> void:
	var c: Array = _credit_colors()
	draw_circle(Vector2.ZERO, 6.0, c[0])
	draw_circle(Vector2.ZERO, 5.0, c[1])
	draw_circle(Vector2.ZERO, 2.5, c[2])
