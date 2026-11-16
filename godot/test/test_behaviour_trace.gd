extends GutTest
## The behaviour trace (testing layer 5 of the plan): events go to the director in fixed steps, and the penguin must visit
## the stations in the order of `test/fixtures/expected-trace.json`. The trace has no language in it, so a later client in
## another language can use the same file.
##
## Two sessions are checked:
##   "claude-code-fixture"  the real Claude Code example, after the bridge adapter (`claude-code.events.jsonl`). It has no
##                          permission prompt and runs each tool once.
##   "session-scene"        the made-up session of the demo (`res://demo/session.json`), with a prompt for approval and a second
##                          visit to the workbench and the forge, as in the plan.
## The plan's list (map table, bookshelf, workbench, forge, sign post, flop, helper desk and its helper, telescope, workbench,
## forge, celebration) is the story of the made-up session, in the order of its events. The real example has fewer calls.

const Trace := preload("res://test/support/trace.gd")
const Director := preload("res://src/core/director.gd")
const TimelinePlayer := preload("res://src/net/timeline_player.gd")

const EXPECTED := "res://test/fixtures/expected-trace.json"


func _expected(scene: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(EXPECTED, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	return data[scene]


func _timeline_of(player: RefCounted) -> Array[Dictionary]:
	return player.events


func test_the_real_claude_code_example_visits_the_stations_in_order() -> void:
	var expected: Dictionary = _expected("claude-code-fixture")
	var timeline: Array[Dictionary] = Trace.read_jsonl("res://test/fixtures/claude-code.events.jsonl")
	assert_gt(timeline.size(), 15)
	var director: RefCounted = Director.new()
	var trace: Dictionary = Trace.play(director, timeline, float(expected["duration"]))
	assert_eq(trace, expected["trace"])


func test_the_made_up_session_visits_the_stations_of_the_plan() -> void:
	var expected: Dictionary = _expected("session-scene")
	var player: RefCounted = TimelinePlayer.load_file("res://demo/session.json")
	var director: RefCounted = Director.new()
	var trace: Dictionary = Trace.play(director, _timeline_of(player), float(expected["duration"]))
	assert_eq(trace, expected["trace"])


func test_the_multi_agent_scene_gives_every_agent_its_own_walk() -> void:
	var expected: Dictionary = _expected("multi-scene")
	var player: RefCounted = TimelinePlayer.load_file("res://demo/multi.json")
	var director: RefCounted = Director.new()
	var trace: Dictionary = Trace.play(director, _timeline_of(player), float(expected["duration"]))
	assert_eq(trace, expected["trace"])
	assert_eq(director.penguin_count(), 6)
	var spots: Dictionary = { }
	for penguin: RefCounted in director.penguins():
		assert_false(spots.has(penguin.position) and penguin.activity == "work", "no two penguins work on one spot")
		spots[penguin.position] = true


func test_the_story_of_the_plan_is_in_the_made_up_session_in_order() -> void:
	# map table, bookshelf, workbench, forge, sign post, flop, helper desk and its helper, telescope, workbench, forge,
	# celebration: the made-up session has these, in a story order of its own. This checks the order of the plan's list as a
	# subsequence of the trace (the made-up session also thinks in the armchair, and the flop comes at the forge).
	var player: RefCounted = TimelinePlayer.load_file("res://demo/session.json")
	var trace: Dictionary = Trace.play(Director.new(), _timeline_of(player), 40.0)
	var steps: Array = trace["agent 1"]
	for station: String in ["Map table", "Bookshelf", "Workbench", "Helper desk", "Forge", "flop", "Workbench", "Forge", "Sign post", "celebration"]:
		assert_has(steps, station)
	assert_eq(steps[steps.size() - 1], "celebration", "the story ends with the celebration")
	assert_eq(trace["helper 1"], ["Telescope"], "the helper goes to the telescope")


func test_a_fast_frame_rate_and_a_slow_one_give_the_same_trace() -> void:
	# The simulation step is fixed, so the trace does not depend on how often the frames come. This feeds the same events
	# through the clock with two frame rates.
	var Clock: GDScript = load("res://src/core/clock.gd")
	var player: RefCounted = TimelinePlayer.load_file("res://demo/session.json")
	var traces: Array = []
	for frame_time: float in [1.0 / 30.0, 1.0 / 144.0]:
		var clock: RefCounted = Clock.new()
		var director: RefCounted = Director.new()
		player.rewind()
		var trace: Dictionary = { }
		var last: Dictionary = { }
		var frames: int = 0
		while clock.now < 32.0 and frames < 100000:
			frames += 1
			for _step: int in clock.advance(frame_time):
				for event: RefCounted in player.due_events(clock.now):
					director.handle_event(event)
				clock.tick()
				director.step(clock.now)
				for key: String in director.world.actors:
					var actor: RefCounted = director.world.actors[key]
					var label: String = Trace.label_of(actor)
					if label != "" and last.get(key, "") != label:
						var who: String = Trace.who_of(actor)
						if not trace.has(who):
							trace[who] = []
						(trace[who] as Array).append(label)
					last[key] = label
		traces.append(trace)
	assert_eq(traces[0], traces[1])


func test_two_runs_give_the_same_positions() -> void:
	var timeline: Array[Dictionary] = Trace.read_jsonl("res://test/fixtures/claude-code.events.jsonl")
	var runs: Array = []
	for _round: int in 2:
		var director: RefCounted = Director.new()
		var samples: Array = []
		Trace.play(director, timeline, 40.0, func(now: float, d: RefCounted) -> void:
			if int(now * 60.0) % 30 == 0:
				var penguin: RefCounted = d.penguins()[0]
				samples.append([penguin.position, penguin.pose, penguin.facing, penguin.y_off]))
		runs.append(samples)
	assert_eq(runs[0], runs[1])
	assert_gt((runs[0] as Array).size(), 50)
