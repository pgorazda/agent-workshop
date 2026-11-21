extends RefCounted
## Plays the spec of a batch camera (the input of `ArenaRules.simulate_camera`) through the incremental camera, the way a
## live client would feed it: each event at its time, and an approval is answered when its `until` time has come.
## The tests use this to compare both cameras on the golden data.

const Camera := preload("res://src/core/camera.gd")
const ArenaRules := preload("res://src/core/arena_rules.gd")


## Runs a spec (snake_case keys, as `Golden.camera_spec` gives it). Returns the camera with `frames` and `log`.
static func run(spec: Dictionary) -> Camera:
	var cam: Camera = Camera.new(spec.get("opts", { }))
	cam.record_frames = true
	var step_length: float = float(cam.o["step"])
	var opened: Array = spec.get("opened", [{ "letter": "A", "t": 0.0 }]) if spec.get("opened") != null else [{ "letter": "A", "t": 0.0 }]
	for entry: Dictionary in opened:
		cam.arena_opened(str(entry["letter"]), float(entry["t"]))
	for entry: Dictionary in spec.get("closed", []):
		cam.arena_closed(str(entry["letter"]), float(entry["t"]))
	var focus_events: Array = ArenaRules.CameraSim.sorted_by_t(spec.get("focus_events", []))
	for entry: Dictionary in focus_events:
		cam.feed_focus(str(entry["arena"]), entry.get("n"), float(entry["t"]), bool(entry.get("priority", false)))
	for entry: Dictionary in ArenaRules.CameraSim.sorted_by_t(spec.get("inputs", [])):
		var input: Dictionary = entry.duplicate()
		input.erase("t")
		cam.input(input, float(entry["t"]))
	var events: Array = ArenaRules.CameraSim.sorted_by_t(spec.get("events", []))
	var next_event: int = 0
	var answers: Array[Dictionary] = [] # { id, until }
	var steps: int = int(ArenaRules.js_round(float(spec["duration"]) / step_length))
	for s in range(steps + 1):
		var now: float = float(s) * step_length
		while next_event < events.size() and float((events[next_event] as Dictionary)["t"]) <= now + Camera.EPS:
			var e: Dictionary = events[next_event]
			next_event += 1
			var id: int = cam.feed(str(e["kind"]), str(e["arena"]), e.get("n"), float(e["t"]))
			if e["kind"] == "approval" and e.get("until") != null and float(e["until"]) != INF:
				answers.append({ "id": id, "until": float(e["until"]) })
		var rest: Array[Dictionary] = []
		for a in answers:
			if float(a["until"]) <= now:
				cam.answer(int(a["id"]), float(a["until"]))
			else:
				rest.append(a)
		answers = rest
		cam.advance(now)
	return cam
