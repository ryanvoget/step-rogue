extends Control

const CARD_SIZE := 100

const RARITY_BG := {
	"common":    Color(0.22, 0.22, 0.27),
	"uncommon":  Color(0.07, 0.32, 0.11),
	"rare":      Color(0.07, 0.14, 0.48),
	"epic":      Color(0.28, 0.07, 0.42),
	"legendary": Color(0.50, 0.35, 0.00),
}
const RARITY_LABEL := {
	"common":    Color(0.70, 0.70, 0.75),
	"uncommon":  Color(0.35, 0.90, 0.45),
	"rare":      Color(0.30, 0.55, 1.00),
	"epic":      Color(0.80, 0.40, 1.00),
	"legendary": Color(1.00, 0.80, 0.10),
}
const ORDER := ["legendary", "epic", "rare", "uncommon", "common"]

@onready var _content:     VBoxContainer = $VBox/ScrollArea/Content
@onready var _count_label: Label         = $VBox/Header/CountLabel
@onready var _actions:     HBoxContainer = $VBox/Actions

func _ready() -> void:
	$VBox/Header/BtnBack.pressed.connect(SceneManager.go_to_menu)
	$VBox/Actions/BtnTradeUp.pressed.connect(
		func(): SceneManager.go_to("res://scenes/trade_up/trade_up.tscn"))
	$VBox/Actions/BtnClear.pressed.connect(_on_clear)
	_refresh()

func _refresh() -> void:
	for c in _content.get_children():
		c.queue_free()

	var items := SaveManager.inventory
	_count_label.text = "(%d)" % items.size() if items.size() > 0 else ""

	if items.is_empty():
		_actions.visible = false
		_build_empty_state()
		return

	_actions.visible = true
	for rarity in ORDER:
		var group: Array = items.filter(func(i): return i.get("rarity", "") == rarity)
		if group.is_empty():
			continue
		_add_section(rarity, group)

# ── Sections ──────────────────────────────────────────────────────────────────

func _add_section(rarity: String, items: Array) -> void:
	var header := Label.new()
	header.text = "%s  %d" % [rarity.capitalize(), items.size()]
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", RARITY_LABEL[rarity])
	_content.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(grid)

	for item in items:
		grid.add_child(_make_card(item))

func _make_card(item: Dictionary) -> Control:
	var card := Control.new()
	card.custom_minimum_size = Vector2(CARD_SIZE, CARD_SIZE)

	var bg := ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = Vector2(CARD_SIZE, CARD_SIZE)
	bg.color = RARITY_BG.get(item.get("rarity", ""), Color(0.2, 0.2, 0.2)) as Color
	card.add_child(bg)

	var tex := TextureRect.new()
	tex.position = Vector2.ZERO
	tex.size = Vector2(CARD_SIZE, CARD_SIZE)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var path: String = "res://assets/icons/" + str(item.get("file", ""))
	tex.texture = load(path)
	card.add_child(tex)

	return card

# ── Empty state ───────────────────────────────────────────────────────────────

func _build_empty_state() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 100)
	_content.add_child(spacer)

	for text in [["🎒", 52], ["No items yet", 18], ["Open crates to find items", 14]]:
		var lbl := Label.new()
		lbl.text = text[0]
		lbl.add_theme_font_size_override("font_size", text[1])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_content.add_child(lbl)

# ── Actions ───────────────────────────────────────────────────────────────────

func _on_clear() -> void:
	SaveManager.clear_inventory()
	_refresh()
