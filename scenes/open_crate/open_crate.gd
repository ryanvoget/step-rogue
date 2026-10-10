extends Control

const KEY_COST   := 2000
const CARD_W     := 110
const CARD_H     := 110
const CARD_GAP   := 8
const CARD_SLOT  := CARD_W + CARD_GAP  # 118
const WINNER_IDX := 42

const T := preload("res://scenes/ui/ui_theme.gd")
const HOLO_RING := preload("res://scenes/ui/holo_ring.gd")

# Card backing per rarity — a dark slab tinted toward the rarity hue rather than the rarity hue
# itself, so the icon on top stays the brightest thing on the card (see the reference: the panel
# is dark, the content glows).
const RARITY_COLORS := {
	"common":    Color(0.10, 0.12, 0.16),
	"uncommon":  Color(0.05, 0.18, 0.11),
	"rare":      Color(0.05, 0.11, 0.26),
	"epic":      Color(0.16, 0.06, 0.24),
	"legendary": Color(0.24, 0.17, 0.03),
}

@onready var _purchase:       Control     = $PurchaseScreen
@onready var _spin:           Control     = $SpinScreen
@onready var _result:         Control     = $ResultScreen
@onready var _balance:        Label       = $PurchaseScreen/VBox/KeyCard/CardVBox/BalanceLabel
@onready var _btn_buy:        Button      = $PurchaseScreen/VBox/KeyCard/CardVBox/BtnBuyKey
@onready var _shortfall:      Label       = $PurchaseScreen/VBox/KeyCard/CardVBox/Shortfall
@onready var _odds_list:      VBoxContainer = $PurchaseScreen/VBox/OddsCard/OddsVBox/OddsList
@onready var _spin_stage:     Control     = $SpinScreen/VBox/SpinStage
@onready var _spin_track:     HBoxContainer = $SpinScreen/VBox/SpinStage/SpinTrack
@onready var _result_card:    PanelContainer = $ResultScreen/VBox/ResultCard
@onready var _result_rarity:  Label       = $ResultScreen/VBox/ResultCard/CardVBox/RarityLabel
@onready var _result_img:     TextureRect = $ResultScreen/VBox/ResultCard/CardVBox/ItemImage
@onready var _result_name:    Label       = $ResultScreen/VBox/ResultCard/CardVBox/ItemName

# Artifacts are no longer bought from crates — they're found during the run instead.
# Elemental crates yield boosts rather than items — they go to SaveManager.boost_inventory instead
# of the normal inventory (see _award). Same reel/spin presentation as every other crate.
const CRATES := [["weapon", "🗡️  Weapons"], ["equipment", "🎒  Equipment"], ["medical", "🧰  Medical"], ["elemental", "⚡  Elemental"]]

var _spinning := false        # true while the reel is scrolling — see _process ticker
var _spin_last_tick := -1
var _crate_btns: Array = []
var _spin_tween: Tween = null # the active reel tween — held to fast-forward it (see _input)
var _ff_label: Label = null   # transparent ⏩ watermark shown while fast-forwarding

func _ready() -> void:
	SceneManager.add_glass_background(self)
	_apply_holo_theme()
	$PurchaseScreen/VBox/Header/BtnBack.pressed.connect(SceneManager.go_to_menu)
	# Replace the single buy button with one per crate type, keeping it as a hidden template.
	_btn_buy.visible = false
	_build_crate_buttons()
	$ResultScreen/VBox/Actions/BtnOpenAnother.pressed.connect(_show_purchase)
	$ResultScreen/VBox/Actions/BtnGoMenu.pressed.connect(SceneManager.go_to_menu)
	_build_odds_list()
	_show_purchase()

func _build_crate_buttons() -> void:
	var parent := _btn_buy.get_parent()
	for c in CRATES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 50)
		b.set_meta("crate", c[0])
		b.set_meta("label", c[1])
		b.pressed.connect(_on_buy.bind(c[0]))
		parent.add_child(b)
		_crate_btns.append(b)
	# Keep the "not enough steps" note last, below the crate buttons.
	parent.move_child(_shortfall, parent.get_child_count() - 1)

func _show_purchase() -> void:
	_purchase.visible = true
	_spin.visible     = false
	_result.visible   = false
	var bank      := SaveManager.step_bank
	var can_afford := bank >= KEY_COST
	_balance.text     = "Balance: %d steps" % bank
	for b in _crate_btns:
		b.disabled = not can_afford
		b.text = "%s  🔑%d" % [b.get_meta("label"), KEY_COST]
	_shortfall.visible = not can_afford
	if not can_afford:
		_shortfall.text = "Need %d more steps" % (KEY_COST - bank)

func _on_buy(crate: String) -> void:
	if not SaveManager.spend_steps(KEY_COST):
		return
	var winner := ItemRegistry.roll_item_for_crate(crate)
	_show_spin(winner, crate)

# ── Spin ──────────────────────────────────────────────────────────────────────

func _show_spin(winner: Dictionary, crate: String) -> void:
	_purchase.visible = false
	_spin.visible     = true
	_result.visible   = false
	_build_track(winner, crate)
	# Wait one frame so SpinStage.size is resolved before reading it
	await get_tree().process_frame
	_animate_spin(winner)

func _build_track(winner: Dictionary, crate: String) -> void:
	for c in _spin_track.get_children():
		c.queue_free()
	var track: Array = []
	for _i in WINNER_IDX:
		track.append(ItemRegistry.random_item_for_crate(crate))
	track.append(winner)
	for _i in 8:
		track.append(ItemRegistry.random_item_for_crate(crate))
	for item in track:
		_spin_track.add_child(_make_card(item))

func _make_card(item: Dictionary) -> Control:
	var card := Control.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	var rarity: String = str(item.get("rarity", ""))
	var accent: Color = T.rarity_color(rarity)

	# Dark slab tinted toward the rarity, with a lit border and corner brackets — the item icon
	# on top stays the brightest thing on the card.
	var panel := PanelContainer.new()
	panel.position = Vector2.ZERO
	panel.size = Vector2(CARD_W, CARD_H)
	panel.custom_minimum_size = Vector2(CARD_W, CARD_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = RARITY_COLORS.get(rarity, Color(0.10, 0.12, 0.16)) as Color
	sb.border_color = Color(accent, 0.75)
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.set_corner_radius_all(8)
	sb.shadow_color = Color(accent, 0.25)
	sb.shadow_size = 6
	panel.add_theme_stylebox_override("panel", sb)
	card.add_child(panel)

	var deco := Control.new()
	deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(deco)
	deco.draw.connect(func():
		T.draw_brackets(deco, Rect2(3, 3, CARD_W - 6, CARD_H - 6), Color(accent, 0.85), 11.0, 1.5)
	)

	var tex := TextureRect.new()
	tex.position = Vector2.ZERO
	tex.size = Vector2(CARD_W, CARD_H)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var path: String = "res://assets/icons/" + str(item.get("file", ""))
	tex.texture = load(path)
	card.add_child(tex)

	return card

func _animate_spin(winner: Dictionary) -> void:
	var vw     := _spin_stage.size.x
	var init_x := vw * 0.5 - CARD_SLOT * 0.5
	# Land somewhere within the winner card, not always dead-center, so the stop looks random.
	# Kept well inside the card (±35% of its width) so it's still unambiguously the winner — and
	# the awarded item comes from `winner`, not the landing position, so this is purely visual.
	var jitter := randf_range(-CARD_W * 0.35, CARD_W * 0.35)
	var end_x  := vw * 0.5 - (WINNER_IDX * CARD_SLOT + CARD_W * 0.5) + jitter

	_spin_track.position = Vector2(init_x, 0)

	# _process plays a tick per card crossing the center while _spinning.
	_spin_last_tick = -1
	_spinning = true

	_spin_tween = create_tween()
	_spin_tween.tween_property(_spin_track, "position:x", end_x, 5.0) \
	  .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_spin_tween.tween_callback(func():
		_spinning = false
		_spin_tween = null
		_show_ff_watermark(false)
		if is_instance_valid(_spin_ring):
			_spin_ring.flare() # the emblem pulses as the readout locks on
		_show_result(winner)
	)

# Hold the screen while the reel spins to fast-forward it at 2x, with a transparent ⏩ watermark.
func _input(event: InputEvent) -> void:
	if not _spinning or _spin_tween == null or not _spin_tween.is_valid():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_spin_tween.set_speed_scale(2.0)
			_show_ff_watermark(true)
		else:
			_spin_tween.set_speed_scale(1.0)
			_show_ff_watermark(false)

func _show_ff_watermark(show: bool) -> void:
	if show:
		if _ff_label == null or not is_instance_valid(_ff_label):
			_ff_label = Label.new()
			_ff_label.text = "⏩"
			_ff_label.add_theme_font_size_override("font_size", 120)
			_ff_label.modulate = Color(1, 1, 1, 0.22) # watermark — barely there
			_ff_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			_ff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_ff_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_ff_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_ff_label)
	elif _ff_label != null and is_instance_valid(_ff_label):
		_ff_label.queue_free()
		_ff_label = null

# Ticker: a tick each time a new card scrolls under the center, slowing with the cubic ease-out.
func _process(_delta: float) -> void:
	if not _spinning:
		return
	var idx := int((_spin_stage.size.x * 0.5 - _spin_track.position.x) / CARD_SLOT)
	if idx != _spin_last_tick:
		_spin_last_tick = idx
		AudioManager.play_tick()

# ── Result ────────────────────────────────────────────────────────────────────

func _show_result(winner: Dictionary) -> void:
	# Three destinations: artifacts and elemental boosts each have their own (non-tradeable)
	# inventory, everything else goes to the shared one. A boost is identified by carrying the
	# melee/ranged effect pair rather than a `type`, since it isn't an equippable item.
	if winner.get("type", "") == "artifact":
		SaveManager.add_artifact(winner)
	elif winner.has("melee") and winner.has("ranged"):
		SaveManager.add_boost(winner)
	else:
		SaveManager.add_to_inventory(winner)
	_purchase.visible = false
	_spin.visible     = false
	_result.visible   = true
	# Materialise rather than cut — the card scales up from slightly small as it fades in.
	_result.modulate.a = 0.0
	_result_card.pivot_offset = _result_card.size * 0.5
	_result_card.scale = Vector2(0.88, 0.88)
	var rt := create_tween()
	rt.tween_property(_result, "modulate:a", 1.0, 0.25)
	rt.parallel().tween_property(_result_card, "scale", Vector2.ONE, 0.42) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var rarity: String = winner.get("rarity", "common")
	_result_rarity.text = rarity.capitalize()

	var col: Color = RARITY_COLORS.get(rarity, Color(0.2, 0.2, 0.2))
	var style := StyleBoxFlat.new()
	style.bg_color = col
	style.set_corner_radius_all(10)
	style.set_content_margin_all(24.0)
	_result_card.add_theme_stylebox_override("panel", style)

	_result_name.text = str(winner.get("name", ""))
	var path: String = "res://assets/icons/" + str(winner.get("file", ""))
	if ResourceLoader.exists(path):
		_result_img.texture = load(path)

# ── Odds list ─────────────────────────────────────────────────────────────────

func _build_odds_list() -> void:
	const ODDS := [
		["Legendary", "1%",  Color(1.0, 0.80, 0.10)],
		["Epic",      "4%",  Color(0.80, 0.40, 1.0)],
		["Rare",      "10%", Color(0.30, 0.55, 1.0)],
		["Uncommon",  "30%", Color(0.35, 0.90, 0.45)],
		["Common",    "55%", Color(0.70, 0.70, 0.75)],
	]
	for row in ODDS:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 0)

		var lbl_rarity := Label.new()
		lbl_rarity.text = row[0]
		lbl_rarity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_rarity.add_theme_font_size_override("font_size", 14)
		lbl_rarity.add_theme_color_override("font_color", row[2])
		hbox.add_child(lbl_rarity)

		var lbl_pct := Label.new()
		lbl_pct.text = row[1]
		lbl_pct.add_theme_font_size_override("font_size", 14)
		hbox.add_child(lbl_pct)

		_odds_list.add_child(hbox)

# ── Holo presentation ────────────────────────────────────────────────────────────────────────
# The crate screens are styled as projected console panels: dark translucent slabs with a lit top
# edge, cyan linework, and a rotating emblem behind the reel. The spin itself is reframed as a
# scanning readout rather than a slot machine — the reference's language is diagnostic displays,
# not casino reels.

func _apply_holo_theme() -> void:
	for card in [$PurchaseScreen/VBox/KeyCard, $PurchaseScreen/VBox/OddsCard, _result_card]:
		if card != null and is_instance_valid(card):
			card.add_theme_stylebox_override("panel", T.panel_box(T.CYAN, T.PANEL_GLASS, 12))
	for scr in [$PurchaseScreen, $SpinScreen, $ResultScreen]:
		T.style_all_buttons(scr, T.CYAN)
	$PurchaseScreen/VBox/Header/Title.add_theme_color_override("font_color", T.CYAN_HOT)
	for lbl in [$PurchaseScreen/VBox/KeyCard/CardVBox/CrateName,
			$PurchaseScreen/VBox/OddsCard/OddsVBox/OddsTitle]:
		lbl.add_theme_color_override("font_color", T.CYAN)
	_balance.add_theme_color_override("font_color", T.AMBER)
	_build_spin_frame()

# Emblem + frame behind the reel, so the cards appear to scroll through a projector rather than
# across a blank strip.
var _spin_ring: Control = null
var _spin_frame: Control = null

func _build_spin_frame() -> void:
	_spin_ring = HOLO_RING.new()
	_spin_ring.custom_minimum_size = Vector2(230, 230)
	_spin_ring.size = Vector2(230, 230)
	_spin_ring.modulate = Color(1, 1, 1, 0.5)
	_spin_ring.z_index = -2
	_spin_stage.add_child(_spin_ring)
	_spin_stage.move_child(_spin_ring, 0)

	# The frame: brackets and edge rails drawn over the reel, marking the read window.
	_spin_frame = Control.new()
	_spin_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_spin_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spin_stage.add_child(_spin_frame)
	_spin_frame.draw.connect(_draw_spin_frame)
	_spin_stage.resized.connect(func():
		if is_instance_valid(_spin_ring):
			_spin_ring.position = _spin_stage.size * 0.5 - _spin_ring.size * 0.5
		if is_instance_valid(_spin_frame):
			_spin_frame.queue_redraw()
	)

func _draw_spin_frame() -> void:
	var sz := _spin_frame.size
	if sz.x <= 0.0:
		return
	# Dim the reel outside the centre window so the eye is pulled to the card about to land.
	var win := CARD_W + 16.0
	var cx := sz.x * 0.5
	_spin_frame.draw_rect(Rect2(0, 0, cx - win * 0.5, sz.y), Color(T.VOID, 0.55))
	_spin_frame.draw_rect(Rect2(cx + win * 0.5, 0, sz.x - cx - win * 0.5, sz.y), Color(T.VOID, 0.55))
	# The read window itself: bracketed, with a hot centre line.
	var r := Rect2(cx - win * 0.5, 2.0, win, sz.y - 4.0)
	T.draw_brackets(_spin_frame, r, Color(T.CYAN, 0.9), 16.0, 2.0)
	T.draw_glow_line(_spin_frame, Vector2(cx, 0.0), Vector2(cx, sz.y), T.CYAN_HOT, 1.0, 0.55)
	# Emitter rails top and bottom, the lit edges from the reference panel.
	T.draw_glow_line(_spin_frame, Vector2(0, 1.0), Vector2(sz.x, 1.0), T.CYAN, 1.5, 0.8)
	T.draw_glow_line(_spin_frame, Vector2(0, sz.y - 1.0), Vector2(sz.x, sz.y - 1.0), T.CYAN, 1.5, 0.8)
