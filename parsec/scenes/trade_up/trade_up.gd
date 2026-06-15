extends Control

const REQUIRED   := 10
const CARD_W     := 90
const CARD_H     := 90
const CARD_SLOT  := CARD_W + 8   # 98
const WINNER_IDX := 42

const RARITY_UP := { "common": "uncommon", "uncommon": "rare", "rare": "epic" }
const ELIGIBLE  := ["common", "uncommon", "rare"]

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

var _selected:       Array  = []
var _current_rarity: String = ""

@onready var _select:         Control        = $SelectScreen
@onready var _spin:           Control        = $SpinScreen
@onready var _result:         Control        = $ResultScreen
@onready var _content:        VBoxContainer  = $SelectScreen/VBox/ScrollArea/Content
@onready var _hint:           Label          = $SelectScreen/VBox/Footer/HintLabel
@onready var _btn_confirm:    Button         = $SelectScreen/VBox/Footer/BtnConfirm
@onready var _spin_stage:     Control        = $SpinScreen/VBox/SpinStage
@onready var _spin_track:     HBoxContainer  = $SpinScreen/VBox/SpinStage/SpinTrack
@onready var _result_card:    PanelContainer = $ResultScreen/VBox/ResultCard
@onready var _result_rarity:  Label          = $ResultScreen/VBox/ResultCard/CardVBox/RarityLabel
@onready var _result_img:     TextureRect    = $ResultScreen/VBox/ResultCard/CardVBox/ItemImage
@onready var _result_name:    Label          = $ResultScreen/VBox/ResultCard/CardVBox/ItemName

func _ready() -> void:
	$SelectScreen/VBox/Header/BtnBack.pressed.connect(
		func(): SceneManager.go_to("res://scenes/inventory/inventory.tscn"))
	_btn_confirm.pressed.connect(_on_confirm)
	$ResultScreen/VBox/Actions/BtnTradeAgain.pressed.connect(_show_select)
	$ResultScreen/VBox/Actions/BtnGoInventory.pressed.connect(
		func(): SceneManager.go_to("res://scenes/inventory/inventory.tscn"))
	_show_select()

# ── Select screen ─────────────────────────────────────────────────────────────

func _show_select() -> void:
	_selected.clear()
	_current_rarity = ""
	_select.visible = true
	_spin.visible   = false
	_result.visible = false
	_build_grid()
	_sync_footer()

func _build_grid() -> void:
	for c in _content.get_children():
		c.queue_free()

	var items     := SaveManager.inventory
	var has_items := false

	for rarity in ELIGIBLE:
		var group: Array = []
		for i in items.size():
			if items[i].get("rarity", "") == rarity:
				group.append({ "item": items[i], "inv_idx": i })
		if group.is_empty():
			continue
		has_items = true
		_add_section(rarity, group)

	if not has_items:
		_build_empty_state()

func _add_section(rarity: String, group: Array) -> void:
	var header := Label.new()
	header.text = rarity.capitalize()
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", RARITY_LABEL[rarity])
	_content.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(grid)

	for entry in group:
		grid.add_child(_make_card(entry.item, entry.inv_idx))

func _make_card(item: Dictionary, inv_idx: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CARD_W, CARD_H)
	btn.flat       = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_meta("inv_idx", inv_idx)
	btn.set_meta("rarity",  item.get("rarity", ""))

	var bg := ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = Vector2(CARD_W, CARD_H)
	bg.color = RARITY_BG.get(item.get("rarity", ""), Color(0.2, 0.2, 0.2)) as Color
	btn.add_child(bg)

	var tex := TextureRect.new()
	tex.position = Vector2.ZERO
	tex.size = Vector2(CARD_W, CARD_H)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path: String = "res://assets/icons/" + str(item.get("file", ""))
	tex.texture = load(path)
	btn.add_child(tex)

	# White flash overlay = selected
	var sel_overlay := ColorRect.new()
	sel_overlay.name = "SelOverlay"
	sel_overlay.position = Vector2.ZERO
	sel_overlay.size = Vector2(CARD_W, CARD_H)
	sel_overlay.color       = Color(1, 1, 1, 0.30)
	sel_overlay.visible     = false
	sel_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(sel_overlay)

	# Dark overlay = locked
	var lock_overlay := ColorRect.new()
	lock_overlay.name = "LockOverlay"
	lock_overlay.position = Vector2.ZERO
	lock_overlay.size = Vector2(CARD_W, CARD_H)
	lock_overlay.color       = Color(0, 0, 0, 0.60)
	lock_overlay.visible     = false
	lock_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lock_overlay)

	btn.pressed.connect(func(): _on_card_pressed(inv_idx, str(item.get("rarity", ""))))
	return btn

func _on_card_pressed(inv_idx: int, rarity: String) -> void:
	if _current_rarity != "" and rarity != _current_rarity:
		return
	if _selected.has(inv_idx):
		_selected.erase(inv_idx)
		if _selected.is_empty():
			_current_rarity = ""
	else:
		if _selected.size() >= REQUIRED:
			return
		_selected.append(inv_idx)
		_current_rarity = rarity
	_sync_cards()
	_sync_footer()

func _sync_cards() -> void:
	for node in _content.get_children():
		if not node is GridContainer:
			continue
		for card in node.get_children():
			var inv_idx: int   = card.get_meta("inv_idx", -1)
			var rarity:  String = card.get_meta("rarity", "")
			var is_sel  := _selected.has(inv_idx)
			var is_locked := _current_rarity != "" and rarity != _current_rarity
			card.get_node("SelOverlay").visible  = is_sel
			card.get_node("LockOverlay").visible = is_locked and not is_sel

func _sync_footer() -> void:
	var count := _selected.size()
	_hint.text = (
		"%d / %d %s selected" % [count, REQUIRED, _current_rarity]
		if _current_rarity != ""
		else "Select 10 items of the same rarity"
	)
	_btn_confirm.disabled = count != REQUIRED

func _build_empty_state() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 80)
	_content.add_child(spacer)
	for pair in [["No eligible items", 18], ["Collect common, uncommon, or rare\nitems from crates to trade up.", 14]]:
		var lbl := Label.new()
		lbl.text = pair[0]
		lbl.add_theme_font_size_override("font_size", pair[1])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_content.add_child(lbl)

# ── Confirm → spin ────────────────────────────────────────────────────────────

func _on_confirm() -> void:
	if _selected.size() != REQUIRED:
		return
	var new_rarity := RARITY_UP[_current_rarity]
	var pool       := ItemRegistry.items_of_rarity(new_rarity)
	var winner     := pool[randi() % pool.size()]
	SaveManager.remove_items_by_indices(_selected.duplicate())
	_show_spin(winner, pool)

func _show_spin(winner: Dictionary, pool: Array) -> void:
	_select.visible = false
	_spin.visible   = true
	_result.visible = false
	_build_track(winner, pool)
	await get_tree().process_frame
	_animate_spin(winner)

func _build_track(winner: Dictionary, pool: Array) -> void:
	for c in _spin_track.get_children():
		c.queue_free()
	var track: Array = []
	for _i in WINNER_IDX:
		track.append(pool[randi() % pool.size()])
	track.append(winner)
	for _i in 8:
		track.append(pool[randi() % pool.size()])
	for item in track:
		_spin_track.add_child(_make_spin_card(item))

func _make_spin_card(item: Dictionary) -> Control:
	var card := Control.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	var bg := ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = Vector2(CARD_W, CARD_H)
	bg.color = RARITY_BG.get(item.get("rarity", ""), Color(0.2, 0.2, 0.2)) as Color
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
	var vw    := _spin_stage.size.x
	var init  := vw * 0.5 - CARD_SLOT * 0.5
	var final := vw * 0.5 - (WINNER_IDX * CARD_SLOT + CARD_W * 0.5)
	_spin_track.position = Vector2(init, 0)
	var tw := create_tween()
	tw.tween_property(_spin_track, "position:x", final, 5.0) \
	  .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _show_result(winner))

# ── Result ────────────────────────────────────────────────────────────────────

func _show_result(winner: Dictionary) -> void:
	SaveManager.add_to_inventory(winner)
	_select.visible = false
	_spin.visible   = false
	_result.visible = true

	var rarity: String = winner.get("rarity", "common")
	_result_rarity.text = rarity.capitalize()
	_result_name.text   = str(winner.get("name", ""))

	var style := StyleBoxFlat.new()
	style.bg_color = RARITY_BG.get(rarity, Color(0.2, 0.2, 0.2)) as Color
	style.set_corner_radius_all(10)
	style.set_content_margin_all(24.0)
	_result_card.add_theme_stylebox_override("panel", style)

	var path: String = "res://assets/icons/" + str(winner.get("file", ""))
	_result_img.texture = load(path) if ResourceLoader.exists(path) else null
