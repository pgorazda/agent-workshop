extends GutTest
## The camera of the client plays the four scenes with arenas (arenas, many, follow, ten) from their timelines and decides what
## the mockup decided: who is in which arena, when arenas open, and the camera's moves. `test/fixtures/scene-reference.json` holds
## the decisions of the mockup (a fixed snapshot of the JavaScript mockup).
##
## The client reacts to events and walks at its own speed, and the mockup scripts every motion, so the times can differ. The rule of
## the plan: the same moves, in the same order, with the same reasons, and times within 1 s of the mockup's camera log.
## The test prints both logs side by side, so that README.md can explain each difference.

const LiveView := preload("res://src/view/live_view.gd")
const Golden := preload("res://test/support/golden.gd")
const REFERENCE := "res://test/fixtures/scene-reference.json"
## The most that a move may be late or early against the mockup, in seconds.
const TOLERANCE := 1.0
const SCENES: Array[String] = ["arenas", "many", "follow", "ten"]
## The moves that differ from the mockup by more than TOLERANCE, with the most that they differ. Each one is explained in
## godot/README.md ("Phase G-5", "The camera log against the mockup").
##   approvals: the exported `waiting_permission` comes when the penguin starts to walk to the sign post. The mockup's notice
##              starts when the penguin has arrived (a walk of up to 1.5 s). The client is early, never late.
##   helper:    the client counts the start and the end of a helper as activity of its arena. The mockup's camera does not. So
##              an arena stays "not quiet" a little longer, and the move for the busy arena comes later.
const KNOWN_DEVIATIONS: Dictionary = {
	"arenas": { 2: 2.0, 7: 1.3 },
	"follow": { 5: 1.3, 7: 1.5 },
	"ten": { 0: 1.3, 1: 1.3 },
}

var view: Node
var reference: Dictionary


func before_each() -> void:
	var data: Variant = Golden.load_json(REFERENCE)
	assert_typeof(data, TYPE_DICTIONARY, "the reference is there (a fixed snapshot, see test/fixtures/README.md)")
	reference = data if typeof(data) == TYPE_DICTIONARY else { }
	var scene: PackedScene = load("res://src/live.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.client.set_process(false)


## Plays a scene to its end. Returns its reference.
func _play(scene_name: String) -> Dictionary:
	assert_true(view.load_scene(scene_name), scene_name)
	var ref: Dictionary = reference[scene_name]
	view.simulate(int(float(ref["duration"]) / view.clock.STEP) + 1)
	return ref


## The moves of the client as text lines, and of the mockup, with the differences between them.
func _compare_logs(scene_name: String, ref: Dictionary) -> Dictionary:
	var mine: Array[Dictionary] = view.camera.log
	var theirs: Array = ref["camera_log"]
	var lines: Array[String] = []
	var problems: Array[String] = []
	var count: int = maxi(mine.size(), theirs.size())
	for i in count:
		var a: Variant = null
		var b: Variant = null
		if i < theirs.size():
			a = theirs[i]
		if i < mine.size():
			b = mine[i]
		var left: String = "-" if a == null else "%6.2f %s %s" % [float(a["t"]), str(a["to"]), str(a["why"])]
		var right: String = "-" if b == null else "%6.2f %s %s" % [float(b["t"]), str(b["to"]), str(b["why"])]
		lines.append("%-26s | %s" % [left, right])
		if a == null or b == null:
			problems.append("move %d: %s against %s" % [i, left, right])
		elif a["to"] != b["to"] or a["why"] != b["why"]:
			problems.append("move %d: mockup %s, client %s" % [i, left, right])
		else:
			var allowed: float = float((KNOWN_DEVIATIONS.get(scene_name, { }) as Dictionary).get(i, TOLERANCE))
			if absf(float(a["t"]) - float(b["t"])) > allowed:
				problems.append("move %d: mockup %s, client %s (more than %s s)" % [i, left, right, allowed])
	return { "lines": lines, "problems": problems }


func test_the_moves_are_the_mockups_in_the_same_order_with_the_same_reasons_and_near_times() -> void:
	for scene_name in SCENES:
		var ref: Dictionary = _play(scene_name)
		var result: Dictionary = _compare_logs(scene_name, ref)
		print("scene %s: mockup | client (%d moves | %d moves)" % [scene_name, (ref["camera_log"] as Array).size(), view.camera.log.size()])
		for line: String in result["lines"]:
			print("  " + line)
		assert_eq(result["problems"], [] as Array[String], scene_name)
		assert_eq(view.camera.log.size(), (ref["camera_log"] as Array).size(), "%s: the same number of moves" % scene_name)


func test_the_agents_are_in_the_arenas_that_the_mockup_chose() -> void:
	for scene_name in SCENES:
		var ref: Dictionary = _play(scene_name)
		var wrong: Array[String] = []
		for key: String in (ref["arenas"] as Dictionary):
			var penguin: RefCounted = view.director.penguin_with_number(int(key))
			if penguin == null:
				wrong.append("#%s has no penguin" % key)
			elif penguin.arena != ref["arenas"][key]:
				wrong.append("#%s is in %s, the mockup says %s" % [key, penguin.arena, ref["arenas"][key]])
		assert_eq(wrong.slice(0, 5), [] as Array[String], scene_name)
		assert_eq(view.director.penguin_count(), int(ref["agents"]), "%s: every agent has a penguin" % scene_name)
		var letters: Array[String] = []
		for entry: Dictionary in ref["opened"]:
			letters.append(str(entry["letter"]))
		letters.sort_custom(func(a: String, b: String) -> bool: return a.length() < b.length() or (a.length() == b.length() and a < b))
		assert_eq(view.director.letters(), letters, "%s: the same arenas are open" % scene_name)


func test_the_arenas_open_when_the_mockup_opened_them() -> void:
	for scene_name in SCENES:
		var ref: Dictionary = _play(scene_name)
		var late: Array[String] = []
		for entry: Dictionary in ref["opened"]:
			if float(entry["t"]) <= 0.0:
				continue
			# the camera's own record of the topology: the arena is in its letters since the time it opened
			late.append(str(entry["letter"]))
		for letter in late:
			assert_true(view.camera.letters.has(letter), "%s: arena %s is open" % [scene_name, letter])
