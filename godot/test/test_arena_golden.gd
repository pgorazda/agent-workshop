extends GutTest
## Golden data: the GDScript arena rules give the same results as the JavaScript reference.
## The JavaScript mockup ran its rules on a list of specs. This test runs the same specs through
## `arena_rules.gd` and compares. Floats must agree within 1e-9.
## `test/fixtures/arena_rules.json` holds the specs of the 34 cases and more. `camera-<scene>.json` holds the
## camera input of one scene of the mockup and the camera log and frames of the JavaScript.

const ArenaRules := preload("res://src/core/arena_rules.gd")
const Golden := preload("res://test/support/golden.gd")
const FIXTURE := "res://test/fixtures/arena_rules.json"


func _fixture() -> Dictionary:
	var data: Variant = Golden.load_json(FIXTURE)
	assert_typeof(data, TYPE_DICTIONARY, "the fixture %s is there and is JSON (a fixed snapshot, see test/fixtures/README.md)" % FIXTURE)
	return data if typeof(data) == TYPE_DICTIONARY else { }


func _opts(args: Array, index: int) -> Dictionary:
	return Golden.snake_keys(args[index]) if args.size() > index else { }


func _ints(list: Array) -> Array[int]:
	var out: Array[int] = []
	for item: Variant in list:
		out.append(int(item))
	return out


func _move(spec: Dictionary) -> ArenaRules.Move:
	var move: ArenaRules.Move = ArenaRules.Move.new()
	var from: Dictionary = spec["from"]
	var to: Dictionary = spec["to"]
	move.from_pose = ArenaRules.Pose.new(from["cx"], from["cy"], from["s"])
	move.to_pose = ArenaRules.Pose.new(to["cx"], to["cy"], to["s"])
	move.t0 = spec["t0"]
	move.dur = spec["dur"]
	move.peak = spec["peak"]
	return move


## Calls the function of the port that matches a function of the JavaScript, and returns plain data.
func _call(fn: String, args: Array) -> Variant:
	match fn:
		"nameOf":
			return ArenaRules.name_of(int(args[0]))
		"indexOf":
			return ArenaRules.index_of(args[0])
		"placeOf":
			return ArenaRules.place_of(args[0], _opts(args, 1))
		"worldWidth":
			return ArenaRules.world_width(_ints(args[0]), _opts(args, 1))
		"pagesOf":
			return ArenaRules.pages_of(args[0], _opts(args, 1))
		"arenaPose":
			return ArenaRules.arena_pose(args[0], _opts(args, 1)).to_dict(false)
		"pagePose":
			return ArenaRules.page_pose(int(args[0]), _opts(args, 1)).to_dict(false)
		"peakFor":
			return ArenaRules.peak_for(args[0], int(args[1]), _opts(args, 2))
		"moveDuration":
			return ArenaRules.move_duration(args[0], int(args[1]), _opts(args, 2))
		"poseAt":
			return ArenaRules.pose_at(_move(args[0]), args[1], args[2]).to_dict(true)
		"tabState":
			return ArenaRules.tab_state(args[0])
		"leaves":
			return ArenaRules.leaves(Golden.snake_keys(args[0]), args[1], _opts(args, 2))
	fail_test("unknown function in the fixture: %s" % fn)
	return null


func test_pure_functions_agree_with_the_javascript() -> void:
	var fixture: Dictionary = _fixture()
	var total: int = 0
	for group: Dictionary in fixture.get("functions", []):
		var fn: String = group["fn"]
		var failures: Array[String] = []
		for entry: Dictionary in group["calls"]:
			var args: Array = Golden.decode(entry["args"])
			var found: String = Golden.diff(Golden.decode(entry["expected"]), _call(fn, args), "%s(%s)" % [fn, str(args)])
			total += 1
			if found != "" and failures.size() < 3:
				failures.append(found)
		assert_eq(failures, [], "%s: %d calls" % [fn, (group["calls"] as Array).size()])
	assert_gt(total, 3000, "many calls were compared")


func _run_arena_script(script: Dictionary) -> Array[String]:
	var model: ArenaRules.Arenas = ArenaRules.create_arenas(Golden.snake_keys(Golden.decode(script["opts"])))
	var failures: Array[String] = []
	var index: int = 0
	for op: Dictionary in script["ops"]:
		var args: Array = Golden.decode(op["args"])
		var result: Variant = null
		match op["op"]:
			"place":
				result = model.place(int(args[0]), args[1])
			"leave":
				model.leave(int(args[0]), args[1])
			"tick":
				result = model.tick(args[0])
			"letters":
				result = model.letters()
			"arenaOf":
				result = model.arena_of(int(args[0]))
			"agents":
				result = model.agents(args[0])
			_:
				failures.append("unknown operation: %s" % str(op["op"]))
		var found: String = Golden.diff(Golden.decode(op["expected"]), result, "op %d %s%s" % [index, op["op"], str(args)])
		if found != "":
			failures.append(found)
			break
		index += 1
	return failures


func test_arena_model_agrees_with_the_javascript() -> void:
	var fixture: Dictionary = _fixture()
	var scripts: Array = fixture.get("arenas", [])
	assert_gt(scripts.size(), 0, "the fixture has arena scripts")
	for script: Dictionary in scripts:
		assert_eq(_run_arena_script(script), [], script["name"])


## Compares the camera log and every frame of one case. Returns the problems found (the first few).
func _check_camera(kase: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var sim: ArenaRules.CameraResult = ArenaRules.simulate_camera(Golden.camera_spec(kase["spec"]))
	var expected: Dictionary = kase["expected"]
	var found: String = Golden.diff(Golden.decode(expected["log"]), sim.log, "log")
	if found != "":
		problems.append(found)
	var frames: Array[Dictionary] = Golden.expand_frames(expected)
	if frames.size() != sim.frames.size():
		problems.append("expected %d frames, got %d" % [frames.size(), sim.frames.size()])
		return problems
	for i in frames.size():
		found = Golden.diff(frames[i], sim.frames[i], "frame %d (t=%s)" % [i, frames[i]["t"]])
		if found != "":
			problems.append(found)
			if problems.size() >= 3:
				break
	return problems


func test_camera_agrees_with_the_javascript_on_the_specs_of_the_34_cases() -> void:
	var fixture: Dictionary = _fixture()
	var cases: Array = fixture.get("cameras", [])
	assert_gt(cases.size(), 40, "the fixture has the camera cases")
	for kase: Dictionary in cases:
		assert_eq(_check_camera(kase), [], kase["name"])


func test_camera_agrees_with_the_javascript_on_the_arena_scenes() -> void:
	var files: Array[String] = Golden.fixture_files("camera-")
	if files.is_empty():
		pending("no scene fixtures (camera-*.json): they are fixed snapshots, see test/fixtures/README.md")
		return
	for path in files:
		var data: Variant = Golden.load_json(path)
		assert_typeof(data, TYPE_DICTIONARY, path)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var kase: Dictionary = (data as Dictionary)["case"]
		assert_eq(_check_camera(kase), [], "%s (%s)" % [kase["name"], path.get_file()])
