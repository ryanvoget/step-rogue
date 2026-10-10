extends Node2D

# Fire Trail+ artifact: a short-lived patch of fire dropped behind the player. Any enemy that
# touches it is burned once (enemy_basic.apply_burn), then ignored for the rest of this patch's
# life so walking through one patch can't stack the burn every frame. World-parented so it stays
# put as the player moves on; frees itself when it burns out.

const RADIUS := 30.0
const LIFETIME := 3.0
const FLICKER_HZ := 11.0

var _burn_damage := 3
var _burn_duration := 3.0
var _life := LIFETIME
var _scorched := {} # enemies already burned by THIS patch

func configure(pos: Vector2, burn_damage: int, burn_duration: float) -> void:
	global_position = pos
	_burn_damage = burn_damage
	_burn_duration = burn_duration

func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or _scorched.has(e):
			continue
		# Test against the enemy's BODY, not just its centre. Enemies are 20-25px in radius against
		# a 30px patch, so a centre-only check meant an enemy standing visibly in the fire wouldn't
		# burn unless it was nearly dead centre on it.
		var er: float = e._radius if "_radius" in e else 0.0
		if e.global_position.distance_to(global_position) <= RADIUS + er and e.has_method("apply_burn"):
			_scorched[e] = true
			e.apply_burn(_burn_damage, _burn_duration)
	queue_redraw()

func _draw() -> void:
	# Fades out over its life, with a slight flicker so it reads as fire rather than a flat disc.
	var t := clampf(_life / LIFETIME, 0.0, 1.0)
	var flicker := 0.85 + 0.15 * sin(Time.get_ticks_msec() / 1000.0 * TAU * FLICKER_HZ)
	draw_circle(Vector2.ZERO, RADIUS * (0.75 + 0.25 * t), Color(1.0, 0.35, 0.08, 0.26 * t * flicker))
	draw_circle(Vector2.ZERO, RADIUS * 0.55 * (0.75 + 0.25 * t), Color(1.0, 0.72, 0.20, 0.34 * t * flicker))
