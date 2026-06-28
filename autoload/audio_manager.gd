extends Node

var _player: AudioStreamPlayer

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.stream = load("res://assets/audio/11. Tractor Audit.wav")
	_player.finished.connect(_player.play)
	_player.volume_db = _to_db(SaveManager.music_volume)
	_player.play()

func set_volume(linear: float) -> void:
	_player.volume_db = _to_db(linear)
	SaveManager.music_volume = linear
	SaveManager.save()

func _to_db(linear: float) -> float:
	return linear_to_db(linear) if linear > 0.0 else -80.0
