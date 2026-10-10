extends Control

# The rotating emblem from the reference image's "AXIOM" projection: concentric arcs at different
# radii and speeds, a dense radial tick fan, and a bright broken outer ring. Used as the menu's
# title piece and as the crate-opening centrepiece.
#
# The parts counter-rotate at deliberately unrelated speeds. That's what makes it read as a
# machine readout rather than a spinning logo — nothing ever quite repeats.

const T := preload("res://scenes/ui/ui_theme.gd")

@export var label_text := ""
@export var accent: Color = T.CYAN
@export var spin := 1.0 # multiplier on every rotation rate; 0 freezes the ring

var _t := 0.0
var _pulse := 0.0 # one-shot flare, see flare()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_t += delta * spin
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 2.2, 0.0)
	queue_redraw()

# A bright expanding flash — called when the ring has something to announce (a crate landing).
func flare() -> void:
	_pulse = 1.0

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	if r <= 4.0:
		return
	var boost := 1.0 + _pulse * 1.6

	# Outer broken ring: four long arcs with gaps, slowly turning.
	for i in 4:
		var a0 := _t * 0.35 + TAU * float(i) / 4.0
		T.draw_glow_arc(self, c, r * 0.96, a0, a0 + deg_to_rad(62.0), accent, 2.0, 0.9 * boost, 24)

	# Counter-rotating inner ring, thinner and faster.
	for i in 3:
		var a1 := -_t * 0.6 + TAU * float(i) / 3.0
		T.draw_glow_arc(self, c, r * 0.80, a1, a1 + deg_to_rad(80.0), accent, 1.5, 0.7 * boost, 24)

	# Radial tick fan — the dense comb of lines that gives the reference ring its texture.
	var ticks := 56
	for i in ticks:
		var a := TAU * float(i) / float(ticks) + _t * 0.18
		# Every fourth tick is longer, so the fan has rhythm instead of being uniform.
		var long := (i % 4 == 0)
		var inner := r * (0.60 if long else 0.66)
		var outer := r * (0.74 if long else 0.70)
		var alpha := (0.75 if long else 0.35) * boost
		draw_line(c + Vector2(inner, 0).rotated(a), c + Vector2(outer, 0).rotated(a),
			Color(accent, alpha), 1.5 if long else 1.0)

	# Core disc and its halo.
	draw_circle(c, r * 0.52, Color(accent, 0.07 * boost))
	T.draw_glow_arc(self, c, r * 0.52, 0.0, TAU, accent, 1.5, 0.8 * boost, 40)

	# Sweeping scan arc, like a radar return.
	var sweep := _t * 1.4
	T.draw_glow_arc(self, c, r * 0.52, sweep, sweep + deg_to_rad(46.0), T.CYAN_HOT, 2.5, 0.9 * boost, 16)

	# Inner reticle: a small cross with a gap at the centre.
	var g := r * 0.10
	var k := r * 0.22
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_line(c + d * g, c + d * k, Color(accent, 0.55 * boost), 1.0)

	if _pulse > 0.0:
		# The flare itself: a ring expanding outward past the emblem as it fades.
		var fr := r * (1.0 + (1.0 - _pulse) * 0.9)
		draw_arc(c, fr, 0.0, TAU, 48, Color(T.CYAN_HOT, _pulse * 0.8), 3.0)
