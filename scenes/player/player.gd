extends CharacterBody2D

const SPEED     := 180.0
const FRAME_W   := 64
const FRAME_H   := 64
const IDLE_FPS  := 8.0
const RUN_FPS   := 10.0

const SHIRT_HUES := {
	"blue":   0.583,
	"red":    0.0,
	"yellow": 0.144,
	"green":  0.361,
}

@export var bullet_scene: PackedScene
@export var max_health := 100

var health: int
var _can_shoot := true
var _mouse_angle := 0.0

@onready var _spawn_point: Marker2D    = $BulletSpawnPoint
@onready var _shoot_timer: Timer       = $ShootCooldown
@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _weapon: Sprite2D         = $Weapon

signal health_changed(current: int, maximum: int)
signal died

func _ready() -> void:
	health = max_health
	add_to_group("player")
	_shoot_timer.timeout.connect(func(): _can_shoot = true)
	_setup_sprite()
	_setup_weapon()

func _setup_sprite() -> void:
	var idle_tex: Texture2D = load("res://assets/sprites/idle_spritesheet.png")
	var run_tex:  Texture2D = load("res://assets/sprites/run_spritesheet.png")
	var sf := SpriteFrames.new()
	sf.remove_animation("default")

	# Idle: 5 frames from idle_spritesheet
	sf.add_animation("idle")
	sf.set_animation_speed("idle", IDLE_FPS)
	sf.set_animation_loop("idle", true)
	for i in range(5):
		var atlas := AtlasTexture.new()
		atlas.atlas = idle_tex
		atlas.region = Rect2(i * FRAME_W, 0, FRAME_W, FRAME_H)
		sf.add_frame("idle", atlas)

	# Directional run: run_spritesheet layout
	# [0]=up1 [1]=up2 [2]=down1 [3]=down2 [4]=right1 [5]=right2 [6]=left1 [7]=left2
	var run_anims := {
		"run_up":    [0, 1],
		"run_down":  [2, 3],
		"run_right": [4, 5],
		"run_left":  [6, 7],
	}
	for anim_name in run_anims:
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, RUN_FPS)
		sf.set_animation_loop(anim_name, true)
		for idx in run_anims[anim_name]:
			var atlas := AtlasTexture.new()
			atlas.atlas = run_tex
			atlas.region = Rect2(idx * FRAME_W, 0, FRAME_W, FRAME_H)
			sf.add_frame(anim_name, atlas)

	_sprite.sprite_frames = sf
	_sprite.play("idle")
	_apply_shirt_color()

func _physics_process(_delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED
	var to_mouse := get_global_mouse_position() - global_position
	_mouse_angle = to_mouse.angle()
	_spawn_point.position = Vector2(22, 0).rotated(_mouse_angle)
	move_and_slide()
	_update_sprite(dir)
	_update_weapon()

func _setup_weapon() -> void:
	_weapon.texture = load("res://assets/sprites/assault_rifle.png")
	_weapon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _apply_shirt_color() -> void:
	var shader := load("res://scenes/character/shirt_recolor.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("target_hue", SHIRT_HUES.get(SaveManager.shirt_color, 0.583))
	_sprite.material = mat

func _update_weapon() -> void:
	_weapon.rotation = _mouse_angle
	_weapon.flip_v   = absf(_mouse_angle) > PI / 2

func _update_sprite(dir: Vector2) -> void:
	var anim: String
	if dir == Vector2.ZERO:
		anim = "idle"
	elif absf(dir.x) >= absf(dir.y):
		anim = "run_right" if dir.x > 0.0 else "run_left"
	elif dir.y < 0.0:
		anim = "run_up"
	else:
		anim = "run_down"
	if _sprite.animation != anim:
		_sprite.play(anim)
	_sprite.flip_h = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_try_shoot()
	elif event.is_action_pressed("shoot"):
		_try_shoot()

func _try_shoot() -> void:
	if not _can_shoot or bullet_scene == null:
		return
	_can_shoot = false
	_shoot_timer.start()
	GameManager.spawn_bullet(bullet_scene, _spawn_point.global_position, _mouse_angle)

func take_damage(amount: int) -> void:
	health = max(0, health - amount)
	health_changed.emit(health, max_health)
	GameManager.health_changed.emit(health, max_health)
	if health == 0:
		died.emit()
		GameManager.player_died.emit()
		queue_free()
