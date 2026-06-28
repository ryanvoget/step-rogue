extends Control

func _ready() -> void:
	$VBox/Header/BtnBack.pressed.connect(SceneManager.go_to_menu)

	var slider: HSlider = $VBox/SliderRow/VolumeSlider
	var label: Label   = $VBox/SliderRow/VolumeLabel

	slider.value = SaveManager.music_volume
	label.text   = str(int(SaveManager.music_volume * 100)) + "%"

	slider.value_changed.connect(func(val: float) -> void:
		label.text = str(int(val * 100)) + "%"
		AudioManager.set_volume(val)
	)
