extends Control

func _ready() -> void:
	$VBox/Buttons/PlayRow/BtnPlay.pressed.connect(SceneManager.go_to_game)
	$VBox/Buttons/PlayRow/BtnTest.pressed.connect(SceneManager.go_to_sandbox)
	$VBox/Buttons/BtnSyncSteps.pressed.connect(func(): SceneManager.go_to("res://scenes/sync_steps/sync_steps.tscn"))
	$VBox/Buttons/BtnOpenCrate.pressed.connect(func(): SceneManager.go_to("res://scenes/open_crate/open_crate.tscn"))
	$VBox/Buttons/BtnInventory.pressed.connect(func(): SceneManager.go_to("res://scenes/inventory/inventory.tscn"))
	$VBox/Buttons/BtnCharacter.pressed.connect(func(): SceneManager.go_to("res://scenes/character/character.tscn"))
	$VBox/Buttons/BtnSettings.pressed.connect(func(): SceneManager.go_to("res://scenes/settings/settings.tscn"))
