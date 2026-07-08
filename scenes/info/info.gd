extends Control

func _ready() -> void:
	$VBox/Header/BtnBack.pressed.connect(SceneManager.go_to_menu)
	$VBox/BtnItemList.pressed.connect(func(): SceneManager.go_to("res://scenes/item_list/item_list.tscn"))
