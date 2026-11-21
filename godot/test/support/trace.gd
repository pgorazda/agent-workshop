extends RefCounted
## Helpers for the behaviour tests: read events from a JSON Lines file or a timeline, play them into a director in fixed
## steps, and write down where the penguins are, as a trace that does not depend on the language.

const Event := preload("res://src/core/event.gd")
const Clock := preload("res://src/core/clock.gd")
const Director := preload("res://src/core/director.gd")
const TraceLog := preload("res://src/core/trace_log.gd")


## The events of a JSON Lines file, each with its time in seconds from the first event: [{"t": 0.0, "event": Event}].
static func read_jsonl(path: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return list
	var first: float = -1.0
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty():
			continue
		var event: RefCounted = Event.parse(line)
		if event == null:
			continue
		if first < 0.0:
			first = event.ts
		list.append({"t": (event.ts - first) / 1000.0, "event": event})
	return list


## The label of what an actor does now, or "" when it is not at a station (see `core/trace_log.gd`).
static func label_of(actor: RefCounted) -> String:
	return TraceLog.label_of(actor)


## The name of an actor in a trace: "agent 3" for a penguin and "helper 3" for the helper of penguin 3.
static func who_of(actor: RefCounted) -> String:
	return TraceLog.who_of(actor)


## Plays the timeline into a director, one step of the clock at a time, until `duration` seconds. Returns the trace: for each
## actor (see `who_of`) the list of labels in the order in which they changed (see `label_of`). Each label is written once
## for as long as it lasts.
static func play(director: RefCounted, timeline: Array[Dictionary], duration: float, on_step: Callable = Callable()) -> Dictionary:
	var clock: RefCounted = Clock.new()
	var trace: Dictionary = { }
	var last: Dictionary = { }
	var next: int = 0
	while clock.now < duration:
		while next < timeline.size() and float(timeline[next]["t"]) <= clock.now + 1e-9:
			director.handle_event(timeline[next]["event"])
			next += 1
		clock.tick()
		director.step(clock.now)
		for key: String in director.world.actors:
			var actor: RefCounted = director.world.actors[key]
			var label: String = label_of(actor)
			var who: String = who_of(actor)
			if label != "" and last.get(key, "") != label:
				if not trace.has(who):
					trace[who] = []
				(trace[who] as Array).append(label)
				last[key] = label
			elif label == "":
				last[key] = ""
		if on_step.is_valid():
			on_step.call(clock.now, director)
	return trace


## An event from a dictionary. `extra` adds fields. The time is in milliseconds.
static func ev(type: String, extra: Dictionary = { }, agent: String = "main", framework: String = "claude-code", session: String = "s1") -> RefCounted:
	var data: Dictionary = {"v": 1, "framework": framework, "session": session, "agent": agent, "type": type, "ts": 1000}
	data.merge(extra, true)
	return Event.from_dictionary(data)


## A tool call start with a category.
static func tool_start(category: String, target: String = "x", id: String = "c1", agent: String = "main", framework: String = "claude-code", session: String = "s1") -> RefCounted:
	return ev("tool_start", {"category": category, "tool": "Tool", "target": target, "id": id}, agent, framework, session)


static func tool_end(ok: bool = true, id: String = "c1", agent: String = "main", framework: String = "claude-code", session: String = "s1") -> RefCounted:
	return ev("tool_end", {"ok": ok, "id": id}, agent, framework, session)


## Runs the director for `seconds` of simulation time with the given clock. Returns the new time.
static func run(director: RefCounted, clock: RefCounted, seconds: float) -> float:
	var end: float = clock.now + seconds
	while clock.now < end - 1e-9:
		clock.tick()
		director.step(clock.now)
	return clock.now


## Runs until `done` returns true, at most `limit` seconds. Returns true when it did. `done` takes no argument.
static func run_until(director: RefCounted, clock: RefCounted, done: Callable, limit: float = 20.0) -> bool:
	var end: float = clock.now + limit
	while clock.now < end:
		if done.call():
			return true
		clock.tick()
		director.step(clock.now)
	return done.call()
