extends GutTest
## The director with arenas: who goes to which arena, helpers, leaving, closing, the penguin limit, and what the
## camera is told. The rules are in docs/arenas.md ("What an arena is").

const Director := preload("res://src/core/director.gd")
const Camera := preload("res://src/core/camera.gd")
const Clock := preload("res://src/core/clock.gd")
const PenguinActor := preload("res://src/core/penguin_actor.gd")
const Trace := preload("res://test/support/trace.gd")

var director: RefCounted
var clock: RefCounted


func before_each() -> void:
	director = Director.new()
	clock = Clock.new()


func _agent(n: int, type: String = "thinking", extra: Dictionary = { }) -> void:
	director.handle_event(Trace.ev(type, extra, "main", "claude-code", "s%d" % n))


func test_a_director_on_its_own_has_one_room() -> void:
	for n in 9:
		_agent(n + 1)
	assert_eq(director.letters(), ["A"] as Array[String])
	assert_eq(director.rooms.size(), 1)
	assert_eq(director.penguin_count(), 9)


func test_an_arena_holds_arena_size_agents_and_a_new_one_opens() -> void:
	director.set_arena_size(2)
	for n in 5:
		_agent(n + 1)
	assert_eq(director.letters(), ["A", "B", "C"] as Array[String])
	assert_eq(director.agent_count_in("A"), 2)
	assert_eq(director.agent_count_in("B"), 2)
	assert_eq(director.agent_count_in("C"), 1)
	var arenas: Array = []
	for penguin: RefCounted in director.penguins():
		arenas.append(penguin.arena)
	assert_eq(arenas, ["A", "A", "B", "B", "C"])
	assert_eq(director.rooms.size(), 3, "each arena has its own world")
	assert_eq((director.rooms["B"] as RefCounted).actors.size(), 2)


func test_the_worlds_do_not_share_spots() -> void:
	director.set_arena_size(1)
	_agent(1, "tool_start", { "category": "read", "id": "c1", "tool": "Read", "target": "a" })
	_agent(2, "tool_start", { "category": "read", "id": "c2", "tool": "Read", "target": "b" })
	Trace.run(director, clock, 4.0)
	var first: RefCounted = director.penguin_with_number(1)
	var second: RefCounted = director.penguin_with_number(2)
	assert_ne(first.arena, second.arena)
	assert_eq(first.position, second.position, "two penguins in different arenas stand on the same spot")
	assert_eq(first.activity, "work")
	assert_eq(second.activity, "work")


func test_a_helper_stays_in_the_arena_of_its_parent_and_does_not_count() -> void:
	director.set_arena_size(2)
	_agent(1)
	_agent(2)
	director.handle_event(Trace.ev("subagent_start", { "id": "sub1" }, "main", "claude-code", "s1"))
	assert_eq(director.helpers().size(), 1)
	assert_eq(director.agent_count_in("A"), 2, "the helper is not an agent of the arena")
	_agent(3)
	assert_eq(director.letters(), ["A", "B"] as Array[String], "a third agent goes to B: the helper did not take a place")
	var helper: RefCounted = director.helpers()[0]
	assert_eq(helper.arena, "A")
	assert_eq(director.actors_in("A").size(), 3, "two penguins and the helper")
	assert_eq(director.actors_in("B").size(), 1)


func test_an_agent_never_changes_arena_while_it_is_present() -> void:
	director.set_arena_size(2)
	for n in 4:
		_agent(n + 1)
	var before: Array = []
	for penguin: RefCounted in director.penguins():
		before.append(penguin.arena)
	for n in 4:
		_agent(n + 1, "thinking")
	var after: Array = []
	for penguin: RefCounted in director.penguins():
		after.append(penguin.arena)
	assert_eq(after, before)


func test_the_limit_on_penguins_holds_for_all_arenas() -> void:
	director.set_arena_size(2)
	director.limit = 3
	for n in 5:
		_agent(n + 1)
	assert_eq(director.penguin_count(), 3)
	assert_eq(director.dropped_agents, 2, "the agents over the limit have no penguin")


func test_the_first_penguin_of_a_new_arena_pops_in_a_little_later() -> void:
	director.set_arena_size(1)
	director.sync_time(10.0)
	_agent(1)
	_agent(2)
	var first: RefCounted = director.penguin_with_number(1)
	var second: RefCounted = director.penguin_with_number(2)
	assert_eq(first.current_segment()["kind"], "pop", "the first arena is open already: no delay")
	assert_eq(second.current_segment()["kind"], "hidden", "arena B opens now: its penguin pops in later")
	assert_almost_eq(float(second.current_segment()["dur"]), director.new_penguin_delay, 1e-9)
	Trace.run(director, clock, 0.4)
	var view: Variant = second.hidden
	assert_true(view, "still hidden after 0.4 s")
	Trace.run(director, clock, 0.4)
	assert_eq(second.current_segment()["kind"], "pop", "it pops in after 0.6 s")


func test_no_delay_for_the_agents_that_were_there_before_time_zero() -> void:
	director.set_arena_size(1)
	director.sync_time(-3.0)
	_agent(1)
	_agent(2)
	assert_eq(director.penguin_with_number(2).current_segment()["kind"], "pop")


func test_an_agent_leaves_after_leave_after_seconds_and_its_place_is_freed() -> void:
	director.set_arena_size(2)
	director.leave_after = 30.0
	_agent(1)
	_agent(2)
	_agent(3)
	assert_eq(director.letters(), ["A", "B"] as Array[String])
	Trace.run(director, clock, 20.0)
	_agent(2) # agent 2 is not quiet
	Trace.run(director, clock, 15.0)
	assert_eq(director.penguin_count(), 1, "agents 1 and 3 left after 30 s; agent 2 had an event 15 s ago")
	assert_eq(director.penguin_with_number(2).arena, "A")
	assert_eq(director.left_count, 2)
	# the place is free: a new agent goes to A, not to a new arena
	_agent(4)
	assert_eq(director.penguin_with_number(4).arena, "A")


func test_a_leaving_penguin_walks_out_through_the_door_and_is_gone() -> void:
	director.leave_after = 5.0
	_agent(1)
	Trace.run(director, clock, 5.6)
	var leaving: RefCounted = null
	for actor: RefCounted in director.actors_in("A"):
		if actor.leaving:
			leaving = actor
	assert_not_null(leaving, "it walks out")
	assert_eq(director.penguin_count(), 0, "it no longer counts")
	assert_eq(leaving.activity, "walk")
	var gone: bool = Trace.run_until(director, clock, func() -> bool: return director.actors_in("A").is_empty(), 6.0)
	assert_true(gone, "it is out of sight and removed")


func test_an_agent_with_an_open_call_or_an_approval_does_not_leave() -> void:
	director.leave_after = 10.0
	director.handle_event(Trace.tool_start("exec", "make", "c1", "main", "claude-code", "build"))
	director.handle_event(Trace.ev("waiting_permission", { }, "main", "claude-code", "ask"))
	_agent(3)
	Trace.run(director, clock, 30.0)
	assert_eq(director.penguin_count(), 2, "the quiet agent left; the ones with an open call and an approval stayed")
	for penguin: RefCounted in director.penguins():
		assert_ne(penguin.number, 3)


func test_an_agent_that_comes_back_is_a_new_penguin() -> void:
	director.leave_after = 5.0
	_agent(1)
	Trace.run(director, clock, 6.0)
	assert_eq(director.penguin_count(), 0)
	_agent(1)
	assert_eq(director.penguin_count(), 1)
	assert_eq(director.penguins()[0].number, 2, "a new number: it came back as a new arrival")


func test_leave_after_is_off_by_default() -> void:
	_agent(1)
	Trace.run(director, clock, 700.0)
	assert_eq(director.penguin_count(), 1)


## Runs for `seconds` and sends an event of agent `n` every second, so that this agent never leaves.
func _run_keeping(n: int, seconds: float) -> void:
	var end: float = clock.now + seconds
	while clock.now < end - 1e-9:
		_agent(n)
		Trace.run(director, clock, 1.0)


func test_an_empty_arena_closes_after_close_after_seconds_but_never_the_last() -> void:
	director.set_arena_size(1)
	director.leave_after = 5.0
	_agent(1)
	_agent(2)
	_run_keeping(2, 20.0)
	assert_eq(director.letters(), ["A", "B"] as Array[String], "A is empty since about 5 s, but it closes only after 30 s")
	_run_keeping(2, 25.0)
	assert_eq(director.letters(), ["B"] as Array[String], "A closed 30 s after it emptied")
	assert_false(director.rooms.has("A"))
	# the last arena never closes, even when it is empty
	Trace.run(director, clock, 120.0)
	assert_eq(director.penguin_count(), 0)
	assert_eq(director.letters(), ["B"] as Array[String])


func test_the_lowest_free_letter_is_used_again() -> void:
	director.set_arena_size(1)
	director.leave_after = 5.0
	for n in 3:
		_agent(n + 1)
	var end: float = clock.now + 45.0
	while clock.now < end:
		_agent(1)
		_agent(3)
		Trace.run(director, clock, 1.0)
	assert_eq(director.letters(), ["A", "C"] as Array[String], "B closed, and its place stays free")
	_agent(9)
	assert_eq(director.letters(), ["A", "B", "C"] as Array[String], "the new arena takes the lowest free letter, B")


func test_names_go_on_after_z() -> void:
	director.set_arena_size(1)
	director.limit = 100
	for n in 28:
		_agent(n + 1)
	var letters: Array[String] = director.letters()
	assert_eq(letters.size(), 28)
	assert_eq(letters[25], "Z")
	assert_eq(letters[26], "AA")
	assert_eq(letters[27], "AB")


# ---------------------------------------------------------------- what the camera is told

func _with_camera() -> Camera:
	var cam: Camera = Camera.new()
	director.attach_camera(cam)
	return cam


func test_a_camera_hears_of_the_arenas_that_open_and_close() -> void:
	var cam: Camera = _with_camera()
	director.set_arena_size(1)
	director.sync_time(1.0)
	_agent(1)
	_agent(2)
	cam.advance(1.1)
	assert_eq(cam.letters, ["A", "B"] as Array[String])
	director.leave_after = 3.0
	Trace.run(director, clock, 0.01)
	director.sync_time(1.0)
	_agent(2)
	assert_eq(cam.pending(), ["open:B"] as Array[String], "the new arena is a pull for the camera")


func test_an_approval_pulls_the_camera_and_the_next_event_ends_it() -> void:
	var cam: Camera = _with_camera()
	director.set_arena_size(1)
	_agent(1)
	_agent(2)
	director.sync_time(4.0)
	cam.advance(4.0)
	assert_eq(cam.arena_shown(), "A")
	director.handle_event(Trace.ev("waiting_permission", { }, "main", "claude-code", "s2"))
	cam.advance(4.1)
	assert_eq(cam.log[cam.log.size() - 1]["why"], "pull:approval")
	assert_eq(cam.arena_shown(), "B")
	# no answer yet: the approval stays open
	cam.advance(20.0)
	assert_eq(cam._pulls.size(), 1, "the approval is still open")
	director.sync_time(20.0)
	director.handle_event(Trace.tool_end(true, "c1", "main", "claude-code", "s2"))
	cam.advance(21.0)
	assert_true(cam._pulls.is_empty(), "the next event of the agent answered it")


func test_a_failure_is_known_to_the_camera_but_does_not_pull_when_it_is_not_ticked() -> void:
	var cam: Camera = Camera.new({ "follow": { "activity": false } })
	director.attach_camera(cam)
	director.set_arena_size(1)
	_agent(1)
	_agent(2)
	director.sync_time(5.0)
	director.handle_event(Trace.tool_start("exec", "make", "c1", "main", "claude-code", "s2"))
	director.handle_event(Trace.tool_end(false, "c1", "main", "claude-code", "s2"))
	cam.advance(5.1)
	assert_eq(cam.arena_shown(), "A", "failures are not ticked in the follow switch: the camera stays")
	assert_eq(cam._fail_events.size(), 1, "but the failure is known to N")
	cam.press("N", 5.2)
	cam.advance(5.4)
	assert_eq(cam.arena_shown(), "B")


func test_the_focus_of_an_arena_is_the_cameras() -> void:
	var cam: Camera = _with_camera()
	director.set_arena_size(2)
	director.sync_time(1.0)
	_agent(1)
	_agent(2)
	cam.advance(3.0)
	assert_not_null(cam.focus_of("A"))
	assert_eq(director.focus.focused, "", "the director's own focus is not used with a camera")


func test_a_helper_that_finishes_its_work_does_not_pull_the_camera() -> void:
	var cam: Camera = Camera.new({ "follow": { "activity": false } })
	director.attach_camera(cam)
	director.set_arena_size(1)
	_agent(1)
	_agent(2)
	director.sync_time(4.0)
	director.handle_event(Trace.ev("subagent_start", { "id": "sub1" }, "main", "claude-code", "s2"))
	director.handle_event(Trace.ev("done", { }, "sub1", "claude-code", "s2"))
	cam.advance(4.2)
	assert_eq(cam.arena_shown(), "A", "the helper's finished turn is activity, not a pull")
	director.handle_event(Trace.ev("done", { }, "main", "claude-code", "s2"))
	cam.advance(4.4)
	assert_eq(cam.arena_shown(), "B", "the finished turn of a main agent does")
