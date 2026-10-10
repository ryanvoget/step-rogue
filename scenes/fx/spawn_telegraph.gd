extends Node2D

# The pulsing blue ring that marks where an enemy is about to teleport in. Shown for LEAD_TIME
# before the enemy actually appears, so a room fills in readable waves instead of being fully
# populated the instant the player walks through the door.
#
# Sized to the enemy that's coming (enemy_basic's _radius, 18 by default) so the marker reads as
# "something exactly this big lands here" rather than a generic decal. Frees itself when the timer
# runs out — world.gd spawns the enemy on its own schedule and never waits on this node, so a
# telegraph that somehow outlives its wave can't hold up a spawn.

const LEAD_TIME := 1.0
const COLOR      := Color(0.35, 0.75, 1.0)
const CORE_COLOR := Color(0.80, 0.95, 1.0)

var _radius := 18.0
var _life := LEAD_TIME

func setup(pos: Vector2, radius: float, lead: float = LEAD_TIME) -> void:
	global_position = pos
	_radius = radius
	_life = lead

func _ready() -> void:
	z_index = -1 # under the enemies and the player, like a floor marker

func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	# Two cues at once: a pulse that quickens as the spawn approaches, and a ring that sweeps
	# closed like a countdown — so the moment of arrival is readable even mid-fight.
	var t: float = 1.0 - clampf(_life / LEAD_TIME, 0.0, 1.0) # 0 → 1 as it fills
	var pulse: float = 0.5 + 0.5 * sin(t * TAU * 4.0)
	var a: float = 0.25 + 0.45 * pulse

	draw_circle(Vector2.ZERO, _radius * (1.25 + 0.2 * pulse), Color(COLOR, 0.10 + 0.10 * t))
	draw_circle(Vector2.ZERO, _radius, Color(COLOR, a * 0.45))
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 28, Color(COLOR, 0.85), 2.0)

	# Countdown sweep: a bright arc closing clockwise from the top.
	draw_arc(Vector2.ZERO, _radius * 0.78, -PI / 2.0, -PI / 2.0 + TAU * t, 28,
		Color(CORE_COLOR, 0.95), 3.0)

	# Converging ticks, pulling inward as the spawn lands.
	for i in range(4):
		var ang := TAU * float(i) / 4.0 + t * 2.0
		var outer := _radius * (1.9 - 0.7 * t)
		var inner := _radius * (1.35 - 0.3 * t)
		draw_line(Vector2(outer, 0).rotated(ang), Vector2(inner, 0).rotated(ang),
			Color(COLOR, 0.55 * pulse), 2.0)
