extends Node

var _player: AudioStreamPlayer

# ── Boss music (I Got Soda) ─────────────────────────────────────────────────────────────────
# The final-boss fight (world.gd floor 35) swaps the background track for "I Got Soda":
#  • Phase 1: loops the 0:00–4:19 section, fading out to silence right at 4:19 then fading back in
#    from the top, over and over until the 500-HP boss dies.
#  • Phase 2 (after Continue): restarts at 4:20 with NO fade-in, plays to the end (5:38), then loops
#    the FULL song for as long as the fight lasts.
# stop_boss_music() restores the normal background track (on clear or death).
const BG_MUSIC_PATH := "res://assets/audio/11. Tractor Audit.wav"
const SODA_MUSIC_PATH := "res://assets/audio/I_Got_Soda_Instrumental.wav"
const SODA_LOOP_END := 259.0     # 4:19 — phase 1 loops 0..this
const SODA_PHASE2_START := 260.0 # 4:20 — phase 2 begins here
const MUSIC_FADE := 3.0          # fade in/out length (seconds)
enum MusicMode { BG, BOSS_P1, BOSS_P2 }
var _music_mode: int = MusicMode.BG
var _bg_stream: AudioStream
var _soda_stream: AudioStream

# Procedurally synthesized SFX (no audio files needed): crate-open ticks, laser shots (any
# bullet — see GameManager.spawn_bullet/spawn_enemy_bullet), and melee swings. A round-robin
# pool of players lets rapid overlapping sounds (fast-fire guns, quick ticks) coexist without
# cutting each other. SFX volume is separate from music (SaveManager.sfx_volume).
var _tick_stream: AudioStreamWAV
var _laser_stream: AudioStreamWAV
var _swing_stream: AudioStreamWAV
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_idx := 0

# Rapid-fire guns (Assault Rifle ~16 shots/sec) would otherwise stack lasers into a buzz —
# skip a laser if one already played within this window.
const LASER_MIN_INTERVAL := 0.09
var _last_laser_ms := -10000

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_bg_stream = load(BG_MUSIC_PATH)
	_player.stream = _bg_stream
	# When the stream ends it restarts from 0 — background loop, and (in BOSS_P2) the full-song loop.
	_player.finished.connect(_player.play)
	_player.volume_db = _to_db(SaveManager.music_volume)
	_player.play()

	_tick_stream = _build_tick()
	_laser_stream = _build_laser()
	_swing_stream = _build_swing()
	for _i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_players.append(p)

# Final-boss phase 1: fade "I Got Soda" in and loop its 0:00–4:19 section (see class header).
func start_boss_music_phase1() -> void:
	if _soda_stream == null:
		_soda_stream = load(SODA_MUSIC_PATH)
	_music_mode = MusicMode.BOSS_P1
	_player.stream = _soda_stream
	_player.volume_db = _to_db(0.0) # start silent; _process fades it in
	_player.play(0.0)

# Final-boss phase 2 (on Continue): restart at 4:20 with no fade-in, then loop the full song.
func start_boss_music_phase2() -> void:
	if _soda_stream == null:
		_soda_stream = load(SODA_MUSIC_PATH)
	_music_mode = MusicMode.BOSS_P2
	_player.stream = _soda_stream
	_player.volume_db = _to_db(SaveManager.music_volume)
	_player.play(SODA_PHASE2_START)

# Back to the normal background track (boss defeated, player died, or otherwise leaving the fight).
func stop_boss_music() -> void:
	if _music_mode == MusicMode.BG:
		return
	_music_mode = MusicMode.BG
	_player.stream = _bg_stream
	_player.volume_db = _to_db(SaveManager.music_volume)
	_player.play(0.0)

# Drives the phase-1 loop + fades. Phase 2 and background need no per-frame work (the finished→play
# loop and a one-time volume set cover them).
func _process(_delta: float) -> void:
	if _music_mode != MusicMode.BOSS_P1:
		return
	var pos := _player.get_playback_position()
	if pos >= SODA_LOOP_END:
		_player.seek(0.0)
		pos = 0.0
	var f := 1.0
	if pos < MUSIC_FADE:
		f = pos / MUSIC_FADE                              # fade in from the top of each loop
	elif pos > SODA_LOOP_END - MUSIC_FADE:
		f = (SODA_LOOP_END - pos) / MUSIC_FADE            # fade out to silence at 4:19
	_player.volume_db = _to_db(SaveManager.music_volume * clampf(f, 0.0, 1.0))

func set_volume(linear: float) -> void:
	_player.volume_db = _to_db(linear)
	SaveManager.music_volume = linear
	SaveManager.save()

func set_sfx_volume(linear: float) -> void:
	SaveManager.sfx_volume = linear
	SaveManager.save()

func _to_db(linear: float) -> float:
	return linear_to_db(linear) if linear > 0.0 else -80.0

# ── SFX playback ────────────────────────────────────────────────────────────────────────────

func play_tick() -> void:
	_play_sfx(_tick_stream)

func play_laser() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_laser_ms < int(LASER_MIN_INTERVAL * 1000.0):
		return
	_last_laser_ms = now
	_play_sfx(_laser_stream)

func play_swing() -> void:
	_play_sfx(_swing_stream)

func _play_sfx(stream: AudioStream) -> void:
	if stream == null or SaveManager.sfx_volume <= 0.0:
		return
	var p := _sfx_players[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_players.size()
	p.stream = stream
	p.volume_db = _to_db(SaveManager.sfx_volume)
	p.play()

# ── Synthesis ───────────────────────────────────────────────────────────────────────────────

# Soft, deep "tock": a low sine with a rounded decay, plus a small (mostly tamed) noise
# transient for a bit of attack — the wheel-of-fortune tick as each card passes the center.
func _build_tick() -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * 0.038)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 60.0)
		var tone := sin(TAU * 288.0 * t) # slightly lower pitch than before (was 340Hz)
		var click := (randf() * 2.0 - 1.0) * exp(-t * 260.0) * 0.16
		s[i] = (tone * 0.7 + click) * env * 0.5 # slightly louder (was 0.38)
	return _make_wav(s, rate)

# Laser "pew": a downward pitch sweep (phase-accumulated so the sweep is clean) with a slight
# square-wave buzz and a fast decay — the shot for any bullet-firing gun.
func _build_laser() -> AudioStreamWAV:
	var rate := 44100
	var dur := 0.12
	var n := int(rate * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var prog := t / dur
		var freq := lerpf(1400.0, 340.0, prog)
		phase += TAU * freq / rate
		var tone := sin(phase)
		var buzz := signf(sin(phase)) * 0.22
		var env := exp(-t * 24.0)
		s[i] = (tone * 0.7 + buzz) * env * 0.5
	return _make_wav(s, rate)

# Melee swing "whoosh": band-passed noise whose cutoff swells as the swing passes, under a
# quick bell envelope — shorter and airier than the old crate swoosh.
func _build_swing() -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * 0.22)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / n
		var alpha := clampf(0.03 + 0.18 * (1.0 - absf(t - 0.45) * 2.2), 0.03, 0.21)
		prev = prev + alpha * ((randf() * 2.0 - 1.0) - prev)
		var env := pow(sin(PI * t), 1.3)
		s[i] = prev * env * 1.5
	return _make_wav(s, rate)

func _make_wav(samples: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	return wav
