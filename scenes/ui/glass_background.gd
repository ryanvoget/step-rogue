extends Control

# The backdrop behind every menu screen. Built from the two reference plates: the deep-space
# gradient and drifting starfield of the exterior shot, overlaid with the dark hull panelling and
# faint cyan grid of the ship interior — so a menu reads as a console aboard the ship, with space
# visible behind it.
#
# Everything is procedural rather than a texture, so it scales to any viewport and costs nothing
# to ship. Layer order, back to front:
#   1. vertical gradient (deep navy → near-black)
#   2. nebula blooms, two soft off-centre clouds
#   3. parallax starfield, three depths, slow drift
#   4. hull panelling + grid lines + corner rivets
#   5. horizon glow along the bottom (the planet-light in the space plate)
#   6. scanlines + vignette

const T := preload("res://scenes/ui/ui_theme.gd")

const STAR_COUNT := 110
const DRIFT_SPEED := 5.0   # px/sec at the farthest layer — slow enough to read as parallax
const GRID_STEP := 56.0

var _stars: Array = []      # [pos, radius, alpha, depth]
var _t := 0.0
var _canvas: Control = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.draw.connect(_paint)
	_canvas.resized.connect(_seed_stars)
	_seed_stars()

func _seed_stars() -> void:
	var sz := _canvas.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		sz = Vector2(480, 854)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260205 # fixed so the sky is the same every launch, not reshuffled per screen
	_stars.clear()
	for i in STAR_COUNT:
		var depth := rng.randf_range(0.25, 1.0)
		_stars.append([
			Vector2(rng.randf_range(0.0, sz.x), rng.randf_range(0.0, sz.y * 0.75)),
			rng.randf_range(0.5, 1.7) * depth,
			rng.randf_range(0.25, 0.95) * depth,
			depth,
		])
	_canvas.queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	_canvas.queue_redraw()

func _paint() -> void:
	var sz := _canvas.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	_paint_space(sz)
	_paint_stars(sz)
	_paint_hull(sz)
	_paint_horizon(sz)
	_paint_overlay(sz)

# 1-2. Space gradient plus two nebula blooms.
func _paint_space(sz: Vector2) -> void:
	const BANDS := 26
	for i in BANDS:
		var f := float(i) / float(BANDS - 1)
		var col := Color(0.035, 0.078, 0.137).lerp(T.VOID, f * f)
		_canvas.draw_rect(Rect2(0.0, sz.y * f, sz.x, sz.y / float(BANDS) + 2.0), col)
	# Nebulae — wide, very faint, drawn as stacked discs so they feather at the edges.
	_nebula(Vector2(sz.x * 0.22, sz.y * 0.18), sz.x * 0.46, Color(0.18, 0.45, 0.75), 0.055)
	_nebula(Vector2(sz.x * 0.86, sz.y * 0.40), sz.x * 0.34, Color(0.30, 0.22, 0.58), 0.040)

func _nebula(at: Vector2, radius: float, col: Color, peak: float) -> void:
	for i in range(6, 0, -1):
		var f := float(i) / 6.0
		_canvas.draw_circle(at, radius * f, Color(col, peak * (1.0 - f) * 1.8))

# 3. Starfield. Each depth drifts at its own rate, and the near stars twinkle.
func _paint_stars(sz: Vector2) -> void:
	for s in _stars:
		var depth: float = s[3]
		var p: Vector2 = s[0]
		var x := fmod(p.x + _t * DRIFT_SPEED * depth, sz.x + 8.0) - 4.0
		var a: float = s[2]
		if depth > 0.7: # only the near layer twinkles — distant stars sit steady
			a *= 0.65 + 0.35 * sin(_t * 2.2 + p.x * 0.05)
		var at := Vector2(x, p.y)
		_canvas.draw_circle(at, s[1] * 2.6, Color(T.CYAN, a * 0.10))
		_canvas.draw_circle(at, s[1], Color(0.88, 0.95, 1.0, a))

# 4. The ship interior: panel blocks, a faint cyan grid, and rivets where lines meet.
func _paint_hull(sz: Vector2) -> void:
	# A few large panels along the edges, catching just enough light to show their shape.
	var panels := [
		Rect2(0.0, 0.0, sz.x * 0.34, 86.0),
		Rect2(sz.x * 0.62, 0.0, sz.x * 0.38, 54.0),
		Rect2(0.0, sz.y - 120.0, sz.x * 0.28, 120.0),
		Rect2(sz.x * 0.70, sz.y - 76.0, sz.x * 0.30, 76.0),
	]
	for r in panels:
		_canvas.draw_rect(r, Color(T.HULL, 0.55))
		_canvas.draw_line(r.position, Vector2(r.end.x, r.position.y), Color(T.CYAN, 0.10), 1.0)
	var grid := Color(T.CYAN, 0.045)
	var y := GRID_STEP
	while y < sz.y:
		_canvas.draw_line(Vector2(0, y), Vector2(sz.x, y), grid, 1.0)
		y += GRID_STEP
	var x := GRID_STEP
	while x < sz.x:
		_canvas.draw_line(Vector2(x, 0), Vector2(x, sz.y), grid, 1.0)
		x += GRID_STEP

# 5. Horizon light — the planet-glow washing up from the bottom of the space plate.
func _paint_horizon(sz: Vector2) -> void:
	const STEPS := 18
	for i in STEPS:
		var f := float(i) / float(STEPS)
		var h := sz.y * 0.20 * (1.0 - f)
		_canvas.draw_rect(Rect2(0.0, sz.y - h, sz.x, h), Color(T.CYAN, 0.011))

# 6. Scanlines and vignette — the two things that stop it reading as flat vector art.
func _paint_overlay(sz: Vector2) -> void:
	var y := 0.0
	while y < sz.y:
		_canvas.draw_rect(Rect2(0.0, y, sz.x, 1.0), Color(0.0, 0.0, 0.0, 0.10))
		y += 3.0
	# Vignette: concentric inset frames, darkest at the very edge.
	const RINGS := 22
	for i in RINGS:
		var f := float(i) / float(RINGS)
		var inset := sz.x * 0.52 * f
		var a := 0.055 * (1.0 - f) * (1.0 - f)
		_canvas.draw_rect(Rect2(inset, inset * (sz.y / maxf(sz.x, 1.0)),
			sz.x - inset * 2.0, sz.y - inset * 2.0 * (sz.y / maxf(sz.x, 1.0))),
			Color(0, 0, 0, a), false, 2.0)
