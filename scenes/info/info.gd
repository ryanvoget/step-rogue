extends Control

func _ready() -> void:
	SceneManager.add_glass_background(self)
	$VBox/Header/BtnBack.pressed.connect(SceneManager.go_to_menu)
	$VBox/BtnItemList.pressed.connect(func(): SceneManager.go_to("res://scenes/item_list/item_list.tscn"))
	$VBox/BtnEnemyInfo.pressed.connect(func(): SceneManager.go_to("res://scenes/enemy_info/enemy_info.tscn"))
	$VBox/BtnStatistics.pressed.connect(func(): SceneManager.go_to("res://scenes/statistics/statistics.tscn"))
