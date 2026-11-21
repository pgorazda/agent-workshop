extends RefCounted
## One penguin, or one helper: the event queue and the behaviour.
##
## The actor is an explicit state machine. It has a queue of events and a list of motion
## segments, and a step of the simulation clock moves them on. It uses no `await` and no generator, so a test can
## step it frame by frame. It does not draw: it exposes `position`, `facing` and `pose`, with the small values that
## the picture needs (see the variables below). Numbers of time and speed come from the JavaScript mockup.
##
## The story, event by event (see docs/event-schema.md for the categories):
##   tool_start         walks to the station of its `category` and takes the pose there, until `tool_end`
##   tool_end ok:false  the penguin flops (1.8 s)
##   waiting_permission goes to the sign post and waits there. The next event ends the wait
##   done               walks to the stage and celebrates
##   thinking           goes to the armchair when it is free, and otherwise thinks where it stands
##   error              flops where it stands
##   any other type     generic work at the odd-jobs station
## A queue makes the penguin hurry: its local time runs faster (see `hurry()`).
##
## A segment is a Dictionary with "kind", "dur" (INF for a segment that waits for an event) and "age", and the data of its
## kind. The kinds: hidden, pop, idle, walk, hop, work, queue, think, sit, approve, flop, cheer, wave, vanish, gone.

const Event := preload("res://src/core/event.gd")
const Stations := preload("res://src/core/stations.gd")
const Data := preload("res://art/atlas_data.gd")

# ---- times and speeds, from the JavaScript mockup
const WALK_SPEED := 150.0
const HELPER_WALK_SPEED := 120.0
const WALK_FRAME := 0.13
const POP_TIME := 0.35
const POP_HIDDEN := 0.12
const IDLE_AFTER_POP := 0.4
const FLOP_TIME := 1.8
const APPROVE_TIME := 0.45
const HOP_UP := 0.25
const HOP_DOWN := 0.22
const HELPER_WAVE_TIME := 0.6
const VANISH_TIME := 0.35
const VANISH_HIDDEN := 0.1
const BLINK_PERIOD := 2.9
const BLINK_TIME := 0.12
# ---- choices (the mockup scripts the lengths, a live actor needs rules)
## A penguin that has no event waits this long where it stands, and then walks to its rest point.
const LINGER_TIME := 2.0
## A call works at least this long after it has reached its station, even when its end is already in the queue.
const MIN_WORK := 0.9
const MIN_WAIT := 1.0
const MIN_THINK := 1.2
const CHEER_TIME := 4.0
const GENERIC_WORK_TIME := 1.2
## The bell of the helper desk rings for this long. The call goes on, and the penguin stands at the desk.
const BELL_TIME := 1.0
## Hurry: each event in the queue after the first one adds this much speed, up to HURRY_MAX.
const HURRY_STEP := 0.5
const HURRY_MAX := 4.0
## The point where smoke rises when a call at the forge fails.
const CHIMNEY := Vector2(396, 66)
const HELPER_SCALE := 0.72
## Where a second and a third penguin celebrate, as offsets from the stage point, so that they do not stand on each other.
const STAGE_OFFSETS: Array[Vector2] = [
	Vector2(0, 0), Vector2(-34, 4), Vector2(34, 4), Vector2(-68, 10), Vector2(68, 10), Vector2(0, -20), Vector2(-34, -16), Vector2(34, -16),
]

## The segments that a `waiting_permission` event may cut (it takes the penguin at once, as an approval takes the focus).
const CUTTABLE: Array[String] = ["walk", "work", "queue", "think", "idle"]

# ---- what the view reads
var key: String = ""
var framework: String = ""
var session: String = ""
var agent: String = ""
## The number of the agent in the room. A helper wears the number of its parent.
var number: int = 0
## The cap cord: a key of CORDS in atlas_data.gd.
var cord: String = "default"
var is_helper: bool = false
var parent_key: String = ""
## The foot of the penguin, in room pixels.
var position: Vector2 = Vector2.ZERO
## "front", "back", "left" or "right".
var facing: String = "front"
## A pose name of the atlas ("idle", "hammer", "read", ...). In a flop it is "idle": use `flop_age`.
var pose: String = "idle"
## What the penguin does: "idle", "walk", "hop", "work", "wait", "queue", "think", "sit", "approve", "flop", "cheer",
## "pop", "wave" or "vanish".
var activity: String = "idle"
## The category of the station that it is at or walks to. "" when it has none. "stage" for a celebration.
var station: String = ""
## What the call is about, and how it goes: "run", "WAIT", "OK", "FAIL", "DONE" or "".
var target: String = ""
var status: String = ""
## Lift of the picture in pixels (negative is up) and the radius of the shadow minus one (0 for no shadow).
var y_off: int = 0
var shadow: int = 7
var blink: bool = false
var hidden: bool = false
## The time in the flop in seconds, or -1.0.
var flop_age: float = -1.0
## The time in a spell of thinking in seconds, or -1.0. `think_in_place` is true when it is not in the armchair.
var think_age: float = -1.0
var think_in_place: bool = false
## The place on the stage of a penguin that celebrates (an index of STAGE_OFFSETS).
var stage_slot: int = 0
## True after the helper has vanished, or the penguin has walked out of the room: the director removes it.
var gone: bool = false
## The arena (a letter) of the room that the actor is in. The director sets it. A penguin never changes arena.
var arena: String = ""
## True while the penguin walks out through the door, because its agent was quiet for too long (`leave_after`).
var leaving: bool = false
## Where the penguin walks when it has had nothing to do for LINGER_TIME.
var rest_point: Vector2 = Vector2(240, 150)
## The events that wait. The director applies the backlog rule to this list.
var queue: Array = []
## The simulation time of the last event that came in.
var last_event_time: float = -1.0

var _segs: Array[Dictionary] = []
var _task: Dictionary = { }
var _suspended: Dictionary = { }
var _asking: bool = false


## Starts the actor at a point. A penguin pops in with a puff. A helper pops in at the helper desk and walks to the telescope.
## `delay` is a time in which the actor is not there yet: the first penguin of a new arena pops in a little after the arena opens.
func start(world: RefCounted, spawn: Vector2, delay: float = 0.0) -> void:
	position = spawn
	world.effects.add("puff", world.now + delay, spawn.x, spawn.y, _effect_scale())
	_segs.clear()
	if delay > 0.0:
		_segs.append(_seg("hidden", delay, {"at": spawn}))
	_segs.append(_seg("pop", POP_TIME, {"at": spawn}))
	if is_helper:
		_segs.append(_seg("wave", HELPER_WAVE_TIME, {"at": spawn}))
		_walk(_segs, spawn, Stations.point("scope"))
		_segs.append(_seg("work", INF, {"at": Vector2(Stations.point("scope")), "anim": "helper/peer", "interrupt": true, "role": "peer", "shadow": 4}))
		rest_point = Vector2(Stations.point("scope"))
		station = "web"
	else:
		_segs.append(_seg("idle", IDLE_AFTER_POP, {"at": spawn}))
	_apply_look(world)


## Adds an event to the queue. The director calls this.
func enqueue(event: RefCounted, world: RefCounted) -> void:
	queue.append(event)
	last_event_time = world.now


## The helper's subagent ended: it vanishes with a puff. The director removes it afterwards (`gone`).
func finish(world: RefCounted) -> void:
	queue.clear()
	_release_station(world)
	_task = { }
	_suspended = { }
	_asking = false
	_segs.clear()
	world.effects.add("puff", world.now, position.x, position.y, _effect_scale())
	_segs.append(_seg("vanish", VANISH_TIME, {"at": position}))


## The agent was quiet for too long: the penguin goes out through the door in the bottom wall. Its place at a station is
## freed now and its events are dropped. It is `gone` when it is out of sight. The director frees the place in the arena.
func leave(world: RefCounted) -> void:
	queue.clear()
	_release_station(world)
	_task = { }
	_suspended = { }
	_asking = false
	leaving = true
	status = ""
	var door: Vector2 = Vector2(Stations.point("door"))
	var out: Vector2 = Vector2(Stations.point("out"))
	# a penguin in the middle of a hop or a flop leaves from where it is
	_segs.clear()
	_walk(_segs, position, door)
	_walk(_segs, door, out)
	_segs.append(_seg("gone", 0.0, {"at": out}))


## One simulation step of `dt` seconds. The world's time is already set.
func step(world: RefCounted, dt: float) -> void:
	_advance(world, dt * hurry())
	_take_events(world)
	if _segs.is_empty():
		_push_idle()
	_begin(_segs[0], world)
	_apply_look(world)


## The speed of the actor's own time: 1.0 with at most one event waiting, more when events pile up.
func hurry() -> float:
	return clampf(1.0 + HURRY_STEP * float(maxi(0, queue.size() - 1)), 1.0, HURRY_MAX)


## True when a call is open (a tool_start without its tool_end).
func has_call() -> bool:
	return not _task.is_empty() or not _suspended.is_empty()


## True when the penguin waits at the sign post (or in the line there).
func is_asking() -> bool:
	return _asking


## The placement of the penguin changed: it got a spot, or it moved up in a line.
func placement_changed(placement: Dictionary, _world: RefCounted) -> void:
	if _task.is_empty() and not _asking:
		return
	_go_to_placement(placement)


## The segment that runs now (an empty Dictionary when there is none). Tests read it.
func current_segment() -> Dictionary:
	return _segs[0] if not _segs.is_empty() else { }


# ---------------------------------------------------------------- the queue

func _take_events(world: RefCounted) -> void:
	while not queue.is_empty():
		var next_event: RefCounted = queue[0]
		if _asking and next_event.type == "waiting_permission":
			# A second prompt while the penguin already waits changes nothing.
			queue.pop_front()
			continue
		if next_event.type == "thinking" and not _segs.is_empty() and ["think", "sit"].has(str(_segs[0]["kind"])):
			# More thinking while it thinks changes nothing.
			queue.pop_front()
			continue
		if _can_take():
			if _exit_first(world):
				return
			var event: RefCounted = queue.pop_front()
			_consume(event, world)
		else:
			return


func _can_take() -> bool:
	if _segs.is_empty():
		return true
	var front: RefCounted = queue[0]
	if front.type == "waiting_permission" and not _asking:
		var all_cuttable: bool = true
		for segment in _segs:
			if not CUTTABLE.has(segment["kind"]):
				all_cuttable = false
		if all_cuttable:
			return true
	var first: Dictionary = _segs[0]
	if first.get("interrupt", false):
		return true
	if _segs.size() > 1:
		return false
	if first["dur"] != INF:
		return false
	return float(first["age"]) >= float(first.get("dwell", 0.0))


## A penguin that sits or waits for an approval ends that first (a hop down, the cheer of an approval). Returns true when
## it pushed such a segment: the event then waits in the queue until it is over.
func _exit_first(world: RefCounted) -> bool:
	if _segs.is_empty():
		return false
	if _asking:
		var here: Vector2 = position
		_asking = false
		_segs.clear()
		# the spot at the sign post stays taken for the small cheer of the answer, and is freed when it ends (see `_finish`)
		_segs.append(_seg("approve", APPROVE_TIME, {"at": here, "hold_spot": true}))
		status = "OK"
		return true
	if _segs[0]["kind"] == "sit":
		_release_station(world)
		_segs.clear()
		var seat: Vector2 = Vector2(Stations.point("seat"))
		var front_of_chair: Vector2 = Vector2(Stations.point("chairFront"))
		_segs.append(_seg("hop", HOP_DOWN, {"from": seat, "to": front_of_chair}))
		return true
	return false


func _consume(event: RefCounted, world: RefCounted) -> void:
	match event.type:
		"tool_start":
			_start_tool(event, world)
		"tool_end":
			_end_tool(event, world)
		"waiting_permission":
			if not _asking:
				_start_wait(event, world)
		"thinking":
			_start_think(world)
		"done":
			_start_done(world)
		"error":
			_flop_here(world, false)
		"session_start", "subagent_start", "subagent_end":
			pass
		_:
			_start_generic(world)


# ---------------------------------------------------------------- the events

func _start_tool(event: RefCounted, world: RefCounted) -> void:
	var category: String = event.category if event.category != "" else "other"
	if category == "think":
		_start_think(world)
		return
	_drop_call(world, category)
	_task = {"id": event.id, "category": category, "target": event.target, "generic": false}
	target = event.target
	status = "run"
	_go_to_placement(world.spots.arrive(key, category))


func _start_generic(world: RefCounted) -> void:
	_drop_call(world, "other")
	_task = {"id": "", "category": "other", "target": "", "generic": true}
	target = ""
	status = "run"
	_go_to_placement(world.spots.arrive(key, "other"))


func _end_tool(event: RefCounted, world: RefCounted) -> void:
	var open: Dictionary = _task if not _task.is_empty() else _suspended
	var matches: bool = not open.is_empty() and (event.id == "" or str(open.get("id", "")) == "" or event.id == str(open["id"]))
	if not matches:
		# An end of a call that the penguin left: a failure still shows, a success is ignored.
		if event.ok == false:
			_flop_here(world, false)
		return
	var category: String = str(open["category"])
	var failed: bool = event.ok == false
	if not failed:
		_release_station(world)
	_task = { }
	_suspended = { }
	if failed:
		# the penguin lies on its spot for the flop, so the spot stays taken until it gets up (see `_flop_here`)
		_asking = false
		_flop_here(world, category == "exec", true)
	else:
		status = "OK"
		_segs.clear()


func _start_wait(event: RefCounted, world: RefCounted) -> void:
	if not _task.is_empty():
		_suspended = _task
		_task = { }
	_release_station(world)
	_asking = true
	_sound(world, "chime", world.now)
	status = "WAIT"
	if event.target != "":
		target = event.target
	_go_to_placement(world.spots.arrive(key, "ask_permission"))


func _start_think(world: RefCounted) -> void:
	if not _segs.is_empty() and ["think", "sit"].has(str(_segs[0]["kind"])):
		return
	_drop_call(world, "think")
	target = "thinking"
	status = "run"
	var from: Vector2 = position
	_segs.clear()
	var seat_free: bool = world.spots.holder("think", 0) == null
	if seat_free:
		world.spots.arrive(key, "think")
		station = "think"
		var front_of_chair: Vector2 = Vector2(Stations.point("chairFront"))
		var seat: Vector2 = Vector2(Stations.point("seat"))
		_walk(_segs, from, front_of_chair)
		_segs.append(_seg("hop", HOP_UP, {"from": front_of_chair, "to": seat}))
		_segs.append(_seg("sit", INF, {"at": seat, "dwell": MIN_THINK}))
	else:
		_release_station(world)
		_segs.append(_seg("think", INF, {"at": from, "dwell": MIN_THINK}))


func _start_done(world: RefCounted) -> void:
	_drop_call(world, "")
	target = "turn complete"
	status = "DONE"
	var from: Vector2 = position
	var stage: Vector2 = Vector2(Stations.point("stage")) + STAGE_OFFSETS[_free_stage_slot(world)]
	_segs.clear()
	station = "stage"
	_walk(_segs, from, stage)
	_segs.append(_seg("cheer", CHEER_TIME, {"at": stage}))


## The first place on the stage that no other penguin is using. A penguin uses a place while its station is "stage".
func _free_stage_slot(world: RefCounted) -> int:
	var taken: Dictionary = { }
	for other_key: String in world.actors:
		var other: RefCounted = world.actors[other_key]
		if other != self and other.station == "stage":
			taken[other.stage_slot] = true
	for slot in STAGE_OFFSETS.size():
		if not taken.has(slot):
			stage_slot = slot
			return slot
	stage_slot = 0
	return 0


## The penguin falls down where it stands. `smoke` adds smoke at the chimney of the forge. With `hold_spot` the penguin keeps its spot
## until the flop is over: the next penguin of the line must not stand on the one that lies there (the recorder checks it).
func _flop_here(world: RefCounted, smoke: bool, hold_spot: bool = false) -> void:
	_drop_call(world, "")
	status = "FAIL"
	var here: Vector2 = position
	_segs.clear()
	_segs.append(_seg("flop", FLOP_TIME, {"at": here, "smoke": smoke, "hold_spot": hold_spot}))


# ---------------------------------------------------------------- scripts of segments

## Gives the script for a placement of the spot logic: walk to the spot and work there, or walk to the line and wait.
func _go_to_placement(placement: Dictionary) -> void:
	var from: Vector2 = position
	var point: Vector2 = Vector2(placement["point"])
	var category: String = str(placement["category"])
	station = category
	_segs.clear()
	if placement["queued"]:
		_walk(_segs, from, point)
		_segs.append(_seg("queue", INF, {"at": point, "dwell": 0.3, "anim": "queue"}))
		return
	_walk(_segs, from, point)
	var role: String = "wait" if _asking else "tool"
	var extra: Dictionary = {
		"at": point, "anim": str(placement["anim"]), "frame": int(placement["frame"]), "shadow": int(placement["shadow"]),
		"category": category, "role": role, "dwell": MIN_WAIT if _asking else MIN_WORK,
	}
	if category == "delegate":
		extra["active_for"] = BELL_TIME
	if role == "tool" and bool(_task.get("generic", false)):
		_segs.append(_seg("work", GENERIC_WORK_TIME, extra))
	else:
		_segs.append(_seg("work", INF, extra))


func _seg(kind: String, dur: float, data: Dictionary = { }) -> Dictionary:
	var segment: Dictionary = {"kind": kind, "dur": dur, "age": 0.0, "started": false}
	segment.merge(data, true)
	return segment


## Adds a walk from `from` to `to`. A walk of less than one pixel is left out.
func _walk(list: Array[Dictionary], from: Vector2, to: Vector2, extra: Dictionary = { }) -> void:
	var distance: float = from.distance_to(to)
	if distance < 1.0:
		return
	var speed: float = HELPER_WALK_SPEED if is_helper else WALK_SPEED
	var data: Dictionary = {"from": from, "to": to}
	data.merge(extra, true)
	list.append(_seg("walk", distance / speed, data))


## Frees the spot or the place in the line, and tells the others.
func _release_station(world: RefCounted) -> void:
	station = ""
	if world.spots.has(key):
		world.leave_station(key)


## A new call, a thinking spell or a celebration ends the open call and the station of the one before.
func _drop_call(world: RefCounted, next_category: String) -> void:
	_suspended = { }
	if not _task.is_empty() or _asking or world.spots.has(key):
		var current: String = str(_task.get("category", ""))
		if current != next_category or _asking:
			_release_station(world)
	_task = { }
	_asking = false
	think_age = -1.0


func _effect_scale() -> float:
	return HELPER_SCALE if is_helper else 1.0


# ---------------------------------------------------------------- time

func _advance(world: RefCounted, local_dt: float) -> void:
	var left: float = local_dt
	if _segs.is_empty():
		_push_idle()
	var guard: int = 0
	while left > 0.0 and not _segs.is_empty() and guard < 64:
		guard += 1
		var segment: Dictionary = _segs[0]
		_begin(segment, world)
		var room: float = float(segment["dur"]) - float(segment["age"])
		if left < room:
			var before: float = float(segment["age"])
			segment["age"] = before + left
			_effects(segment, before, float(segment["age"]), world)
			left = 0.0
			_rest_check(segment)
		else:
			var before: float = float(segment["age"])
			segment["age"] = segment["dur"]
			_effects(segment, before, float(segment["dur"]), world)
			left -= room
			_finish(segment, world)
			_segs.pop_front()
			if _segs.is_empty():
				_push_idle()
	if _segs.is_empty():
		_push_idle()


func _push_idle() -> void:
	_segs.append(_seg("idle", INF, {"at": position, "rest": true}))


## A penguin that has stood idle for LINGER_TIME walks to its rest point. A new event cuts the walk.
func _rest_check(segment: Dictionary) -> void:
	if segment["kind"] != "idle" or not segment.get("rest", false) or not queue.is_empty():
		return
	if float(segment["age"]) < LINGER_TIME:
		return
	if position.distance_to(rest_point) < 4.0:
		segment["rest"] = false
		return
	var list: Array[Dictionary] = []
	_walk(list, position, rest_point, {"interrupt": true})
	list.append(_seg("idle", INF, {"at": rest_point}))
	_segs = list


## What happens when a segment starts: a puff, the smoke of a failed call, the confetti of a celebration.
func _begin(segment: Dictionary, world: RefCounted) -> void:
	if segment["started"]:
		return
	segment["started"] = true
	match segment["kind"]:
		"flop":
			world.effects.note_failure(world.now)
			_sound(world, "flop", world.now)
			if segment.get("smoke", false):
				world.effects.add("smoke", world.now, CHIMNEY.x, CHIMNEY.y, 1.0, 0)
			status = "FAIL"
		"cheer":
			var at: Vector2 = segment["at"]
			world.effects.add("confetti", world.now, at.x, at.y, 1.0, 7 + int(at.x))
			_sound(world, "fanfare", world.now + FANFARE_DELAY)
			for i in SPARKLES.size():
				var entry: Array = SPARKLES[i]
				world.effects.add("sparkle", world.now + float(entry[0]), at.x + float(entry[1]), at.y + float(entry[2]), 1.0, i)


## The fanfare of a finished turn sounds this long after the cheer starts (`soundCues` of the JavaScript mockup).
const FANFARE_DELAY := 0.15


## Says that a sound is due (see `World.add_sound`). A helper makes no sound: the mockup has cues for the agents only.
func _sound(world: RefCounted, sound_name: String, t: float) -> void:
	if not is_helper:
		world.add_sound(sound_name, t)


## [delay, dx, dy] of the sparkles of a celebration, relative to the foot of the penguin (the mockup's `sparkle` list).
const SPARKLES: Array = [
	[0.05, -26.0, -44.0], [0.3, 24.0, -50.0], [0.6, -20.0, -66.0], [0.9, 28.0, -36.0], [1.3, -30.0, -58.0], [1.7, 22.0, -62.0],
]


## The effects that start while a segment goes from age `a0` to `a1`: dust under a walk, the sparks of the forge, the stars
## of the hammer and of the bell.
func _effects(segment: Dictionary, a0: float, a1: float, world: RefCounted) -> void:
	var scale: float = _effect_scale()
	match segment["kind"]:
		"walk":
			var dur: float = float(segment["dur"])
			var from: Vector2 = segment["from"]
			var to: Vector2 = segment["to"]
			var k: int = maxi(0, int(floorf((a0 - 0.08) / 0.18)) + 1)
			while true:
				var at: float = 0.08 + float(k) * 0.18
				if at > a1 or at >= dur:
					break
				var point: Vector2 = from.lerp(to, at / dur)
				world.effects.add("dust", world.now, point.x, point.y - 1.0, scale, 0)
				k += 1
		"work":
			if not Data.ANIMATIONS.has(segment["anim"]):
				return
			var period: float = float(Data.ANIMATIONS[segment["anim"]]["period"])
			var active_for: float = float(segment.get("active_for", INF))
			var f0: int = int(floorf(a0 / period))
			var f1: int = int(floorf(minf(a1, active_for) / period))
			var at: Vector2 = segment["at"]
			for f in range(f0 + 1, f1 + 1):
				if f % 2 == 0:
					continue
				# The shovel makes sparks at the forge, the hammers make stars, and the bell makes stars too.
				var anim: String = str(segment["anim"])
				if anim == "exec":
					world.effects.add("spark", world.now, at.x, at.y, 1.0, int(roundf(world.now * 1000.0)))
				elif anim == "write" or anim == "other":
					world.effects.add("tink", world.now, at.x, at.y, 1.0, 0)
					_sound(world, "tink", world.now)
				elif anim == "delegate":
					world.effects.add("bell", world.now, at.x, at.y, 1.0, 0)
					if f == 1:
						# the desk bell sounds once: when the penguin first rings it
						_sound(world, "bell", world.now)


func _finish(segment: Dictionary, world: RefCounted) -> void:
	if segment.get("hold_spot", false):
		_release_station(world)
	match segment["kind"]:
		"work":
			if segment["role"] == "tool" and float(segment["dur"]) != INF:
				# generic work is over: the call is done
				_task = { }
				status = "OK"
				_release_station(world)
		"vanish", "gone":
			gone = true
			hidden = true


# ---------------------------------------------------------------- the look

## Position, facing, pose and the small values, from the segment that runs.
func _apply_look(world: RefCounted) -> void:
	if _segs.is_empty():
		return
	var segment: Dictionary = _segs[0]
	var age: float = float(segment["age"])
	var kind: String = segment["kind"]
	activity = kind
	y_off = 0
	shadow = 7
	hidden = false
	flop_age = -1.0
	think_age = -1.0
	think_in_place = false
	blink = fmod(world.now + float(number) * 0.7, BLINK_PERIOD) < BLINK_TIME
	if is_helper:
		shadow = 4
	match kind:
		"hidden", "gone":
			position = segment["at"]
			hidden = true
			_set_look("front", "idle")
		"pop":
			position = segment["at"]
			hidden = age < POP_HIDDEN
			_set_look("front", "idle")
		"idle":
			position = segment["at"]
			if int(floorf(world.now * 2.0 + float(number))) % 2 != 0:
				y_off = -1
			_set_look("front", "idle")
		"wave":
			position = segment["at"]
			_set_look("front", "wave2" if int(floorf(age / 0.2)) % 2 != 0 else "wave")
		"walk":
			var from: Vector2 = segment["from"]
			var to: Vector2 = segment["to"]
			var fraction: float = minf(1.0, age / float(segment["dur"]))
			position = from.lerp(to, fraction)
			var step_frame: int = int(floorf(age / WALK_FRAME)) % 2
			_walk_look(to - from)
			pose = "walk2" if step_frame == 1 else "walk"
			y_off = -1 if step_frame == 1 else 0
		"hop":
			var from: Vector2 = segment["from"]
			var to: Vector2 = segment["to"]
			var fraction: float = minf(1.0, age / float(segment["dur"]))
			position = from.lerp(to, fraction)
			y_off = -int(roundf(sin(fraction * PI) * 6.0))
			shadow = 0
			_set_look("front", "idle")
		"sit":
			position = segment["at"]
			shadow = 0
			think_age = age
			if int(floorf(world.now * 1.6)) % 2 != 0:
				y_off = -1
			_set_look("front", "think")
		"think":
			position = segment["at"]
			think_age = age
			think_in_place = true
			_set_look("front", "think")
		"queue":
			position = segment["at"]
			if int(floorf(world.now * 2.0)) % 2 != 0:
				y_off = -1
			_set_look("right", "idle")
		"approve":
			position = segment["at"]
			y_off = -int(roundf(sin(minf(1.0, age / 0.3) * PI) * 4.0))
			_set_look("front", "cheer")
		"flop":
			position = segment["at"]
			flop_age = age
			_set_look("front", "idle")
		"cheer":
			position = segment["at"]
			var phase: float = fmod(age, 0.55) / 0.55
			y_off = -int(roundf(sin(phase * PI) * 9.0))
			shadow = 7 - int(roundf(float(-y_off) / 3.0))
			_set_look("front", "cheer" if phase < 0.5 else "cheer2")
		"work":
			position = segment["at"]
			if segment.get("role", "") == "wait":
				activity = "wait"
			_work_look(segment, age)
		"vanish":
			position = segment["at"]
			hidden = age > VANISH_HIDDEN
			_set_look("front", "idle")


func _work_look(segment: Dictionary, age: float) -> void:
	var anim: String = str(segment["anim"])
	if not Data.ANIMATIONS.has(anim):
		_set_look("front", "idle")
		return
	if not is_helper and segment.has("shadow"):
		shadow = int(segment["shadow"])
	var entry: Dictionary = Data.ANIMATIONS[anim]
	var active_for: float = float(segment.get("active_for", INF))
	if age >= active_for:
		_set_look("front", "idle")
		return
	var poses: Array = entry["poses"]
	var frame: int = int(floorf(age / float(entry["period"]))) + int(segment.get("frame", 0))
	var direction: String = entry["dir"]
	if direction == "side":
		_set_look("left" if entry["flip"] else "right", str(poses[posmod(frame, poses.size())]))
	else:
		_set_look(direction, str(poses[posmod(frame, poses.size())]))
	if direction == "back":
		blink = false


func _set_look(new_facing: String, new_pose: String) -> void:
	facing = new_facing
	pose = new_pose


## The facing of a walk: sideways when the move is mostly horizontal (`walkLook` in session.js).
func _walk_look(delta: Vector2) -> void:
	if absf(delta.x) > absf(delta.y) * 0.9:
		facing = "left" if delta.x < 0.0 else "right"
	else:
		facing = "back" if delta.y < 0.0 else "front"
