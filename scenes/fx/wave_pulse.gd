extends Node2D

# An expanding ring that damages each enemy once as its leading edge sweeps over them. World-
# parented at the position it was fired from, so it keeps expanding from there rather than
# dragging along with the player. Frees itself at full size.
#
# Two callers share this:
#   • the Wave Pulse+ artifact — a plain damage ring every few seconds
#   • the hammer family (War Hammer, Pulse Hammer and five fused variants) — a ground slam, which
#     adds knockback, and in Grapple Hammer's case pulls enemies in before shoving them out.
# Everything past `damage` is optional so the artifact's two-argument call still works.

const DEFAULT_RADIUS := 220.0
const EXPAND_SPEED := 380.0 # px/sec — the visible sweep rate, same for every size of ring
const EDGE_THICKNESS := 26.0
const PULL_DURATION := 0.35   # Grapple Hammer: how long enemies are dragged inward before the shove
const PULL_SPEED := 520.0     # ...and how fast they're dragged

var _damage := 5
var _max_radius := DEFAULT_RADIUS
var _knockback := 0.0
var _pull_first := false      # pull enemies in, then knock them away (Grapple Hammer)
var _color := Color(0.35, 0.85, 1.0)

var _radius := 0.0
var _pull_timer := 0.0
var _hit := {}   # enemies already caught by this ring
var _pulled := [] # enemies being dragged inward during the pull phase

func configure(pos: Vector2, damage: int, max_radius: float = DEFAULT_RADIUS,
		knockback: float = 0.0, pull_first: bool = false, color: Color = Color(0.35, 0.85, 1.0)) -> void:
	global_position = pos
	_damage = damage
	_max_radius = max_radius
	_knockback = knockback
	_pull_first = pull_first
	_color = color
	if pull_first:
		_pull_timer = PULL_DURATION

func _physics_process(delta: float) -> void:
	# Grapple Hammer opens by dragging everything in range toward the centre. The ring itself
	# doesn't start expanding until that finishes, so the two phases read as one motion.
	if _pull_timer > 0.0:
		_pull_timer -= delta
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e):
				continue
			var to_centre: Vector2 = global_position - e.global_position
			if to_centre.length() <= _max_radius:
				e.global_position += to_centre.normalized() * PULL_SPEED * delta
				if not _pulled.has(e):
					_pulled.append(e)
		queue_redraw()
		return

	_radius += EXPAND_SPEED * delta
	# Clamp and sweep one last time at exactly _max_radius before freeing. Returning early here
	# skipped that final pass, so enemies sitting in the outermost few pixels were never hit.
	var finished := _radius >= _max_radius
	if finished:
		_radius = _max_radius
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or _hit.has(e):
			continue
		# Caught once the edge reaches its BODY — no need to still be inside when it passes, and
		# no need for the ring to reach its centre (same body-radius fix as fire_patch).
		var er: float = e._radius if "_radius" in e else 0.0
		if e.global_position.distance_to(global_position) <= _radius + er and e.has_method("take_damage"):
			_hit[e] = true
			var dir: Vector2 = (e.global_position - global_position).normalized()
			e.take_damage(_damage, dir, _knockback)
	if finished:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	if _pull_timer > 0.0:
		# Pull phase: a contracting ring reading as suction, so the shove that follows is telegraphed.
		var p := clampf(_pull_timer / PULL_DURATION, 0.0, 1.0)
		draw_arc(Vector2.ZERO, _max_radius * p, 0.0, TAU, 48, Color(_color, 0.55), 3.0)
		return
	var t := clampf(1.0 - _radius / _max_radius, 0.0, 1.0)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 48, Color(_color, 0.75 * t), EDGE_THICKNESS * t + 2.0)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 48, Color(_color.lerp(Color.WHITE, 0.6), 0.85 * t), 2.0)
