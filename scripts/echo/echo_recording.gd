class_name EchoRecording
extends RefCounted
## An immutable-ish snapshot of the last few seconds of a player's actions.
## Time is normalised so the first frame is t = 0. Frames are stored in parallel packed
## arrays; discrete events (fire / dash / interact) carry their own timestamps.

const ST_IDLE := 0
const ST_RUN := 1
const ST_DASH := 2

var times := PackedFloat32Array()
var positions := PackedVector3Array()
var yaws := PackedFloat32Array()
var aims := PackedVector3Array()
var states := PackedByteArray()
## Each event: {"t": float, "type": "fire"|"dash"|"interact", ...}
##   fire:     "muzzle": Vector3 offset from body position, "dir": Vector3
##   dash:     "dir": Vector3
##   interact: "id": String
var events: Array = []
var duration := 0.0
var owner_id := 0

# Result of the most recent sample() call (avoids per-tick allocations).
var s_pos := Vector3.ZERO
var s_yaw := 0.0
var s_aim := Vector3.FORWARD
var s_state := 0
var _cursor := 0

func frame_count() -> int:
	return times.size()

func is_valid() -> bool:
	return times.size() >= 2 and positions.size() == times.size() and yaws.size() == times.size() \
		and aims.size() == times.size() and states.size() == times.size()

func fire_event_count() -> int:
	var n := 0
	for e in events:
		if e["type"] == "fire":
			n += 1
	return n

## Interpolated pose at playback time t (clamped to the recording). Results land in s_* fields.
## Playback is monotonic, so a cursor makes this O(1) amortised; it also rewinds if t goes back.
func sample(t: float) -> void:
	var n := times.size()
	if n == 0:
		return
	t = clampf(t, 0.0, times[n - 1])
	if _cursor >= n - 1 or times[_cursor] > t:
		_cursor = 0
	while _cursor < n - 2 and times[_cursor + 1] <= t:
		_cursor += 1
	var a := _cursor
	var b := mini(a + 1, n - 1)
	var span := times[b] - times[a]
	var w := 0.0 if span <= 0.00001 else clampf((t - times[a]) / span, 0.0, 1.0)
	s_pos = positions[a].lerp(positions[b], w)
	s_yaw = lerp_angle(yaws[a], yaws[b], w)
	s_aim = aims[a].slerp(aims[b], w) if aims[a].dot(aims[b]) < 0.9999 else aims[a]
	s_state = states[a]

func to_dict() -> Dictionary:
	return {
		"times": times, "positions": positions, "yaws": yaws, "aims": aims,
		"states": states, "events": events.duplicate(true), "duration": duration, "owner": owner_id,
	}

static func from_dict(d: Dictionary) -> EchoRecording:
	var r := EchoRecording.new()
	r.times = d.get("times", PackedFloat32Array())
	r.positions = d.get("positions", PackedVector3Array())
	r.yaws = d.get("yaws", PackedFloat32Array())
	r.aims = d.get("aims", PackedVector3Array())
	r.states = d.get("states", PackedByteArray())
	r.events = (d.get("events", []) as Array).duplicate(true)
	r.duration = float(d.get("duration", 0.0))
	r.owner_id = int(d.get("owner", 0))
	return r
