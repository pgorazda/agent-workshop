extends GutTest
## The penguin actor, stepped with the clock and no frames: a tool call walks to the right station and takes its pose, a failure
## flops, a queue makes it hurry, thinking, approvals, a celebration, spots and lines, and the way back to the rest point.

const Director := preload("res://src/core/director.gd")
const Clock := preload("res://src/core/clock.gd")
const Stations := preload("res://src/core/stations.gd")
const PenguinActor := preload("res://src/core/penguin_actor.gd")
const Data := preload("res://art/atlas_data.gd")
const Trace := preload("res://test/support/trace.gd")

var director: RefCounted
var clock: RefCounted


func before_each() -> void:
	director = Director.new()
	clock = Clock.new()


## Makes a penguin that has popped in and stands idle.
func _penguin(agent: String = "main") -> RefCounted:
	director.handle_event(Trace.ev("session_start", { }, agent))
	Trace.run(director, clock, 1.0)
	return director.actor_of(Director.key_of("claude-code", "s1", agent))


func _work_at(actor: RefCounted) -> bool:
	return actor.activity == "work" and actor.station != ""


func test_a_tool_call_walks_to_its_station_and_takes_the_pose() -> void:
	# category -> [station spot, the poses of the animation, the facing]
	var table: Dictionary = {
		"read": ["shelf", ["read", "read2"], "left"],
		"search": ["map", ["browse", "browse2"], "right"],
		"write": ["benchL", ["hammer", "hammer2"], "back"],
		"exec": ["forge", ["shovel", "shovel2"], "right"],
		"web": ["scope", ["peer"], "right"],
		"delegate": ["desk", ["tap", "tap2"], "right"],
		"ask_permission": ["sign", ["waveL", "waveL2"], "front"],
		"other": ["odd", ["hammer", "hammer2"], "left"],
	}
	for category: String in table:
		var local_director: RefCounted = Director.new()
		var local_clock: RefCounted = Clock.new()
		local_director.handle_event(Trace.tool_start(category))
		var penguin: RefCounted = local_director.penguins()[0]
		var arrived: bool = Trace.run_until(local_director, local_clock, func() -> bool: return _work_at(penguin))
		assert_true(arrived, "%s: the penguin arrives" % category)
		var expected: Array = table[category]
		assert_eq(Vector2i(penguin.position), Stations.point(expected[0]), "%s: it stands on the spot %s" % [category, expected[0]])
		assert_has(expected[1], penguin.pose, "%s: a pose of the animation" % category)
		assert_eq(penguin.facing, expected[2], "%s: the facing" % category)
		assert_eq(penguin.station, category)


func test_a_tool_call_works_until_its_end_arrives() -> void:
	director.handle_event(Trace.tool_start("exec", "make"))
	var penguin: RefCounted = director.penguins()[0]
	Trace.run_until(director, clock, func() -> bool: return _work_at(penguin))
	Trace.run(director, clock, 6.0)
	assert_eq(penguin.activity, "work", "the call is open: it keeps working")
	assert_eq(penguin.status, "run")
	director.handle_event(Trace.tool_end(true))
	Trace.run(director, clock, 0.2)
	assert_ne(penguin.activity, "work")
	assert_eq(penguin.status, "OK")


func test_a_call_that_ends_early_still_works_for_a_moment() -> void:
	director.handle_event(Trace.tool_start("read"))
	director.handle_event(Trace.tool_end(true))
	var penguin: RefCounted = director.penguins()[0]
	var arrived: bool = Trace.run_until(director, clock, func() -> bool: return _work_at(penguin))
	assert_true(arrived, "it walks to the bookshelf even though the end is in the queue")
	var arrived_at: float = clock.now
	Trace.run_until(director, clock, func() -> bool: return penguin.activity != "work")
	assert_gte(clock.now - arrived_at, PenguinActor.MIN_WORK - 0.05, "it works at least MIN_WORK")


func test_a_failed_call_flops_for_one_point_eight_seconds() -> void:
	var penguin: RefCounted = _penguin()
	director.handle_event(Trace.tool_start("exec", "make test"))
	Trace.run_until(director, clock, func() -> bool: return _work_at(penguin))
	director.handle_event(Trace.tool_end(false))
	Trace.run_until(director, clock, func() -> bool: return penguin.activity == "flop")
	assert_eq(penguin.activity, "flop")
	assert_eq(penguin.status, "FAIL")
	var flop_start: float = clock.now
	assert_lt(penguin.flop_age, 0.1)
	Trace.run_until(director, clock, func() -> bool: return penguin.activity != "flop")
	assert_almost_eq(clock.now - flop_start, PenguinActor.FLOP_TIME, 0.05)
	assert_eq(penguin.flop_age, -1.0)


func test_a_penguin_that_lies_after_a_failure_keeps_its_spot_until_it_gets_up() -> void:
	# the next penguin of the line must not stand on the one that lies there
	var first: RefCounted = _penguin("a")
	var second: RefCounted = _penguin("b")
	director.handle_event(Trace.tool_start("exec", "make test", "c1", "a"))
	Trace.run_until(director, clock, func() -> bool: return _work_at(first))
	var spot: Vector2 = first.position
	director.handle_event(Trace.tool_end(false, "c1", "a"))
	Trace.run_until(director, clock, func() -> bool: return first.activity == "flop")
	assert_true(director.world.spots.has(first.key), "it keeps its spot while it lies there")
	director.handle_event(Trace.tool_start("exec", "make lint", "c2", "b"))
	var shared: int = 0
	var seconds: float = 0.0
	while seconds < PenguinActor.FLOP_TIME - 0.2:
		Trace.run(director, clock, 0.1)
		seconds += 0.1
		if first.activity == "flop" and _work_at(second) and second.position.distance_to(spot) < 1.5:
			shared += 1
	assert_eq(shared, 0, "no penguin works on the spot of the one that lies there")
	Trace.run_until(director, clock, func() -> bool: return first.activity != "flop")
	assert_false(director.world.spots.has(first.key), "and lets it go when it has got up")
	Trace.run_until(director, clock, func() -> bool: return _work_at(second))
	assert_true(_work_at(second), "the second penguin works there once the first has got up")


func test_the_spot_at_the_sign_post_stays_taken_for_the_cheer_of_an_answer() -> void:
	var first: RefCounted = _penguin("a")
	director.handle_event(Trace.ev("waiting_permission", { "target": "git push" }, "a"))
	Trace.run_until(director, clock, func() -> bool: return first.activity == "wait", 20.0)
	assert_eq(first.activity, "wait")
	var post: RefCounted = director.world.spots
	assert_true(post.has(first.key), "the penguin holds the spot at the sign post")
	director.handle_event(Trace.tool_end(true, "c1", "a"))
	Trace.run_until(director, clock, func() -> bool: return first.activity == "approve", 20.0)
	assert_eq(first.activity, "approve", "the small cheer of the answer")
	assert_true(post.has(first.key), "it still holds the spot during the cheer")
	Trace.run_until(director, clock, func() -> bool: return first.activity != "approve", 5.0)
	assert_false(post.has(first.key), "and lets it go when the cheer is over")


func test_a_flop_shakes_the_room_and_a_failed_run_at_the_forge_makes_smoke() -> void:
	var penguin: RefCounted = _penguin()
	director.handle_event(Trace.tool_start("exec", "make test"))
	Trace.run_until(director, clock, func() -> bool: return _work_at(penguin))
	director.handle_event(Trace.tool_end(false))
	Trace.run_until(director, clock, func() -> bool: return penguin.activity == "flop")
	assert_eq(director.world.effects.count_of("smoke"), 1)
	Trace.run(director, clock, 0.05)
	var offsets: Array = []
	for i in 10:
		Trace.run(director, clock, 0.02)
		offsets.append(director.world.effects.shake_offset(clock.now))
	assert_true(offsets.any(func(offset: int) -> bool: return offset != 0), "the room moves")


func test_a_failed_call_at_another_station_makes_no_smoke() -> void:
	var penguin: RefCounted = _penguin()
	director.handle_event(Trace.tool_start("read"))
	Trace.run_until(director, clock, func() -> bool: return _work_at(penguin))
	director.handle_event(Trace.tool_end(false))
	Trace.run_until(director, clock, func() -> bool: return penguin.activity == "flop")
	assert_eq(director.world.effects.count_of("smoke"), 0)


func test_a_queue_makes_it_hurry() -> void:
	var penguin: RefCounted = _penguin()
	assert_eq(penguin.hurry(), 1.0)
	penguin.queue.append(Trace.tool_end())
	assert_eq(penguin.hurry(), 1.0, "one event waiting is normal")
	penguin.queue.append(Trace.tool_end())
	penguin.queue.append(Trace.tool_end())
	assert_almost_eq(penguin.hurry(), 2.0, 1e-9)
	for i in 30:
		penguin.queue.append(Trace.tool_end())
	assert_eq(penguin.hurry(), PenguinActor.HURRY_MAX, "the hurry has a top")


func test_a_penguin_with_a_queue_is_faster_than_one_without() -> void:
	# The same four calls: one penguin gets them one by one, when it is ready; the other gets them all at once.
	var slow_director: RefCounted = Director.new()
	var slow_clock: RefCounted = Clock.new()
	var fast_director: RefCounted = Director.new()
	var fast_clock: RefCounted = Clock.new()
	var categories: Array[String] = ["search", "read", "write", "exec"]
	for category in categories:
		fast_director.handle_event(Trace.tool_start(category, "x", category))
		fast_director.handle_event(Trace.tool_end(true, category))
	var fast: RefCounted = fast_director.penguins()[0]
	var fast_done: bool = Trace.run_until(fast_director, fast_clock, func() -> bool: return fast.queue.is_empty() and not fast.has_call() and fast.activity == "idle", 60.0)
	assert_true(fast_done)
	# without a queue: the next call starts when the one before has ended
	var slow: RefCounted = null
	var slow_total: float = 0.0
	for category in categories:
		slow_director.handle_event(Trace.tool_start(category, "x", category))
		slow_director.handle_event(Trace.tool_end(true, category))
		slow = slow_director.penguins()[0]
		Trace.run_until(slow_director, slow_clock, func() -> bool: return slow.queue.is_empty() and not slow.has_call() and slow.activity == "idle" and slow.current_segment().get("age", 0.0) > 0.0, 60.0)
	slow_total = slow_clock.now
	assert_lt(fast_clock.now, slow_total, "with a queue the penguin hurries")


func test_thinking_goes_to_the_armchair_when_it_is_free() -> void:
	director.handle_event(Trace.ev("thinking"))
	var penguin: RefCounted = director.penguins()[0]
	var seated: bool = Trace.run_until(director, clock, func() -> bool: return penguin.activity == "sit")
	assert_true(seated)
	assert_eq(Vector2i(penguin.position), Stations.point("seat"))
	assert_eq(penguin.pose, "think")
	assert_eq(penguin.shadow, 0, "a seated penguin has no shadow")
	Trace.run(director, clock, 0.5)
	assert_gt(penguin.think_age, 0.4)
	assert_false(penguin.think_in_place)


func test_thinking_where_it_stands_when_the_armchair_is_taken() -> void:
	director.handle_event(Trace.ev("thinking", { }, "first"))
	var first: RefCounted = director.actor_of(Director.key_of("claude-code", "s1", "first"))
	Trace.run_until(director, clock, func() -> bool: return first.activity == "sit")
	director.handle_event(Trace.ev("thinking", { }, "second"))
	var second: RefCounted = director.actor_of(Director.key_of("claude-code", "s1", "second"))
	var started: bool = Trace.run_until(director, clock, func() -> bool: return second.activity == "think")
	assert_true(started, "the second one thinks where it stands")
	assert_true(second.think_in_place)
	assert_eq(second.pose, "think")
	var spot: Vector2 = second.position
	Trace.run(director, clock, 2.0)
	assert_eq(second.position, spot, "it did not move")
	assert_eq(first.activity, "sit", "the first one still sits")


func test_the_armchair_is_free_again_when_the_sitter_leaves() -> void:
	director.handle_event(Trace.ev("thinking", { }, "first"))
	var first: RefCounted = director.actor_of(Director.key_of("claude-code", "s1", "first"))
	Trace.run_until(director, clock, func() -> bool: return first.activity == "sit")
	director.handle_event(Trace.tool_start("read", "x", "c1", "first"))
	Trace.run_until(director, clock, func() -> bool: return _work_at(first))
	director.handle_event(Trace.ev("thinking", { }, "second"))
	var second: RefCounted = director.actor_of(Director.key_of("claude-code", "s1", "second"))
	var seated: bool = Trace.run_until(director, clock, func() -> bool: return second.activity == "sit")
	assert_true(seated, "the second penguin takes the armchair")


func test_a_sitter_hops_down_before_it_goes_on() -> void:
	director.handle_event(Trace.ev("thinking"))
	var penguin: RefCounted = director.penguins()[0]
	Trace.run_until(director, clock, func() -> bool: return penguin.activity == "sit")
	director.handle_event(Trace.tool_start("read"))
	var hopped: bool = Trace.run_until(director, clock, func() -> bool: return penguin.activity == "hop")
	assert_true(hopped)
	assert_true(penguin.y_off < 0 or penguin.position.y > Stations.point("seat").y - 1, "it hops down in front of the chair")


func test_waiting_permission_goes_to_the_sign_post_and_the_next_event_ends_the_wait() -> void:
	director.handle_event(Trace.tool_start("exec", "git push"))
	director.handle_event(Trace.ev("waiting_permission", {"message": "ok?"}))
	var penguin: RefCounted = director.penguins()[0]
	var waiting: bool = Trace.run_until(director, clock, func() -> bool: return penguin.activity == "wait")
	assert_true(waiting)
	assert_eq(Vector2i(penguin.position), Stations.point("sign"))
	assert_eq(penguin.status, "WAIT")
	assert_true(penguin.is_asking())
	Trace.run(director, clock, 5.0)
	assert_eq(penguin.activity, "wait", "it waits for as long as nothing comes")
	director.handle_event(Trace.tool_end(true))
	var approved: bool = Trace.run_until(director, clock, func() -> bool: return penguin.activity == "approve")
	assert_true(approved, "an answer shows as a small cheer")
	Trace.run_until(director, clock, func() -> bool: return penguin.activity == "idle")
	assert_false(penguin.has_call(), "the call is closed")
	assert_eq(penguin.status, "OK")


func test_the_prompt_takes_the_penguin_before_it_reaches_the_forge() -> void:
	director.handle_event(Trace.tool_start("exec", "git push"))
	director.handle_event(Trace.ev("waiting_permission"))
	var penguin: RefCounted = director.penguins()[0]
	var visited: Array[String] = []
	Trace.run_until(director, clock, func() -> bool:
		if penguin.station != "" and (visited.is_empty() or visited[visited.size() - 1] != penguin.station):
			visited.append(penguin.station)
		return penguin.activity == "wait")
	assert_eq(visited, ["ask_permission"], "it never went to the forge")


func test_a_second_prompt_while_waiting_changes_nothing() -> void:
	director.handle_event(Trace.ev("waiting_permission"))
	var penguin: RefCounted = director.penguins()[0]
	Trace.run_until(director, clock, func() -> bool: return penguin.activity == "wait")
	director.handle_event(Trace.ev("waiting_permission"))
	Trace.run(director, clock, 2.0)
	assert_eq(penguin.activity, "wait")
	assert_eq(penguin.queue.size(), 0)


func test_a_failure_after_an_approval_flops_at_the_sign_post() -> void:
	director.handle_event(Trace.tool_start("exec", "rm"))
	director.handle_event(Trace.ev("waiting_permission"))
	var penguin: RefCounted = director.penguins()[0]
	Trace.run_until(director, clock, func() -> bool: return penguin.activity == "wait")
	director.handle_event(Trace.tool_end(false))
	var flopped: bool = Trace.run_until(director, clock, func() -> bool: return penguin.activity == "flop")
	assert_true(flopped)
	assert_eq(Vector2i(penguin.position), Stations.point("sign"))


func test_done_walks_to_the_stage_and_celebrates() -> void:
	var penguin: RefCounted = _penguin()
	director.handle_event(Trace.ev("done"))
	var cheering: bool = Trace.run_until(director, clock, func() -> bool: return penguin.activity == "cheer")
	assert_true(cheering)
	assert_eq(Vector2i(penguin.position), Stations.point("stage"))
	assert_eq(penguin.status, "DONE")
	assert_eq(director.world.effects.count_of("confetti"), 1)
	assert_eq(director.world.effects.count_of("sparkle"), PenguinActor.SPARKLES.size())
	var started: float = clock.now
	Trace.run_until(director, clock, func() -> bool: return penguin.activity != "cheer")
	assert_almost_eq(clock.now - started, PenguinActor.CHEER_TIME, 0.1)


func test_an_unknown_event_type_is_generic_work_at_the_odd_jobs_station() -> void:
	var penguin: RefCounted = _penguin()
	director.handle_event(Trace.ev("something_from_the_future"))
	var working: bool = Trace.run_until(director, clock, func() -> bool: return _work_at(penguin))
	assert_true(working)
	assert_eq(Vector2i(penguin.position), Stations.point("odd"))
	assert_eq(penguin.station, "other")
	var started: float = clock.now
	Trace.run_until(director, clock, func() -> bool: return penguin.activity != "work")
	assert_almost_eq(clock.now - started, PenguinActor.GENERIC_WORK_TIME, 0.1, "generic work ends by itself")
	assert_false(penguin.has_call())


func test_an_error_event_flops_where_the_penguin_stands() -> void:
	var penguin: RefCounted = _penguin()
	var here: Vector2 = penguin.position
	director.handle_event(Trace.ev("error", {"error": "boom"}))
	var flopped: bool = Trace.run_until(director, clock, func() -> bool: return penguin.activity == "flop")
	assert_true(flopped)
	assert_eq(penguin.position, here)


func test_a_tool_end_of_a_call_that_was_left_is_ignored_unless_it_failed() -> void:
	var penguin: RefCounted = _penguin()
	director.handle_event(Trace.tool_end(true, "ghost"))
	Trace.run(director, clock, 0.5)
	assert_eq(penguin.activity, "idle")
	director.handle_event(Trace.tool_end(false, "ghost"))
	var flopped: bool = Trace.run_until(director, clock, func() -> bool: return penguin.activity == "flop")
	assert_true(flopped)


func test_a_full_station_gives_a_line_and_the_spot_is_given_on() -> void:
	# The workbench has two spots. The third writer waits in the line.
	var actors: Array[RefCounted] = []
	for i in 3:
		director.handle_event(Trace.tool_start("write", "f%d" % i, "w%d" % i, "a%d" % i))
		actors.append(director.actor_of(Director.key_of("claude-code", "s1", "a%d" % i)))
	var third: RefCounted = actors[2]
	var queued: bool = Trace.run_until(director, clock, func() -> bool: return third.activity == "queue")
	assert_true(queued, "the third penguin waits in the line")
	assert_eq(Vector2i(third.position), Stations.queue_place(Stations.for_category("write"), 0))
	assert_eq(third.status, "run", "its card still shows the call as running")
	director.handle_event(Trace.tool_end(true, "w0", "a0"))
	var got_spot: bool = Trace.run_until(director, clock, func() -> bool: return _work_at(third))
	assert_true(got_spot, "when a spot is free the first one in the line walks to it")
	assert_eq(Vector2i(third.position), Stations.point("benchL"))


func test_a_penguin_that_has_nothing_to_do_walks_to_its_rest_point() -> void:
	director.handle_event(Trace.tool_start("read"))
	director.handle_event(Trace.tool_end(true))
	var penguin: RefCounted = director.penguins()[0]
	var rest: Vector2 = penguin.rest_point
	Trace.run_until(director, clock, func() -> bool: return _work_at(penguin))
	Trace.run(director, clock, 10.0)
	assert_lt(penguin.position.distance_to(rest), 2.0, "after a while it stands at its rest point")
	assert_eq(penguin.activity, "idle")


func test_a_new_event_cuts_the_walk_to_the_rest_point() -> void:
	director.handle_event(Trace.tool_start("read"))
	director.handle_event(Trace.tool_end(true))
	var penguin: RefCounted = director.penguins()[0]
	Trace.run_until(director, clock, func() -> bool: return _work_at(penguin))
	Trace.run_until(director, clock, func() -> bool: return penguin.activity == "walk" and penguin.current_segment().get("interrupt", false))
	director.handle_event(Trace.tool_start("search"))
	var arrived: bool = Trace.run_until(director, clock, func() -> bool: return _work_at(penguin) and penguin.station == "search")
	assert_true(arrived)


func test_walking_looks_the_way_it_goes() -> void:
	director.handle_event(Trace.tool_start("read"))
	var penguin: RefCounted = director.penguins()[0]
	var facings: Dictionary = { }
	Trace.run_until(director, clock, func() -> bool:
		if penguin.activity == "walk":
			facings[penguin.facing] = true
			assert_true(penguin.pose == "walk" or penguin.pose == "walk2")
		return _work_at(penguin))
	assert_true(facings.has("left"), "the shelf is to the left of the rug: the penguin walks left")


func test_a_penguin_pops_in_hidden_at_first() -> void:
	director.handle_event(Trace.ev("session_start"))
	var penguin: RefCounted = director.penguins()[0]
	Trace.run(director, clock, 0.05)
	assert_true(penguin.hidden)
	assert_eq(director.world.effects.count_of("puff"), 1)
	Trace.run(director, clock, 0.2)
	assert_false(penguin.hidden)


func test_the_cord_and_the_number_do_not_change() -> void:
	var penguin: RefCounted = _penguin()
	var cord: String = penguin.cord
	director.handle_event(Trace.tool_start("write"))
	Trace.run(director, clock, 3.0)
	assert_eq(penguin.cord, cord)
	assert_eq(penguin.number, 1)


func test_every_pose_it_takes_exists_in_the_atlas() -> void:
	# one call in each category, then a flop, a celebration and thinking: each pose and facing must be baked
	var penguin: RefCounted = _penguin()
	var poses: Dictionary = { }
	var categories: Array = Array(Stations.TABLE.map(func(station: Dictionary) -> String: return station["category"]))
	var queue_events: Array = []
	for category: String in categories:
		queue_events.append(Trace.tool_start(category, "x", category))
		queue_events.append(Trace.tool_end(true, category))
	queue_events.append(Trace.ev("thinking"))
	queue_events.append(Trace.ev("done"))
	for event: RefCounted in queue_events:
		director.handle_event(event)
	var end: float = clock.now + 90.0
	while clock.now < end and not (penguin.queue.is_empty() and penguin.activity == "idle" and penguin.status == "DONE"):
		clock.tick()
		director.step(clock.now)
		var dir: String = "front" if penguin.facing == "front" else ("back" if penguin.facing == "back" else "side")
		poses["penguin/%s/%s/%s" % [penguin.cord, dir, penguin.pose]] = true
	assert_gt(poses.size(), 12)
	for picture: String in poses:
		assert_true(Data.PICTURES.has(picture), "baked: %s" % picture)


func test_two_penguins_that_finish_a_turn_do_not_celebrate_on_one_point() -> void:
	director.handle_event(Trace.ev("done", { }, "a"))
	director.handle_event(Trace.ev("done", { }, "b"))
	var first: RefCounted = director.actor_of(Director.key_of("claude-code", "s1", "a"))
	var second: RefCounted = director.actor_of(Director.key_of("claude-code", "s1", "b"))
	var both: bool = Trace.run_until(director, clock, func() -> bool: return first.activity == "cheer" and second.activity == "cheer")
	assert_true(both)
	assert_ne(first.position, second.position)
	assert_eq(Vector2i(first.position), Stations.point("stage"))
