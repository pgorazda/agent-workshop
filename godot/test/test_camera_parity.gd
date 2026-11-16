extends GutTest
## The incremental camera (`core/camera.gd`) gives the same results as the batch camera (`ArenaRules.simulate_camera`)
## and as the JavaScript. Every golden camera case runs through it with the events fed at their times and each approval
## answered when its `until` time has come. The log and every frame must agree (floats within 1e-9).

const Camera := preload("res://src/core/camera.gd")
const ArenaRules := preload("res://src/core/arena_rules.gd")
const Golden := preload("res://test/support/golden.gd")
const CameraPlayer := preload("res://test/support/camera_player.gd")
const FIXTURE := "res://test/fixtures/arena_rules.json"


func _problems(kase: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var spec: Dictionary = Golden.camera_spec(kase["spec"])
	var cam: Camera = CameraPlayer.run(spec)
	var expected: Dictionary = kase["expected"]
	var found: String = Golden.diff(Golden.decode(expected["log"]), cam.log, "log")
	if found != "":
		problems.append(found)
	var frames: Array[Dictionary] = Golden.expand_frames(expected)
	if frames.size() != cam.frames.size():
		problems.append("expected %d frames, got %d" % [frames.size(), cam.frames.size()])
		return problems
	for i in frames.size():
		found = Golden.diff(frames[i], cam.frames[i], "frame %d (t=%s)" % [i, frames[i]["t"]])
		if found != "":
			problems.append(found)
			if problems.size() >= 3:
				break
	return problems


func test_incremental_camera_agrees_on_the_golden_cases() -> void:
	var data: Variant = Golden.load_json(FIXTURE)
	assert_typeof(data, TYPE_DICTIONARY, "the fixture is there")
	if typeof(data) != TYPE_DICTIONARY:
		return
	var cases: Array = (data as Dictionary).get("cameras", [])
	assert_gt(cases.size(), 40, "the fixture has the camera cases")
	for kase: Dictionary in cases:
		assert_eq(_problems(kase), [], kase["name"])


func test_incremental_camera_agrees_on_the_arena_scenes() -> void:
	var files: Array[String] = Golden.fixture_files("camera-")
	assert_gt(files.size(), 3, "the four scene fixtures are there")
	for path in files:
		var data: Variant = Golden.load_json(path)
		assert_typeof(data, TYPE_DICTIONARY, path)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var kase: Dictionary = (data as Dictionary)["case"]
		assert_eq(_problems(kase), [], "%s (%s)" % [kase["name"], path.get_file()])


## The incremental camera and the batch port give the same frames, not only the same frames as the fixtures.
func test_incremental_camera_equals_the_batch_port_on_a_busy_script() -> void:
	var events: Array[Dictionary] = []
	var focus_events: Array[Dictionary] = []
	var kinds: Array[String] = ["activity", "activity", "fail", "done", "approval", "join", "activity"]
	for i in 120:
		var arena: String = ["A", "B", "C", "D", "E", "F"][(i * 7) % 6]
		var kind: String = kinds[(i * 5) % kinds.size()]
		var e: Dictionary = { "t": 0.9 + float(i) * 0.37, "arena": arena, "n": 1 + (i * 3) % 9, "kind": kind }
		if kind == "approval":
			e["until"] = e["t"] + 1.0 + float(i % 7)
		events.append(e)
		focus_events.append({ "t": e["t"], "arena": arena, "n": e["n"], "priority": kind != "activity" })
	var opened: Array[Dictionary] = []
	for letter: String in ["A", "B", "C", "D", "E"]:
		opened.append({ "letter": letter, "t": 0.0 })
	opened.append({ "letter": "F", "t": 12.0 })
	var spec: Dictionary = {
		"events": events, "focus_events": focus_events, "opened": opened, "closed": [{ "letter": "C", "t": 30.0 }],
		"inputs": [{ "t": 20.0, "key": "Tab" }, { "t": 22.0, "key": "Right" }, { "t": 24.0, "key": "Esc" }, { "t": 35.0, "key": "F" }],
		"duration": 50.0,
	}
	var batch: ArenaRules.CameraResult = ArenaRules.simulate_camera(spec)
	var cam: Camera = CameraPlayer.run(spec)
	assert_eq(Golden.diff(batch.log, cam.log, "log"), "")
	assert_gt(batch.log.size(), 5, "the script makes the camera move")
	assert_eq(cam.frames.size(), batch.frames.size())
	var found: String = ""
	for i in mini(cam.frames.size(), batch.frames.size()):
		found = Golden.diff(batch.frames[i], cam.frames[i], "frame %d" % i)
		if found != "":
			break
	assert_eq(found, "")


# ---------------------------------------------------------------- cases that only a live camera has

func _camera(opts: Dictionary = { }, letters: Array[String] = ["A", "B", "C"]) -> Camera:
	var cam: Camera = Camera.new(opts)
	for letter in letters:
		cam.arena_opened(letter, 0.0)
	return cam


func test_an_approval_stays_open_until_the_answer_comes() -> void:
	var cam: Camera = _camera()
	cam.advance(2.0)
	var id: int = cam.feed("approval", "B", 5, 2.0)
	assert_gt(id, -1)
	cam.advance(2.1)
	# the camera was at A for more than the hold, so it goes to B at once
	assert_eq(cam.log.size(), 1, "one move")
	assert_eq(cam.log[0]["to"], "B")
	assert_eq(cam.log[0]["why"], "pull:approval")
	# nobody answers: the approval stays open for a long time, and it still shows in the pending list
	cam.advance(60.0)
	assert_eq(cam.pending(), [] as Array[String], "the camera was there, so the pull is served")
	assert_true(cam._pulls.size() == 1, "the approval pull is still known")
	cam.answer(id, 61.0)
	cam.advance(62.0)
	assert_true(cam._pulls.is_empty(), "the answer closed it")


func test_an_open_approval_pulls_from_another_arena_for_as_long_as_it_waits() -> void:
	var cam: Camera = _camera({ "follow": { "activity": false } })
	cam.advance(3.0)
	cam.press("N", 3.0)
	cam.advance(3.1)
	assert_eq(cam.arena_shown(), "A", "N does nothing with nothing to look at")
	assert_eq(cam.mode, "MANUAL", "N leaves AUTO")
	cam.press("F", 3.5)
	cam.advance(3.6)
	assert_eq(cam.mode, "AUTO")
	cam.press("F", 3.9)
	cam.feed("approval", "C", 9, 4.0)
	cam.advance(4.1) # F switches to MANUAL: the approval does not pull
	assert_eq(cam.mode, "MANUAL")
	assert_eq(cam.arena_shown(), "A")
	cam.press("F", 30.0)
	cam.advance(30.1)
	assert_eq(cam.mode, "AUTO")
	assert_eq(cam.arena_shown(), "C", "an approval that was never answered still pulls, after 26 seconds")
	assert_eq(cam.log[cam.log.size() - 1]["why"], "pull:approval")


func test_an_answer_that_comes_before_the_camera_may_move_ends_the_pull() -> void:
	var cam: Camera = _camera()
	cam.advance(1.0)
	var id: int = cam.feed("approval", "B", 2, 1.2)
	cam.answer(id, 1.3)
	cam.advance(5.0)
	assert_eq(cam.log, [] as Array[Dictionary], "answered within a step or two: the camera never moves")
	assert_eq(cam.arena_shown(), "A")


func test_a_pull_for_an_arena_that_closes_is_dropped() -> void:
	var cam: Camera = _camera({ "follow": { "done": true } })
	cam.advance(2.0)
	cam.feed("done", "C", 4, 2.0)
	cam.arena_closed("C", 2.0)
	cam.advance(8.0)
	assert_eq(cam.arena_shown(), "A", "the camera does not go to an arena that closed")
	assert_eq(cam.log, [] as Array[Dictionary])
	assert_eq(cam.letters, ["A", "B"] as Array[String])


func test_the_arena_on_screen_closes_and_the_camera_cuts_to_its_neighbour() -> void:
	var cam: Camera = _camera()
	cam.click_tab("B", 1.0)
	cam.advance(3.0)
	assert_eq(cam.arena_shown(), "B")
	cam.arena_closed("B", 4.0)
	cam.advance(4.1)
	assert_eq(cam.arena_shown(), "A", "the arena before it in letter order")
	assert_eq(cam.log[cam.log.size() - 1]["why"], "closed")
	assert_eq(cam.moves[cam.moves.size() - 1]["kind"], "cut")


func test_events_that_arrive_between_steps_count_at_the_next_step() -> void:
	var cam: Camera = _camera({ "follow": { "approval": false, "open": false, "done": false } })
	cam.advance(10.0)
	var step_length: float = float(cam.o["step"])
	# the camera has been quiet on A for a long time, and B gets an event 0.01 s after the last step
	var last: float = float(cam._next_step - 1) * step_length
	cam.feed("activity", "B", 3, last + 0.01)
	cam.advance(last + step_length - 0.0001)
	assert_eq(cam.log.size(), 0, "no step ran yet: the event waits")
	cam.advance(last + step_length)
	assert_eq(cam.log.size(), 1, "the step after the event moves the camera to the busy arena")
	assert_eq(cam.log[0]["why"], "activity")
	assert_eq(cam.log[0]["to"], "B")
	assert_almost_eq(float(cam.log[0]["t"]), last + step_length, 1e-9)


func test_the_pace_holds_a_move_and_the_signal_tells_the_interface() -> void:
	var cam: Camera = _camera({ "pace": 0.1, "follow": { "fail": true, "open": true, "done": true, "join": true } }, ["A", "B", "C", "D"])
	var held_signals: Array[bool] = []
	cam.held_changed.connect(func(value: bool) -> void: held_signals.append(value))
	cam.advance(2.0)
	cam.feed("done", "B", 1, 2.0)
	cam.advance(2.1)
	assert_eq(cam.arena_shown(), "B")
	cam.feed("done", "C", 2, 4.0)
	cam.advance(4.1)
	assert_eq(cam.arena_shown(), "B", "the pace allows one move in 10 s")
	assert_true(cam.held, "the next move waits")
	assert_eq(held_signals, [true])


func test_reduced_motion_makes_each_move_a_short_cut() -> void:
	var cam: Camera = _camera({ "reduced_motion": true })
	cam.click_tab("C", 1.0)
	cam.advance(1.1)
	assert_almost_eq(float(cam.moves[0]["dur"]), 0.15, 1e-9)
	assert_eq(float(cam.moves[0]["peak"]), 0.0)
	cam.advance(1.5)
	assert_false(cam.moving_at(1.5))


func test_the_signals_of_a_move_and_of_a_new_arena_ribbon() -> void:
	var cam: Camera = _camera({ }, ["A"])
	var moved_to: Array[String] = []
	var ribbons: Array[String] = []
	var modes: Array[String] = []
	cam.moved.connect(func(entry: Dictionary) -> void: moved_to.append(str(entry["to"])))
	cam.ribbon_started.connect(func(arena: String, _at: float) -> void: ribbons.append(arena))
	cam.mode_changed.connect(func(mode: String) -> void: modes.append(mode))
	cam.advance(3.0)
	cam.arena_opened("B", 3.0)
	cam.feed("open", "B", 5, 3.0)
	cam.advance(3.1)
	assert_eq(moved_to, ["B"])
	cam.advance(4.0)
	assert_eq(ribbons, ["B"])
	cam.press("F", 4.0)
	cam.advance(4.1)
	assert_eq(modes, ["MANUAL"])


func test_the_long_moves_are_marked_for_the_benchmark() -> void:
	var letters: Array[String] = []
	for i in 40:
		letters.append(ArenaRules.name_of(i))
	var cam: Camera = _camera({ }, letters)
	cam.click_tab("Z", 1.0)
	cam.advance(3.0)
	cam.click_tab("B", 4.0)
	cam.advance(6.0)
	assert_eq(cam.moves.size(), 2)
	assert_eq(cam.moves[0]["kind"], "fly")
	assert_true(cam.moves[0]["wide"], "page 1 to page 7 widens the view to 4 rooms or more")
	assert_eq(cam.moves[1]["kind"], "fly")
	assert_eq(cam.moves[0]["id"], 1)
	assert_eq(cam.moves[1]["id"], 2)
	assert_eq(cam.move_id, 2)


func test_the_log_stays_short_in_a_long_session() -> void:
	var cam: Camera = _camera({ "pace": INF }, ["A", "B"])
	var t: float = 1.0
	for i in 40:
		cam.click_tab("B" if i % 2 == 0 else "A", t)
		cam.advance(t + 0.1)
		t += 1.0
	assert_eq(cam.log.size(), 40)
	assert_lte(cam.log.size(), Camera.LOG_LIMIT)


func test_a_click_on_a_penguin_sets_the_focus_and_holds_it_in_auto() -> void:
	var cam: Camera = _camera({ }, ["A"])
	cam.feed_focus("A", 1, 0.1, false)
	cam.advance(2.0)
	assert_eq(cam.focus_of("A"), 1)
	cam.set_focus("A", 2, 2.1)
	cam.feed_focus("A", 3, 2.2, false)
	cam.advance(2.5)
	assert_eq(cam.focus_of("A"), 2, "the click holds the focus for 1.5 s")
	cam.advance(3.8)
	assert_eq(cam.focus_of("A"), 3, "then the newest event takes it in AUTO")
	cam.press("F", 3.9)
	cam.set_focus("A", 5, 4.0)
	cam.feed_focus("A", 6, 4.1, false)
	cam.advance(8.0)
	assert_eq(cam.focus_of("A"), 5, "in MANUAL the focus stays where the person put it")
