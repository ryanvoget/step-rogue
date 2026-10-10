extends Node
class_name UITheme

# Shared visual language for every screen, derived from the two reference images:
# the dark ship interior with glowing cyan holograms, and the deep-space plate.
#
# The rule the references follow, and the one everything here obeys: the world is almost black,
# and ONLY the holographic elements emit light. Nothing is mid-grey. A surface is either part of
# the dark hull or it glows — that contrast is what makes the look read as a hologram rather than
# as a flat blue UI.
#
# Every screen pulls its colours and panel/button builders from here rather than hand-rolling
# styleboxes, so a palette change lands everywhere at once.

# ── Palette ──────────────────────────────────────────────────────────────────────────────────
const VOID        := Color(0.016, 0.027, 0.043) # deepest background, near-black blue
const HULL        := Color(0.043, 0.063, 0.090) # ship panelling
const HULL_LIT    := Color(0.075, 0.106, 0.145) # panel catching light
const PANEL_GLASS := Color(0.047, 0.098, 0.141, 0.82) # holo panel fill (translucent)

const CYAN        := Color(0.373, 0.847, 0.961) # primary hologram
const CYAN_HOT    := Color(0.878, 0.976, 1.000) # the white-hot core of a glowing edge
const CYAN_DIM    := Color(0.204, 0.478, 0.588) # unlit holo linework
const AMBER       := Color(1.000, 0.663, 0.200) # the warm accent chips in the reference panel
const AMBER_HOT   := Color(1.000, 0.839, 0.569)

const TEXT        := Color(0.878, 0.937, 0.980)
const TEXT_DIM    := Color(0.482, 0.584, 0.675)
const DANGER      := Color(1.000, 0.361, 0.333)
const GOOD        := Color(0.392, 0.902, 0.529)

# Rarity colours, pushed toward emissive so they sit in the same holo world as everything else.
const RARITY := {
	"common":    Color(0.561, 0.639, 0.714),
	"uncommon":  Color(0.306, 0.902, 0.510),
	"rare":      Color(0.310, 0.639, 1.000),
	"epic":      Color(0.761, 0.420, 1.000),
	"legendary": Color(1.000, 0.737, 0.200),
}

static func rarity_color(r: String) -> Color:
	return RARITY.get(r, TEXT_DIM)

# ── Holo panel ───────────────────────────────────────────────────────────────────────────────
# The reference screen is a dark translucent slab with ONE bright edge where the emitter runs.
# That single lit edge is what sells it as a projection, so panels here get a cyan border with a
# brighter top rather than a uniform outline.
static func panel_box(accent: Color = CYAN, fill: Color = PANEL_GLASS, radius: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = Color(accent, 0.45)
	s.set_border_width_all(1)
	s.border_width_top = 2
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14.0
	s.content_margin_right = 14.0
	s.content_margin_top = 11.0
	s.content_margin_bottom = 11.0
	s.shadow_color = Color(accent, 0.16)
	s.shadow_size = 8
	return s

# A flatter inner surface for rows/chips sitting inside a panel.
static func inset_box(tint: Color = CYAN, radius: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(tint.r * 0.18, tint.g * 0.22, tint.b * 0.28, 0.40)
	s.border_color = Color(tint, 0.28)
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 10.0
	s.content_margin_right = 10.0
	s.content_margin_top = 7.0
	s.content_margin_bottom = 7.0
	return s

# ── Buttons ──────────────────────────────────────────────────────────────────────────────────
# Dark slab, cyan rule, and a hover state that brightens rather than changing hue — the same way
# the reference console's chips read as lit vs unlit rather than as different colours.
static func button_box(accent: Color, lit: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(accent.r * 0.10 + 0.02, accent.g * 0.14 + 0.03, accent.b * 0.20 + 0.05,
		0.55 + 0.25 * lit)
	s.border_color = Color(accent, 0.35 + 0.5 * lit)
	s.set_border_width_all(1)
	s.border_width_left = 3 # the emitter rail down one side
	s.set_corner_radius_all(8)
	s.content_margin_left = 16.0
	s.content_margin_right = 16.0
	s.content_margin_top = 10.0
	s.content_margin_bottom = 10.0
	s.shadow_color = Color(accent, 0.22 * lit)
	s.shadow_size = int(10 * lit)
	return s

static func style_button(btn: Button, accent: Color = CYAN, font_size: int = 15) -> void:
	btn.flat = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_stylebox_override("normal", button_box(accent, 0.0))
	btn.add_theme_stylebox_override("hover", button_box(accent, 0.6))
	btn.add_theme_stylebox_override("pressed", button_box(accent, 1.0))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("disabled", button_box(TEXT_DIM, 0.0))
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", CYAN_HOT)
	btn.add_theme_color_override("font_pressed_color", CYAN_HOT)
	btn.add_theme_color_override("font_disabled_color", Color(TEXT_DIM, 0.55))

# Walks a subtree and themes every Button it finds — screens are built at runtime in several
# places, so this is how they get restyled without touching each construction site.
static func style_all_buttons(root: Node, accent: Color = CYAN) -> void:
	for child in root.get_children():
		if child is Button:
			style_button(child, accent)
		style_all_buttons(child, accent)

# ── Glow drawing ─────────────────────────────────────────────────────────────────────────────
# Godot has no bloom on a plain CanvasItem, so "glowing" is faked the way the reference does it
# optically: the same shape drawn several times, widest and faintest first, with a white-hot core
# last. Used by the holo ring, the map light sources and the crate frame alike.
static func draw_glow_circle(ci: CanvasItem, pos: Vector2, radius: float, col: Color,
		intensity: float = 1.0) -> void:
	ci.draw_circle(pos, radius * 2.2, Color(col, 0.05 * intensity))
	ci.draw_circle(pos, radius * 1.5, Color(col, 0.10 * intensity))
	ci.draw_circle(pos, radius, Color(col, 0.22 * intensity))
	ci.draw_circle(pos, radius * 0.45, Color(col, 0.45 * intensity))

static func draw_glow_line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color,
		width: float = 2.0, intensity: float = 1.0) -> void:
	ci.draw_line(a, b, Color(col, 0.10 * intensity), width * 4.0)
	ci.draw_line(a, b, Color(col, 0.28 * intensity), width * 2.0)
	ci.draw_line(a, b, Color(col, 0.95 * intensity), width)
	ci.draw_line(a, b, Color(CYAN_HOT, 0.75 * intensity), width * 0.4)

static func draw_glow_arc(ci: CanvasItem, pos: Vector2, radius: float, from: float, to: float,
		col: Color, width: float = 2.0, intensity: float = 1.0, segments: int = 48) -> void:
	ci.draw_arc(pos, radius, from, to, segments, Color(col, 0.12 * intensity), width * 3.5)
	ci.draw_arc(pos, radius, from, to, segments, Color(col, 0.35 * intensity), width * 1.8)
	ci.draw_arc(pos, radius, from, to, segments, Color(col, 0.95 * intensity), width)

# Corner brackets — the "[ ]" framing that reads as a targeting reticle on the reference HUD.
static func draw_brackets(ci: CanvasItem, rect: Rect2, col: Color, size: float = 14.0,
		width: float = 2.0) -> void:
	var p := rect.position
	var e := rect.end
	for corner in [
		[Vector2(p.x, p.y), Vector2(1, 0), Vector2(0, 1)],
		[Vector2(e.x, p.y), Vector2(-1, 0), Vector2(0, 1)],
		[Vector2(p.x, e.y), Vector2(1, 0), Vector2(0, -1)],
		[Vector2(e.x, e.y), Vector2(-1, 0), Vector2(0, -1)],
	]:
		var o: Vector2 = corner[0]
		ci.draw_line(o, o + (corner[1] as Vector2) * size, col, width)
		ci.draw_line(o, o + (corner[2] as Vector2) * size, col, width)
