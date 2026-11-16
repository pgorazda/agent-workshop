extends GutTest
## The cost of the simulation alone, with no screen (plan, "Performance", item 5): 157 agents, each with a call at a station.
## It prints the time of a step and fails above a generous limit, so that a slow simulation shows on any machine.

const Director := preload("res://src/core/director.gd")
const Clock := preload("res://src/core/clock.gd")
const Trace := preload("res://test/support/trace.gd")
const Camera := preload("res://src/core/camera.gd")
const TimelinePlayer := preload("res://src/net/timeline_player.gd")

## The limit of the plan: 10 ms for one step of 1/60 s.
const LIMIT_MS := 10.0


func test_a_step_of_157_agents_stays_under_the_limit() -> void:
	var director: RefCounted = Director.new()
	director.limit = 200
	var categories: Array[String] = ["read", "search", "write", "exec", "web", "delegate", "think", "ask_permission", "other"]
	for i in 157:
		var agent: String = "a%d" % i
		director.handle_event(Trace.tool_start(categories[i % categories.size()], "t%d" % i, "c%d" % i, agent))
	var clock: RefCounted = Clock.new()
	var steps: int = 600
	var started: int = Time.get_ticks_usec()
	for _step in steps:
		clock.tick()
		director.step(clock.now)
	var per_step_ms: float = float(Time.get_ticks_usec() - started) / 1000.0 / float(steps)
	gut.p("157 agents: %.3f ms for one step (limit %.0f ms)" % [per_step_ms, LIMIT_MS])
	assert_eq(director.penguin_count(), 157)
	assert_lt(per_step_ms, LIMIT_MS)


## The same agents in 40 arenas, with the camera attached and the rules of the arenas running (phase G-5).
func test_a_step_of_157_agents_in_40_arenas_with_the_camera_stays_under_the_limit() -> void:
	var director: RefCounted = Director.new()
	director.limit = 200
	director.set_arena_size(4)
	director.leave_after = 600.0
	var camera: Camera = Camera.new()
	director.attach_camera(camera)
	var categories: Array[String] = ["read", "search", "write", "exec", "web", "delegate", "think", "ask_permission", "other"]
	for i in 157:
		director.handle_event(Trace.tool_start(categories[i % categories.size()], "t%d" % i, "c%d" % i, "a%d" % i))
	var clock: RefCounted = Clock.new()
	var steps: int = 600
	var started: int = Time.get_ticks_usec()
	for _step in steps:
		clock.tick()
		director.step(clock.now)
		camera.advance(clock.now)
	var per_step_ms: float = float(Time.get_ticks_usec() - started) / 1000.0 / float(steps)
	gut.p("157 agents in %d arenas with the camera: %.3f ms for one step (limit %.0f ms)" % [director.letters().size(), per_step_ms, LIMIT_MS])
	print("simulation cost: 157 agents in %d arenas with the camera: %.3f ms for one step (limit %.0f ms)" % [director.letters().size(), per_step_ms, LIMIT_MS])
	assert_eq(director.penguin_count(), 157)
	assert_eq(director.letters().size(), 40)
	assert_lt(per_step_ms, LIMIT_MS)


## The real scene `ten`, played from its timeline with no screen: the events, the director and the camera, step by step.
func test_the_ten_scene_stays_under_the_limit_for_every_step() -> void:
	var player: RefCounted = TimelinePlayer.load_file("res://demo/ten.json")
	assert_not_null(player)
	var director: RefCounted = Director.new()
	director.limit = 200
	director.set_arena_size(int(player.options.get("arena_size", 4)))
	director.leave_after = 600.0
	var camera: Camera = Camera.new()
	director.attach_camera(camera)
	var clock: RefCounted = Clock.new()
	clock.reset(player.start_time())
	director.sync_time(clock.now)
	var worst_ms: float = 0.0
	var worst_before_ms: float = 0.0
	var spent_after: Array[float] = []
	var total_ms: float = 0.0
	var steps: int = 0
	while clock.now < player.duration:
		var before_zero: bool = clock.now < 0.0
		var started: int = Time.get_ticks_usec()
		for event: RefCounted in player.due_events(clock.now):
			director.handle_event(event)
		for input: Dictionary in player.due_inputs(clock.now):
			var entry: Dictionary = input.duplicate()
			entry.erase("t")
			camera.input(entry, clock.now)
		clock.tick()
		director.step(clock.now)
		camera.advance(clock.now)
		var spent: float = float(Time.get_ticks_usec() - started) / 1000.0
		if before_zero:
			worst_before_ms = maxf(worst_before_ms, spent)
		else:
			worst_ms = maxf(worst_ms, spent)
			spent_after.append(spent)
		total_ms += spent
		steps += 1
	spent_after.sort()
	var p99_ms: float = spent_after[int(float(spent_after.size()) * 0.99)]
	print("simulation cost: the scene ten, %d steps: %.3f ms a step on average, %.3f ms at the 99th percentile and %.3f ms the worst step after time 0 (limit %.0f ms), %.3f ms the worst step of the 3 s before it, when the 150 agents arrive" % [steps, total_ms / float(steps), p99_ms, worst_ms, LIMIT_MS, worst_before_ms])
	assert_eq(director.penguin_count(), 157)
	# The gate is the 99th percentile: one step can be slow for a reason that is not the simulation (a pause of the machine).
	assert_lt(p99_ms, LIMIT_MS)
