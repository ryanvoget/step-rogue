extends Control

# Shared glassy-futuristic backdrop (gradient + neon HUD grid + accent scanlines) reused by
# every menu/UI screen except the actual gameplay (world.gd) and sandbox. Screens attach it via
# SceneManager.add_glass_background(self). Built from a GradientTexture2D TextureRect (which
# always renders regardless of layout timing) plus a grid-drawing child — the same structure
# the original menu used, rather than a _draw() override that can miss the first layout pass.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var grad := Gradient.new()
	grad.set_color(0, Color(0.07, 0.11, 0.20))
	grad.set_color(1, Color(0.02, 0.02, 0.06))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_LINEAR
	gt.fill_from = Vector2(0.15, 0.0)
	gt.fill_to = Vector2(0.85, 1.0)
	var bg := TextureRect.new()
	bg.texture = gt
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var grid := Control.new()
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grid)
	grid.draw.connect(_draw_grid.bind(grid))
	grid.resized.connect(grid.queue_redraw)
	grid.queue_redraw()

func _draw_grid(grid: Control) -> void:
	var sz := grid.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var line_col := Color(0.35, 0.80, 1.0, 0.05)
	var step := 44.0
	var y := step
	while y < sz.y:
		grid.draw_line(Vector2(0, y), Vector2(sz.x, y), line_col, 1.0)
		y += step
	var x := step
	while x < sz.x:
		grid.draw_line(Vector2(x, 0), Vector2(x, sz.y), line_col, 1.0)
		x += step
	grid.draw_rect(Rect2(0, sz.y * 0.28, sz.x, 2.0), Color(0.30, 0.85, 1.0, 0.22))
	grid.draw_rect(Rect2(0, sz.y * 0.72, sz.x, 2.0), Color(0.30, 0.85, 1.0, 0.14))
