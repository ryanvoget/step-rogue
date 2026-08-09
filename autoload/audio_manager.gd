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
const SODA_PHASE2_START := 260.5 # 4:20.5 — phase 2 begins here
const MUSIC_FADE := 3.0          # fade in/out length (seconds)
enum MusicMode { BG, BOSS_P1, BOSS_P2 }
var _music_mode: int = MusicMode.BG
var _bg_stream: AudioStream
var _soda_stream: AudioStream

# ── Layered "Hatches" game music ────────────────────────────────────────────────────────────
# Adaptive stems (all the same 46.5s length, so they stay sample-synced): they ALL play in parallel
# from the same start and loop together (via the hook's `finished`); which ones are AUDIBLE is set
# by volume. This makes new layers snap in perfectly in sync — a layer added at 0:20 is already
# playing at 0:20, just silent. Floor tiers are cumulative: hook always, +strings at 5, +synths at
# 10, +drums at 15; the lowHP stem layers on whenever HP < 25% (see world.gd). Only active during a
# run (world.gd), and muted while the final-boss "I Got Soda" track plays.
const HATCH_PATHS := {
	"hook":    "res://Music/hook_Hatches.wav",
	"strings": "res://Music/strings_Hatches.wav",
	"synths":  "res://Music/synths_Hatches.wav",
	"drums":   "res://Music/drums_Hatches.wav",
	"lowhp":   "res://Music/lowHP_Hatches.wav",
}
var _hatch_players := {}          # layer name -> AudioStreamPlayer
var _hatch_tweens := {}           # layer name -> active volume-fade Tween
var _hatch_on := false            # the hatch stack is the current music (a run, non-boss)
var _hatch_floor := 0
var _hatch_low_hp := false
const HATCH_FADE := 1.4           # seconds to fade a layer in/out so it never snaps on abruptly

# Procedurally synthesized SFX (no audio files needed): crate-open ticks, laser shots (any
# bullet — see GameManager.spawn_bullet/spawn_enemy_bullet), and melee swings. A round-robin
# pool of players lets rapid overlapping sounds (fast-fire guns, quick ticks) coexist without
# cutting each other. SFX volume is separate from music (SaveManager.sfx_volume).
var _tick_stream: AudioStreamWAV
var _laser_stream: AudioStreamWAV
var _swing_stream: AudioStreamWAV
var _impact_stream: AudioStreamWAV
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

	# Layered hatch music players — created up front, silent until start_hatch_music.
	for name in HATCH_PATHS:
		var hp := AudioStreamPlayer.new()
		hp.stream = load(HATCH_PATHS[name])
		hp.volume_db = -80.0
		add_child(hp)
		_hatch_players[name] = hp
	# All layers loop together off the hook's end, so they never drift out of sync.
	_hatch_players["hook"].finished.connect(_on_hatch_loop)

	_tick_stream = _build_tick()
	_laser_stream = _build_laser()
	_swing_stream = _build_swing()
	_impact_stream = _build_impact()
	for _i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_players.append(p)

# Final-boss phase 1: fade "I Got Soda" in and loop its 0:00–4:19 section (see class header).
func start_boss_music_phase1() -> void:
	if _soda_stream == null:
		_soda_stream = load(SODA_MUSIC_PATH)
	_music_mode = MusicMode.BOSS_P1
	_update_hatch_volumes() # mute the hatch stack while the boss track plays
	_player.stream = _soda_stream
	_player.volume_db = _to_db(0.0) # start silent; _process fades it in
	_player.play(0.0)

# Final-boss phase 2 (on Continue): restart at 4:20 with no fade-in, then loop the full song.
func start_boss_music_phase2() -> void:
	if _soda_stream == null:
		_soda_stream = load(SODA_MUSIC_PATH)
	_music_mode = MusicMode.BOSS_P2
	_update_hatch_volumes() # mute the hatch stack while the boss track plays
	_player.stream = _soda_stream
	_player.volume_db = _to_db(SaveManager.music_volume)
	_player.play(SODA_PHASE2_START)

# Back to the normal music (boss defeated, player died, or otherwise leaving the fight): resume the
# hatch stack if a run is still going, else the plain background track.
func stop_boss_music() -> void:
	if _music_mode == MusicMode.BG:
		return
	_music_mode = MusicMode.BG
	if _hatch_on:
		_player.stop() # game music is the hatch stack
		_update_hatch_volumes()
	else:
		_player.stream = _bg_stream
		_player.volume_db = _to_db(SaveManager.music_volume)
		_player.play(0.0)

# ── Hatch (layered game) music ──────────────────────────────────────────────────────────────

# Begin the layered game music for a run: silence the menu track, (re)start all stems in sync from
# the top, and set which layers are audible for this floor.
func start_hatch_music(floor: int) -> void:
	_hatch_on = true
	_hatch_floor = floor
	_hatch_low_hp = false
	_music_mode = MusicMode.BG
	_player.stop()
	for name in _hatch_players:
		_hatch_players[name].play(0.0)
	_update_hatch_volumes()

# End the layered game music (leaving the run) and restore the plain background track.
func stop_hatch_music() -> void:
	_hatch_on = false
	_music_mode = MusicMode.BG
	for name in _hatch_players:
		_hatch_players[name].stop()
	_player.stream = _bg_stream
	_player.volume_db = _to_db(SaveManager.music_volume)
	if not _player.playing:
		_player.play(0.0)

func set_hatch_floor(floor: int) -> void:
	_hatch_floor = floor
	_update_hatch_volumes()

func set_hatch_low_hp(active: bool) -> void:
	if active == _hatch_low_hp:
		return
	_hatch_low_hp = active
	_update_hatch_volumes()

# Loop all stems together the instant the base (hook) ends, so they never drift.
func _on_hatch_loop() -> void:
	if not _hatch_on:
		return
	for name in _hatch_players:
		_hatch_players[name].play(0.0)
	_update_hatch_volumes()

# Sets each layer's volume from the current floor/HP state. Everything is muted while a boss track
# is playing (mode != BG) or the hatch music isn't the active track.
func _update_hatch_volumes() -> void:
	var audible := _hatch_on and _music_mode == MusicMode.BG
	var base := SaveManager.music_volume
	_set_hatch_layer("hook",    audible)                          # base — always on when active
	_set_hatch_layer("strings", audible and _hatch_floor >= 5)
	_set_hatch_layer("synths",  audible and _hatch_floor >= 10)
	_set_hatch_layer("drums",   audible and _hatch_floor >= 15)
	_set_hatch_layer("lowhp",   audible and _hatch_low_hp)

# Fades a layer toward its target volume (in LINEAR loudness, so the ramp sounds smooth) instead of
# snapping — so a stem eases in when it activates and eases out when it drops.
func _set_hatch_layer(name: String, on: bool) -> void:
	if not _hatch_players.has(name):
		return
	var p: AudioStreamPlayer = _hatch_players[name]
	var to_lin: float = SaveManager.music_volume if on else 0.0
	var from_lin: float = db_to_linear(p.volume_db)
	if is_equal_approx(from_lin, to_lin):
		return
	if _hatch_tweens.has(name) and _hatch_tweens[name] != null and _hatch_tweens[name].is_valid():
		_hatch_tweens[name].kill()
	var tw := create_tween()
	tw.tween_method(func(v: float): p.volume_db = _to_db(v), from_lin, to_lin, HATCH_FADE)
	_hatch_tweens[name] = tw

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
	SaveManager.music_volume = linear
	if _music_mode != MusicMode.BOSS_P1: # BOSS_P1 volume is driven by the fade in _process
		_player.volume_db = _to_db(linear)
	_update_hatch_volumes()
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

func play_impact() -> void:
	_play_sfx(_impact_stream)

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

# Melee-impact "thunk": a deep, sharp hit — a low sine thump (with a fast downward pitch drop) plus
# a brief noise crack transient, both under a fast decay. Played the frame a melee strike connects.
func _build_impact() -> AudioStreamWAV:
	var rate := 44100
	var dur := 0.16
	var n := int(rate * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var prog := t / dur
		var freq := lerpf(190.0, 70.0, clampf(prog * 2.0, 0.0, 1.0)) # deep pitch drop
		phase += TAU * freq / rate
		var thump := sin(phase)
		var crack := (randf() * 2.0 - 1.0) * exp(-t * 90.0) * 0.5 # sharp attack transient
		var env := exp(-t * 22.0)
		s[i] = clampf((thump * 0.85 + crack) * env, -1.0, 1.0) * 0.6
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
