extends Node2D

const PLAYER_SCENE     := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE      := preload("res://scenes/enemies/enemy_basic.tscn")
const BULLET_SCENE     := preload("res://scenes/bullets/bullet.tscn")
const BASE_ENEMY_COUNT := 3

@onready var _room:    Node2D = $Room
@onready var _enemies: Node   = $Enemies
@onready var _bullets: Node   = $Bullets
@onready var _hud = $HUD

var _enemies_alive := 0
var _clearing      := false

func _ready() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	GameManager.register_bullets_container(_bullets)
	_spawn_player()
	_hud.game_started.connect(_spawn_enemies)
	if OS.has_feature("ios") or OS.has_feature("android"):
		add_child(preload("res://scenes/ui/mobile_controls.tscn").instantiate())

func _exit_tree() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)

func _spawn_player() -> void:
	var p: CharacterBody2D = PLAYER_SCENE.instantiate()
	p.bullet_scene = BULLET_SCENE
	add_child(p)
	p.global_position = _room.player_spawn_pos

func _spawn_enemies() -> void:
	var count  := BASE_ENEMY_COUNT + (GameManager.current_floor - 1)
	var spawns: Array = _room.enemy_spawn_positions
	_enemies_alive = mini(count, spawns.size())
	for i in range(_enemies_alive):
		var e: CharacterBody2D = ENEMY_SCENE.instantiate()
		e.global_position = spawns[i]
		e.died.connect(_on_enemy_died)
		_enemies.add_child(e)

func _on_enemy_died() -> void:
	_enemies_alive -= 1
	if _enemies_alive <= 0 and not _clearing:
		_on_room_cleared()

func _on_room_cleared() -> void:
	_clearing = true
	GameManager.room_cleared.emit()
	await get_tree().create_timer(2.0).timeout
	if not is_inside_tree():
		return
	GameManager.next_floor()
	_clearing = false
	_spawn_enemies()
