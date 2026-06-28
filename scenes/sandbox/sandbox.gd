extends Node2D

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE  := preload("res://scenes/enemies/enemy_basic.tscn")
const BULLET_SCENE := preload("res://scenes/bullets/bullet.tscn")

@onready var _room:    Node2D = $Room
@onready var _bullets: Node   = $Bullets

func _ready() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	GameManager.register_bullets_container(_bullets)
	_spawn_player()
	_spawn_dummy()
	$HUD/BtnMenu.pressed.connect(_on_menu_pressed)
	_setup_equipped_icons()

func _setup_equipped_icons() -> void:
	var row: HBoxContainer = $HUD/EquippedRow
	for key in ["equipped_weapon", "equipped_equipment", "equipped_defensive"]:
		var item: Dictionary = SaveManager.get(key)
		var slot_bg := ColorRect.new()
		slot_bg.custom_minimum_size = Vector2(38, 38)
		slot_bg.color = Color(0.08, 0.1, 0.15, 0.85)
		if not item.is_empty():
			var tex_rect := TextureRect.new()
			tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			tex_rect.texture      = load("res://assets/icons/" + item["file"])
			tex_rect.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			slot_bg.add_child(tex_rect)
		row.add_child(slot_bg)

func _exit_tree() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)

func _spawn_player() -> void:
	var p: CharacterBody2D = PLAYER_SCENE.instantiate()
	p.bullet_scene = BULLET_SCENE
	add_child(p)
	p.global_position = _room.player_spawn_pos

func _spawn_dummy() -> void:
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	e.sandbox_mode = true
	e.global_position = _room.enemy_spawn_positions[0]
	e.died.connect(_spawn_dummy)
	add_child(e)

func _on_menu_pressed() -> void:
	SceneManager.go_to_menu()
