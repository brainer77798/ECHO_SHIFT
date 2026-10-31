class_name EchoRecorder
extends Node
## Continuously records a player's recent actions into a fixed-size ring buffer.
## The buffer never grows: capacity is allocated once for the maximum (upgraded) window.
## One recorder exists per player, so in multiplayer every player has an independent buffer.

var window := Cfg.ECHO_RECORD_TIME          # seconds of history an Echo will capture
var capacity := 0
var _times := PackedFloat32Array()
var _pos := PackedVector3Array()
var _yaw := PackedFloat32Array()
var _aim := PackedVector3Array()
var _state := PackedByteArray()
var _head := 0       # next write slot
var _count := 0
var clock := 0.0     # seconds of recorded time (advances only while recording)
var events: Array = []

func _init() -> void:
	capacity = int(Cfg.ECHO_BUFFER_CAPACITY_TIME * float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))) + 4
	_times.resize(capacity)
	_pos.resize(capacity)
	_yaw.resize(capacity)
	_aim.resize(capacity)
	_state.resize(capacity)

## Per-tick protocol: begin_tick(delta) -> log_fire/log_dash/log_interact (any number) -> commit_frame(...).
## Events and the frame that results from them therefore share one timestamp.
func begin_tick(delta: float) -> void:
	clock += delta

## Convenience: begin_tick + commit_frame (no events logged in between).
func record_frame(delta: float, pos: Vector3, yaw: float, aim: Vector3, state: int) -> void:
	begin_tick(delta)
	commit_frame(pos, yaw, aim, state)

func commit_frame(pos: Vector3, yaw: float, aim: Vector3, state: int) -> void:
	_times[_head] = clock
	_pos[_head] = pos
	_yaw[_head] = yaw
	_aim[_head] = aim
	_state[_head] = state
	_head = (_head + 1) % capacity
	_count = mini(_count + 1, capacity)
	# trim events that have fallen out of the largest possible window
	var oldest := clock - Cfg.ECHO_BUFFER_CAPACITY_TIME
	while events.size() > 0 and float(events[0]["t"]) < oldest:
		events.pop_front()

func log_fire(muzzle_offset: Vector3, dir: Vector3) -> void:
	events.append({"t": clock, "type": "fire", "muzzle": muzzle_offset, "dir": dir})

func log_dash(dir: Vector3) -> void:
	events.append({"t": clock, "type": "dash", "dir": dir})

func log_interact(id: String) -> void:
	events.append({"t": clock, "type": "interact", "id": id})

## Seconds of history currently available (capped at the current window).
func available_time() -> float:
	if _count < 2:
		return 0.0
	var newest := _slot(_count - 1)
	var oldest := _slot(0)
	return minf(_times[newest] - _times[oldest], window)

func fill_ratio() -> float:
	return clampf(available_time() / window, 0.0, 1.0)

func can_snapshot() -> bool:
	return available_time() >= Cfg.ECHO_MIN_RECORD

## Builds an EchoRecording from the last `window` seconds, or null if too little data.
func snapshot(owner_id := 0) -> EchoRecording:
	if not can_snapshot():
		return null
	var newest := _slot(_count - 1)
	var t_end := _times[newest]
	var t_start := t_end - window
	# find the first frame inside the window
	var first := 0
	while first < _count - 1 and _times[_slot(first)] < t_start - 0.0001:
		first += 1
	var n := _count - first
	var rec := EchoRecording.new()
	rec.owner_id = owner_id
	rec.times.resize(n)
	rec.positions.resize(n)
	rec.yaws.resize(n)
	rec.aims.resize(n)
	rec.states.resize(n)
	var t0 := _times[_slot(first)]
	for i in n:
		var s := _slot(first + i)
		rec.times[i] = _times[s] - t0
		rec.positions[i] = _pos[s]
		rec.yaws[i] = _yaw[s]
		rec.aims[i] = _aim[s]
		rec.states[i] = _state[s]
	rec.duration = rec.times[n - 1]
	for e in events:
		var et := float(e["t"])
		if et >= t0 - 0.0001 and et <= t_end + 0.0001:
			var c: Dictionary = (e as Dictionary).duplicate()
			c["t"] = maxf(et - t0, 0.0)
			rec.events.append(c)
	return rec

func clear() -> void:
	_head = 0
	_count = 0
	events.clear()

func set_window(seconds: float) -> void:
	window = clampf(seconds, 1.5, Cfg.ECHO_BUFFER_CAPACITY_TIME - 0.5)

## Physical ring slot of the logical index i (0 = oldest stored frame).
func _slot(i: int) -> int:
	return (_head - _count + i + capacity * 2) % capacity
