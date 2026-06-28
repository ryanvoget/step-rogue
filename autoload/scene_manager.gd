extends Node

func go_to(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func go_to_menu() -> void:
	go_to("res://scenes/menu/menu.tscn")

func go_to_game() -> void:
	go_to("res://scenes/world/world.tscn")

func go_to_sandbox() -> void:
	go_to("res://scenes/sandbox/sandbox.tscn")
