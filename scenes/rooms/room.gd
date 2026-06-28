extends Node2D

const ROOM_W := 480.0
const ROOM_H := 854.0
const WALL_T := 28.0

var player_spawn_pos: Vector2
var enemy_spawn_positions: Array

func _ready() -> void:
	_build_walls()
	player_spawn_pos = Vector2(ROOM_W * 0.5, ROOM_H - 100.0)
	enemy_spawn_positions = [
		Vector2(ROOM_W * 0.5,  120.0),
		Vector2(120.0,          ROOM_H * 0.35),
		Vector2(ROOM_W - 120.0, ROOM_H * 0.35),
		Vector2(120.0,          ROOM_H * 0.65),
		Vector2(ROOM_W - 120.0, ROOM_H * 0.65),
	]

func _draw() -> void:
	# Floor
	draw_rect(Rect2(0, 0, ROOM_W, ROOM_H), Color(0.05, 0.04, 0.14))
	# Walls
	var wc := Color(0.14, 0.13, 0.32)
	draw_rect(Rect2(0,            0,             ROOM_W, WALL_T), wc)
	draw_rect(Rect2(0,            ROOM_H-WALL_T, ROOM_W, WALL_T), wc)
	draw_rect(Rect2(0,            0,             WALL_T, ROOM_H), wc)
	draw_rect(Rect2(ROOM_W-WALL_T, 0,            WALL_T, ROOM_H), wc)

func _build_walls() -> void:
	_wall(Vector2(0,             0            ), Vector2(ROOM_W, WALL_T))
	_wall(Vector2(0,             ROOM_H-WALL_T), Vector2(ROOM_W, WALL_T))
	_wall(Vector2(0,             0            ), Vector2(WALL_T, ROOM_H))
	_wall(Vector2(ROOM_W-WALL_T, 0            ), Vector2(WALL_T, ROOM_H))

func _wall(pos: Vector2, size: Vector2) -> void:
	var body  := StaticBody2D.new()
	body.position        = pos
	body.collision_layer = 8
	body.collision_mask  = 0

	var col   := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size   = size
	col.shape    = shape
	col.position = size * 0.5
	body.add_child(col)
	add_child(body)
