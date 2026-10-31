extends Node
## Audio manager. Every sound effect and music loop is synthesised procedurally at start-up
## (no external audio files), so a missing asset can never crash the game.
## API: play(), play_at(), play_music(), stop_music(), set_ambient().

const RATE := 22050
const POOL_2D := 10
const POOL_3D := 20

var _rng := RandomNumberGenerator.new()
var _streams: Dictionary = {}
var _music: Dictionary = {}
var _last_played: Dictionary = {}
var _pool2d: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _music_player: AudioStreamPlayer
var _ambient_player: AudioStreamPlayer
var _music_thread: Thread
var _music_ready := false
var _music_pending := ""
var _music_current := ""
var _music_tween: Tween

## Minimum seconds between two plays of the same sound (stops per-frame spam).
const MIN_INTERVAL := {
	"shot": 0.035, "echo_shot": 0.035, "enemy_shot": 0.04, "hit": 0.04, "enemy_hit": 0.04,
	"step": 0.12, "zap": 0.08, "warn": 0.15, "ui_hover": 0.05, "frag": 0.04,
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool2d.append(p)
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.unit_size = 9.0
		p3.max_distance = 70.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_pool3d.append(p3)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = "SFX"
	_ambient_player.volume_db = -22.0
	add_child(_ambient_player)
	_build_sfx()
	_music_thread = Thread.new()
	_music_thread.start(_build_music_thread)

func _exit_tree() -> void:
	if _music_thread and _music_thread.is_started():
		_music_thread.wait_to_finish()

func _process(_delta: float) -> void:
	if not _music_ready and _music_thread and _music_thread.is_started() and not _music_thread.is_alive():
		_music_thread.wait_to_finish()
		_music_ready = true
		if _music_pending != "":
			var t := _music_pending
			_music_pending = ""
			play_music(t)

# --- Public API -------------------------------------------------------------------------------

func has_sound(sound_name: String) -> bool:
	return _streams.has(sound_name)

func _throttled(sound_name: String) -> bool:
	var now := Time.get_ticks_msec()
	var gap := int(float(MIN_INTERVAL.get(sound_name, 0.02)) * 1000.0)
	if now - int(_last_played.get(sound_name, -100000)) < gap:
		return true
	_last_played[sound_name] = now
	return false

func play(sound_name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(sound_name) or _throttled(sound_name):
		return
	var p := _free_player2d()
	p.stream = _streams[sound_name]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()

func play_at(sound_name: String, pos: Vector3, vol_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(sound_name) or _throttled(sound_name):
		return
	var p := _free_player3d()
	p.stream = _streams[sound_name]
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()

func _free_player2d() -> AudioStreamPlayer:
	for p in _pool2d:
		if not p.playing:
			return p
	return _pool2d[0]

func _free_player3d() -> AudioStreamPlayer3D:
	for p in _pool3d:
		if not p.playing:
			return p
	return _pool3d[0]

func play_music(track: String, fade := 0.8) -> void:
	if track == _music_current and _music_player.playing:
		return
	if not _music_ready:
		_music_pending = track
		return
	if not _music.has(track):
		return
	_music_current = track
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	if _music_player.playing:
		_music_tween.tween_property(_music_player, "volume_db", -40.0, fade * 0.5)
	_music_tween.tween_callback(func() -> void:
		_music_player.stream = _music[track]
		_music_player.volume_db = -40.0
		_music_player.play())
	_music_tween.tween_property(_music_player, "volume_db", -6.0, fade)

func stop_music(fade := 0.8) -> void:
	_music_current = ""
	_music_pending = ""
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", -50.0, fade)
	_music_tween.tween_callback(_music_player.stop)

func set_ambient(kind: String, pitch := 1.0) -> void:
	if kind == "" or not _streams.has(kind):
		_ambient_player.stop()
		return
	if _ambient_player.stream != _streams[kind]:
		_ambient_player.stream = _streams[kind]
	_ambient_player.pitch_scale = pitch
	if not _ambient_player.playing:
		_ambient_player.play()

# --- Synthesis helpers -------------------------------------------------------------------------

func _make(dur: float, fn: Callable, loop := false) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var s: float = clampf(float(fn.call(t, dur)), -1.0, 1.0)
		bytes.encode_s16(i * 2, int(s * 31000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w

## Phase (radians) of an exponential frequency sweep f0 -> f1 over d seconds.
func _sw(t: float, d: float, f0: float, f1: float) -> float:
	var k := log(f1 / f0)
	if absf(k) < 0.0001:
		return TAU * f0 * t
	return TAU * f0 * d / k * (exp(k * t / d) - 1.0)

func _env(t: float, d: float, attack: float, decay_pow: float) -> float:
	return minf(t / maxf(attack, 0.0001), 1.0) * pow(maxf(1.0 - t / d, 0.0), decay_pow)

func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)

# --- Sound effect definitions -------------------------------------------------------------------

func _build_sfx() -> void:
	_streams["shot"] = _make(0.20, func(t: float, d: float) -> float:
		var e := _env(t, d, 0.002, 2.2)
		return e * (0.55 * sin(_sw(t, d, 2300.0, 480.0)) + 0.22 * signf(sin(_sw(t, d, 1150.0, 240.0))) + 0.12 * _noise()))
	_streams["echo_shot"] = _make(0.24, func(t: float, d: float) -> float:
		var e := _env(t, d, 0.004, 2.0)
		return e * (0.5 * sin(_sw(t, d, 1500.0, 520.0) + 2.0 * sin(t * 50.0)) + 0.25 * sin(_sw(t, d, 2250.0, 780.0))))
	_streams["enemy_shot"] = _make(0.22, func(t: float, d: float) -> float:
		var e := _env(t, d, 0.003, 1.8)
		var ph := _sw(t, d, 900.0, 220.0)
		return e * (0.4 * (fmod(ph / TAU, 1.0) * 2.0 - 1.0) + 0.3 * sin(ph * 0.5) + 0.1 * _noise()))
	_streams["hit"] = _make(0.14, func(t: float, d: float) -> float:
		return _env(t, d, 0.001, 3.0) * (0.6 * _noise() + 0.5 * sin(TAU * 140.0 * t)))
	_streams["enemy_hit"] = _make(0.32, func(t: float, d: float) -> float:
		var e := _env(t, d, 0.001, 3.5)
		return e * (0.35 * sin(TAU * 470.0 * t) + 0.25 * sin(TAU * 1130.0 * t) + 0.2 * sin(TAU * 1880.0 * t) + 0.18 * _noise()))
	_streams["armor_hit"] = _make(0.35, func(t: float, d: float) -> float:
		var e := _env(t, d, 0.001, 3.0)
		return e * (0.4 * sin(TAU * 260.0 * t) + 0.3 * sin(TAU * 610.0 * t) + 0.25 * sin(TAU * 1420.0 * t) + 0.15 * _noise()))
	var lp_state := [0.0]
	_streams["explosion"] = _make(0.8, func(t: float, d: float) -> float:
		lp_state[0] += (_noise() - lp_state[0]) * lerpf(0.5, 0.05, t / d)
		return _env(t, d, 0.004, 2.2) * (1.6 * lp_state[0] + 0.5 * sin(_sw(t, d, 120.0, 38.0))))
	var lp2 := [0.0]
	_streams["dash"] = _make(0.28, func(t: float, d: float) -> float:
		lp2[0] += (_noise() - lp2[0]) * lerpf(0.08, 0.5, t / d)
		var e := sin(PI * t / d)
		return e * e * 1.4 * lp2[0])
	_streams["echo_create"] = _make(0.75, func(t: float, d: float) -> float:
		var e := _env(t, d, 0.01, 1.4)
		var s := 0.0
		for k in 4:
			var ts := t - 0.07 * k
			if ts > 0.0:
				s += sin(TAU * 440.0 * pow(2.0, float(k) * 0.5) * ts) * exp(-ts * 5.0) * 0.35
		return e * (s + 0.25 * sin(_sw(t, d, 300.0, 1700.0))))
	_streams["echo_expire"] = _make(0.45, func(t: float, d: float) -> float:
		var e := _env(t, d, 0.003, 1.6)
		return e * (0.45 * sin(_sw(t, d, 1400.0, 180.0)) + 0.25 * signf(sin(TAU * 60.0 * t)) * sin(_sw(t, d, 700.0, 120.0))))
	_streams["echo_replace"] = _make(0.4, func(t: float, d: float) -> float:
		var e := 1.0 if fmod(t, 0.2) < 0.12 else 0.0
		return 0.35 * e * sin(TAU * 660.0 * t) * (1.0 - t / d))
	_streams["echo_fail"] = _make(0.25, func(t: float, d: float) -> float:
		return _env(t, d, 0.002, 1.2) * 0.4 * signf(sin(TAU * 150.0 * t)))
	var lp3 := [0.0]
	_streams["door"] = _make(0.7, func(t: float, d: float) -> float:
		lp3[0] += (_noise() - lp3[0]) * 0.12
		var e := sin(PI * minf(t / d, 1.0))
		return e * (0.5 * lp3[0] + 0.45 * sin(_sw(t, d, 70.0, 160.0)) + 0.12 * signf(sin(TAU * 38.0 * t))))
	_streams["door_close"] = _make(0.6, func(t: float, d: float) -> float:
		lp3[0] += (_noise() - lp3[0]) * 0.15
		var e := sin(PI * minf(t / d, 1.0)) * (1.0 - 0.3 * t / d)
		return e * (0.5 * lp3[0] + 0.45 * sin(_sw(t, d, 160.0, 60.0))) + (0.6 * _env(t, d, 0.001, 8.0) * sin(TAU * 52.0 * t)) * (1.0 if t > d * 0.8 else 0.0))
	_streams["switch"] = _make(0.3, func(t: float, d: float) -> float:
		var s := _env(t, d, 0.001, 9.0) * sin(TAU * 1800.0 * t) * 0.5
		if t > 0.07:
			s += _env(t - 0.07, d - 0.07, 0.001, 6.0) * sin(TAU * 1200.0 * (t - 0.07)) * 0.5
		return s)
	_streams["plate_on"] = _make(0.35, func(t: float, d: float) -> float:
		return _env(t, d, 0.002, 2.5) * (0.5 * sin(TAU * 90.0 * t) + 0.35 * sin(_sw(t, d, 400.0, 1100.0))))
	_streams["plate_off"] = _make(0.3, func(t: float, d: float) -> float:
		return _env(t, d, 0.002, 2.5) * (0.4 * sin(TAU * 80.0 * t) + 0.25 * sin(_sw(t, d, 900.0, 300.0))))
	_streams["pickup"] = _make(0.35, func(t: float, d: float) -> float:
		var f := 880.0 if t < 0.1 else 1320.0
		return _env(t, d, 0.003, 2.0) * 0.45 * sin(TAU * f * t))
	_streams["frag"] = _make(0.14, func(t: float, d: float) -> float:
		return _env(t, d, 0.002, 2.5) * 0.4 * sin(TAU * 1500.0 * t) * (1.0 + 0.5 * sin(TAU * 40.0 * t)))
	_streams["health"] = _make(0.5, func(t: float, d: float) -> float:
		var f := 520.0 * pow(2.0, floorf(t * 6.0) / 6.0)
		return _env(t, d, 0.005, 1.3) * 0.4 * sin(TAU * f * t))
	_streams["ui_click"] = _make(0.07, func(t: float, d: float) -> float:
		return _env(t, d, 0.001, 2.0) * 0.5 * sin(TAU * 1000.0 * t))
	_streams["ui_hover"] = _make(0.04, func(t: float, d: float) -> float:
		return _env(t, d, 0.001, 2.0) * 0.25 * sin(TAU * 1500.0 * t))
	_streams["ui_back"] = _make(0.1, func(t: float, d: float) -> float:
		return _env(t, d, 0.001, 2.0) * 0.45 * sin(_sw(t, d, 900.0, 400.0)))
	_streams["alarm"] = _make(1.0, func(t: float, d: float) -> float:
		var f := 700.0 if fmod(t, 0.5) < 0.25 else 520.0
		return 0.32 * signf(sin(TAU * f * t)) * (1.0 - t / d))
	_streams["warn"] = _make(0.22, func(t: float, d: float) -> float:
		return _env(t, d, 0.002, 1.0) * 0.4 * sin(_sw(t, d, 500.0, 1400.0)))
	_streams["charge"] = _make(1.0, func(t: float, d: float) -> float:
		return (t / d) * 0.35 * (sin(_sw(t, d, 200.0, 1800.0)) + 0.4 * signf(sin(_sw(t, d, 100.0, 900.0)))))
	_streams["boss_phase"] = _make(2.0, func(t: float, d: float) -> float:
		var e := _env(t, d, 0.01, 1.2)
		return e * (0.7 * sin(_sw(t, d, 90.0, 28.0)) + 0.3 * sin(_sw(t, d, 800.0, 60.0)) + 0.25 * _noise() * exp(-t * 3.0)))
	_streams["boss_hit"] = _make(0.4, func(t: float, d: float) -> float:
		return _env(t, d, 0.001, 2.5) * (0.5 * sin(_sw(t, d, 300.0, 60.0)) + 0.35 * _noise() * exp(-t * 12.0)))
	_streams["shield_down"] = _make(0.9, func(t: float, d: float) -> float:
		return _env(t, d, 0.003, 1.5) * (0.5 * sin(_sw(t, d, 1800.0, 90.0)) + 0.3 * _noise() * exp(-t * 6.0)))
	_streams["step"] = _make(0.09, func(t: float, d: float) -> float:
		return _env(t, d, 0.001, 3.0) * (0.35 * _noise() * (1.0 - t / d) + 0.5 * sin(TAU * 95.0 * t)))
	_streams["hurt"] = _make(0.3, func(t: float, d: float) -> float:
		return _env(t, d, 0.002, 2.0) * (0.45 * signf(sin(_sw(t, d, 260.0, 110.0))) + 0.25 * _noise()))
	_streams["death"] = _make(1.1, func(t: float, d: float) -> float:
		return _env(t, d, 0.005, 1.3) * (0.5 * sin(_sw(t, d, 400.0, 40.0)) + 0.25 * _noise() * exp(-t * 4.0)))
	_streams["terminal"] = _make(0.4, func(t: float, d: float) -> float:
		var f := 900.0 + 300.0 * floorf(fmod(t * 25.0, 4.0))
		return _env(t, d, 0.002, 1.0) * 0.3 * sin(TAU * f * t))
	_streams["checkpoint"] = _make(0.9, func(t: float, d: float) -> float:
		var s := 0.0
		for k in 3:
			var ts := t - 0.12 * k
			if ts > 0.0:
				s += sin(TAU * 523.25 * pow(1.2599, float(k)) * ts) * exp(-ts * 3.0) * 0.4
		return s)
	_streams["heat_warn"] = _make(0.2, func(t: float, d: float) -> float:
		return _env(t, d, 0.002, 1.0) * 0.3 * signf(sin(TAU * 220.0 * t)))
	_streams["overheat"] = _make(0.6, func(t: float, d: float) -> float:
		return _env(t, d, 0.004, 1.5) * (0.35 * _noise() + 0.4 * sin(_sw(t, d, 200.0, 50.0))))
	var lp4 := [0.0]
	_streams["zap"] = _make(0.3, func(t: float, d: float) -> float:
		lp4[0] += (_noise() - lp4[0]) * 0.6
		return _env(t, d, 0.001, 1.5) * (0.7 * lp4[0] * signf(sin(TAU * 90.0 * t)) + 0.2 * sin(TAU * 1300.0 * t)))
	_streams["ending_shutdown"] = _make(4.0, func(t: float, d: float) -> float:
		return _env(t, d, 0.2, 1.0) * (0.4 * sin(_sw(t, d, 440.0, 55.0)) + 0.25 * sin(_sw(t, d, 880.0, 110.0))))
	_streams["ending_containment"] = _make(4.0, func(t: float, d: float) -> float:
		var e := sin(PI * t / d)
		return e * (0.3 * sin(TAU * 220.0 * t) + 0.25 * sin(TAU * 330.0 * t) + 0.2 * sin(TAU * 440.0 * t + sin(t * 3.0))))
	_streams["ending_reactivation"] = _make(4.0, func(t: float, d: float) -> float:
		var e := _env(t, d, 0.4, 0.6)
		return e * (0.3 * sin(_sw(t, d, 110.0, 880.0)) + 0.25 * sin(_sw(t, d, 165.0, 1320.0)) + 0.1 * _noise() * (t / d)))
	_build_ambient()

func _build_ambient() -> void:
	# A single 12 s loop: low machinery hum with sparse metallic pings. All tones complete whole
	# cycles per loop (frequencies are multiples of 1/12 Hz) so the loop is click-free.
	var d := 12.0
	var lp := [0.0]
	var fn := func(t: float, dur: float) -> float:
		lp[0] += (_noise() - lp[0]) * 0.02
		var s: float = 0.22 * sin(TAU * 55.0 * t) + 0.12 * sin(TAU * 110.0 * t + sin(TAU * t / dur)) + 0.6 * float(lp[0])
		s += 0.06 * sin(TAU * 164.0 * t) * (0.5 + 0.5 * sin(TAU * 2.0 * t / dur))
		for p in [1.5, 5.0, 8.75]:
			var tp := t - float(p)
			if tp > 0.0:
				s += 0.05 * sin(TAU * 1320.0 * tp) * exp(-tp * 4.0)
		return s * 0.8
	_streams["ambient"] = _make(d, fn, true)

# --- Music (generated on a worker thread) -------------------------------------------------------------

func _build_music_thread() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1189
	_music["menu"] = _compose(rng, 72.0, [[57, 0], [53, 0], [60, 0], [55, 0]], 0.5, false, false, 0.7)
	_music["explore"] = _compose(rng, 84.0, [[57, 0], [53, 0], [48, 0], [55, 0]], 0.55, true, false, 0.9)
	_music["combat"] = _compose(rng, 132.0, [[57, 0], [53, 0], [48, 0], [52, 0]], 0.5, true, true, 1.2)
	_music["boss"] = _compose(rng, 144.0, [[45, 0], [41, 0], [43, 0], [40, 0]], 0.55, true, true, 1.5)
	_music["ending"] = _compose(rng, 60.0, [[60, 0], [57, 0], [53, 0], [55, 0]], 0.7, false, false, 0.5)

func _midi_hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)

## Builds a looping track: chord pad + optional pulse bass/arp/hats. 16 beats long.
func _compose(rng: RandomNumberGenerator, bpm: float, chords: Array, pad_gain: float, bass: bool, drive: bool, arp_gain: float) -> AudioStreamWAV:
	var beat := 60.0 / bpm
	var loop_len := beat * 16.0
	var n := int(loop_len * RATE)
	var loop_hz := 1.0 / loop_len
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var scale := [0, 3, 5, 7, 10, 12, 15, 17]   # A minor pentatonic-ish (relative to chord root)
	var arp_pattern: Array = []
	for i in 16:
		arp_pattern.append(scale[rng.randi_range(0, scale.size() - 1)])
	var lpn := 0.0
	for i in n:
		var t := float(i) / RATE
		var bar := int(t / (beat * 4.0)) % 4
		var root: float = float(chords[bar][0])
		var s := 0.0
		# pad: root, minor third, fifth - slightly detuned pairs
		for off in [0.0, 3.0, 7.0, 12.0]:
			var f := _snap(_midi_hz(root + float(off) - 12.0), loop_hz)
			s += 0.1 * pad_gain * (sin(TAU * f * t) + 0.6 * sin(TAU * _snap(f * 1.003, loop_hz) * t))
		var bar_t := fmod(t, beat * 4.0) / (beat * 4.0)
		s *= 0.5 + 0.5 * sin(PI * bar_t)
		if bass:
			var bt := fmod(t, beat * 0.5)
			var f_b := _snap(_midi_hz(root - 24.0), loop_hz)
			var gate := 1.0 if (drive or int(t / (beat * 0.5)) % 2 == 0) else 0.0
			s += 0.28 * gate * exp(-bt * 9.0) * sin(TAU * f_b * t)
			s += 0.08 * gate * exp(-bt * 14.0) * signf(sin(TAU * f_b * 2.0 * t))
		# arpeggio on 16ths
		var step := int(t / (beat * 0.25))
		if arp_gain > 0.0 and (drive or step % 2 == 0):
			var at := fmod(t, beat * 0.25)
			var nf := _snap(_midi_hz(root + float(arp_pattern[step % 16]) + 12.0), loop_hz)
			s += 0.07 * arp_gain * exp(-at * 18.0) * sin(TAU * nf * t)
		if drive:
			var ht := fmod(t, beat * 0.5)
			lpn += (rng.randf_range(-1.0, 1.0) - lpn) * 0.7
			s += 0.04 * exp(-ht * 40.0) * (rng.randf_range(-1.0, 1.0) - lpn)
			var kt := fmod(t, beat)
			s += 0.3 * exp(-kt * 14.0) * sin(_sw(kt, 0.3, 120.0, 45.0))
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w

func _snap(f: float, loop_hz: float) -> float:
	return roundf(f / loop_hz) * loop_hz
