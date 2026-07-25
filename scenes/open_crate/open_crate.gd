extends Control

const KEY_COST   := 2000
const CARD_W     := 110
const CARD_H     := 110
const CARD_GAP   := 8
const CARD_SLOT  := CARD_W + CARD_GAP  # 118
const WINNER_IDX := 42

const RARITY_COLORS := {
	"common":    Color(0.22, 0.22, 0.27),
	"uncommon":  Color(0.07, 0.32, 0.11),
	"rare":      Color(0.07, 0.14, 0.48),
	"epic":      Color(0.28, 0.07, 0.42),
	"legendary": Color(0.50, 0.35, 0.00),
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

const CRATES := [["weapon", "🗡️  Weapons"], ["equipment", "🎒  Equipment"], ["medical", "🧰  Medical"]]

var _spinning := false        # true while the reel is scrolling — see _process ticker
var _spin_last_tick := -1
var _crate_btns: Array = []

func _ready() -> void:
	SceneManager.add_glass_background(self)
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

	var bg := ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = Vector2(CARD_W, CARD_H)
	bg.color = RARITY_COLORS.get(item.get("rarity", ""), Color(0.2, 0.2, 0.2)) as Color
	card.add_child(bg)

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

	var tw := create_tween()
	tw.tween_property(_spin_track, "position:x", end_x, 5.0) \
	  .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		_spinning = false
		_show_result(winner)
	)

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
	SaveManager.add_to_inventory(winner)
	_purchase.visible = false
	_spin.visible     = false
	_result.visible   = true

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
