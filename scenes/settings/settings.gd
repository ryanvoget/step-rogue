extends Control

func _ready() -> void:
	SceneManager.add_glass_background(self)
	$VBox/Header/BtnBack.pressed.connect(SceneManager.go_to_menu)

	var slider: HSlider = $VBox/SliderRow/VolumeSlider
	var label: Label   = $VBox/SliderRow/VolumeLabel

	slider.value = SaveManager.music_volume
	label.text   = str(int(SaveManager.music_volume * 100)) + "%"

	slider.value_changed.connect(func(val: float) -> void:
		label.text = str(int(val * 100)) + "%"
		AudioManager.set_volume(val)
	)

	var sfx_slider: HSlider = $VBox/SfxRow/SfxSlider
	var sfx_label: Label   = $VBox/SfxRow/SfxLabel
	sfx_slider.value = SaveManager.sfx_volume
	sfx_label.text   = str(int(SaveManager.sfx_volume * 100)) + "%"
	sfx_slider.value_changed.connect(func(val: float) -> void:
		sfx_label.text = str(int(val * 100)) + "%"
		AudioManager.set_sfx_volume(val)
		AudioManager.play_laser() # audible preview of the new SFX level
	)
