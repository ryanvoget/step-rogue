extends Node2D

const PLAYER_SCENE     := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE      := preload("res://scenes/enemies/enemy_basic.tscn")
const BULLET_SCENE     := preload("res://scenes/bullets/bullet.tscn")
const TURRET_SCENE     := preload("res://scenes/turret/turret.tscn")
const GRENADE_SCENE    := preload("res://scenes/grenade/grenade.tscn")
const BASE_ENEMY_COUNT := 3

@onready var _room:    Node2D = $Room
@onready var _enemies: Node   = $Enemies
@onready var _bullets: Node   = $Bullets
@onready var _hud = $HUD

var _player: CharacterBody2D = null
var _enemies_alive  := 0
var _clearing       := false

func _ready() -> void:
	GameManager.register_bullets_container(_bullets)
	GameManager.equipment_placeable = SaveManager.equipped_equipment.get("placeable", false)
	GameManager.equipment_throwable = SaveManager.equipped_equipment.get("throwable", false)
	GameManager.equipment_deployed  = false
	GameManager.deploy_equipment_requested.connect(_use_equipment)
	_spawn_player()
	_hud.game_started.connect(_spawn_enemies)
	if OS.has_feature("ios") or OS.has_feature("android") or OS.has_feature("editor"):
		add_child(preload("res://scenes/ui/mobile_controls.tscn").instantiate())

func _spawn_player() -> void:
	var p: CharacterBody2D = PLAYER_SCENE.instantiate()
	p.bullet_scene = BULLET_SCENE
	add_child(p)
	p.global_position = _room.player_spawn_pos
	_player = p
	if not SaveManager.equipped_weapon.is_empty():
		ItemRegistry.equip_on_player(p, SaveManager.equipped_weapon)

# Uses the equipped equipment (Turret/Advanced Turret = deploy in place; Blast Grenade =
# throw in the direction the throw joystick was released, from mobile_controls). One-time
# per run — mobile_controls hides its button after this fires once.
func _use_equipment(angle: float) -> void:
	if GameManager.equipment_deployed:
		return
	var item: Dictionary = SaveManager.equipped_equipment
	if item.is_empty():
		return
	if item.get("placeable", false):
		GameManager.equipment_deployed = true
		_deploy_turret(item)
	elif item.get("throwable", false):
		GameManager.equipment_deployed = true
		_throw_grenade(item, angle)

func _deploy_turret(item: Dictionary) -> void:
	var turret: Node2D = TURRET_SCENE.instantiate()
	add_child(turret)
	turret.global_position = _player.global_position
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	turret.configure(tex, item["damage"], item["fire_rate"], item["bullet_speed"])

func _throw_grenade(item: Dictionary, angle: float) -> void:
	var grenade: Node2D = GRENADE_SCENE.instantiate()
	add_child(grenade)
	var tex: Texture2D = load("res://assets/icons/" + item["file"])
	var origin: Vector2 = _player.global_position
	var landing: Vector2 = origin + Vector2.RIGHT.rotated(angle) * item["throw_distance"]
	grenade.configure(tex, origin, landing, item["damage"], item["aoe_radius"], item["explode_delay"])

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
