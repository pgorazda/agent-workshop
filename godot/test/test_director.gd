extends GutTest
## The director: one penguin for each framework + session + agent, helpers, the limit, cord colours, the backlog rule.

const Director := preload("res://src/core/director.gd")
const Clock := preload("res://src/core/clock.gd")
const Data := preload("res://art/atlas_data.gd")
const Trace := preload("res://test/support/trace.gd")

var director: RefCounted
var clock: RefCounted


func before_each() -> void:
	director = Director.new()
	clock = Clock.new()


func test_the_hello_greeting_is_ignored() -> void:
	assert_false(director.handle_message({"v": 1, "type": "hello"}))
	assert_eq(director.penguin_count(), 0)
	assert_eq(director.routed, 0)


func test_a_message_that_is_not_an_event_is_ignored() -> void:
	assert_false(director.handle_message({"v": 1, "type": "tool_start"}))
	assert_eq(director.penguin_count(), 0)


func test_the_first_event_of_an_agent_makes_its_penguin() -> void:
	assert_true(director.handle_event(Trace.ev("thinking")))
	assert_eq(director.penguin_count(), 1)
	var penguin: RefCounted = director.penguins()[0]
	assert_eq(penguin.framework, "claude-code")
	assert_eq(penguin.number, 1)
	assert_false(penguin.is_helper)


func test_one_penguin_for_each_framework_session_and_agent() -> void:
	director.handle_event(Trace.ev("thinking"))
	director.handle_event(Trace.ev("thinking"))
	assert_eq(director.penguin_count(), 1, "the same key: the same penguin")
	director.handle_event(Trace.ev("thinking", { }, "main", "claude-code", "s2"))
	assert_eq(director.penguin_count(), 2, "another session: another penguin")
	director.handle_event(Trace.ev("thinking", { }, "other"))
	assert_eq(director.penguin_count(), 3, "another agent: another penguin")
	director.handle_event(Trace.ev("thinking", { }, "main", "pi"))
	assert_eq(director.penguin_count(), 4, "another framework: another penguin")
	var numbers: Array = []
	for penguin: RefCounted in director.penguins():
		numbers.append(penguin.number)
	assert_eq(numbers, [1, 2, 3, 4], "each penguin gets a number when it first appears")


func test_the_cap_cord_comes_from_the_framework() -> void:
	assert_eq(Director.cord_of("claude-code"), "claude-code")
	assert_eq(Director.cord_of("hermes"), "hermes")
	assert_eq(Director.cord_of("some-new-framework"), "default", "an unknown framework gets the default grey")
	director.handle_event(Trace.ev("thinking", { }, "main", "pi"))
	assert_eq((director.penguins()[0] as RefCounted).cord, "pi")


func test_the_known_frameworks_are_the_cords_of_the_atlas() -> void:
	var cords: Array = Data.CORDS.keys().duplicate()
	cords.erase("default")
	var known: Array = Array(Director.KNOWN_FRAMEWORKS).duplicate()
	cords.sort()
	known.sort()
	assert_eq(known, cords)


func test_the_limit_on_penguins() -> void:
	director.limit = 3
	for i in 5:
		director.handle_event(Trace.ev("thinking", { }, "agent-%d" % i))
	assert_eq(director.penguin_count(), 3)
	assert_eq(director.dropped_agents, 2, "two events came from agents that got no penguin")
	director.handle_event(Trace.ev("thinking", { }, "agent-0"))
	assert_eq(director.dropped_agents, 2, "an agent that has a penguin is not dropped")


func test_the_default_limit_is_twelve() -> void:
	assert_eq(Director.DEFAULT_LIMIT, 12)
	for i in 14:
		director.handle_event(Trace.ev("thinking", { }, "a%d" % i))
	assert_eq(director.penguin_count(), 12)


func test_a_subagent_start_makes_a_helper_that_goes_after_subagent_end() -> void:
	director.handle_event(Trace.tool_start("delegate", "explore", "t1"))
	director.handle_event(Trace.ev("subagent_start", {"id": "sub1"}))
	assert_eq(director.penguin_count(), 1, "a helper is not a penguin for the limit")
	assert_eq(director.helpers().size(), 1)
	var helper: RefCounted = director.helpers()[0]
	var parent: RefCounted = director.penguins()[0]
	assert_true(helper.is_helper)
	assert_eq(helper.number, parent.number, "a helper wears its parent's number")
	assert_eq(helper.cord, parent.cord)
	director.handle_event(Trace.ev("subagent_end", {"id": "sub1"}))
	Trace.run(director, clock, 1.0)
	assert_eq(director.helpers().size(), 0, "the helper is removed after it vanished")
	assert_eq(director.penguin_count(), 1)


func test_a_subagents_own_events_go_to_its_helper() -> void:
	director.handle_event(Trace.ev("subagent_start", {"id": "sub1"}))
	director.handle_event(Trace.tool_start("read", "a.py", "r1", "sub1"))
	assert_eq(director.penguin_count(), 1, "the event made no new penguin")
	var helper: RefCounted = director.helpers()[0]
	assert_eq(helper.queue.size(), 1, "it went to the helper")
	assert_eq((director.penguins()[0] as RefCounted).queue.size(), 0)


func test_a_second_subagent_start_with_the_same_id_makes_no_second_helper() -> void:
	director.handle_event(Trace.ev("subagent_start", {"id": "sub1"}))
	director.handle_event(Trace.ev("subagent_start", {"id": "sub1"}))
	assert_eq(director.helpers().size(), 1)


func test_a_subagent_end_of_an_unknown_helper_changes_nothing() -> void:
	director.handle_event(Trace.ev("thinking"))
	assert_false(director.handle_event(Trace.ev("subagent_end", {"id": "nope"})))
	assert_eq(director.penguin_count(), 1)


func test_a_session_start_makes_a_penguin_with_nothing_to_do() -> void:
	director.handle_event(Trace.ev("session_start"))
	assert_eq(director.penguin_count(), 1)
	assert_eq((director.penguins()[0] as RefCounted).queue.size(), 0)


func test_new_penguins_pop_in_at_different_places() -> void:
	for i in 3:
		director.handle_event(Trace.ev("session_start", { }, "a%d" % i))
	var spots: Dictionary = { }
	for penguin: RefCounted in director.penguins():
		spots[penguin.position] = true
	assert_eq(spots.size(), 3)


func test_the_backlog_rule_cuts_a_long_queue() -> void:
	for i in 40:
		director.handle_event(Trace.tool_start("read", "f%d" % i, "c%d" % i))
		director.handle_event(Trace.tool_end(true, "c%d" % i))
	var penguin: RefCounted = director.penguins()[0]
	assert_lte(penguin.queue.size(), director.backlog_limit)
	assert_gt(director.dropped_events, 0)
	assert_eq((penguin.queue[penguin.queue.size() - 1] as RefCounted).type, "tool_end", "the last event is kept")
	assert_eq((penguin.queue[penguin.queue.size() - 1] as RefCounted).id, "c39")


func test_the_focus_follows_the_events() -> void:
	director.handle_event(Trace.ev("thinking"))
	Trace.run(director, clock, 0.1)
	assert_eq(director.focus.focused, (director.penguins()[0] as RefCounted).key)


func test_a_failure_takes_the_focus_at_once() -> void:
	director.handle_event(Trace.ev("thinking", { }, "a"))
	Trace.run(director, clock, 0.1)
	director.handle_event(Trace.ev("thinking", { }, "b"))
	director.handle_event(Trace.tool_end(false, "x", "b"))
	Trace.run(director, clock, 0.05)
	assert_eq(director.focus.focused, Director.key_of("claude-code", "s1", "b"))


func test_a_helpers_events_count_for_its_parent_in_the_focus() -> void:
	director.handle_event(Trace.ev("subagent_start", {"id": "sub1"}))
	Trace.run(director, clock, 0.1)
	assert_eq(director.focus.focused, (director.penguins()[0] as RefCounted).key)


func test_the_penguin_with_a_number() -> void:
	director.handle_event(Trace.ev("thinking", { }, "a"))
	director.handle_event(Trace.ev("thinking", { }, "b"))
	assert_eq((director.penguin_with_number(2) as RefCounted).agent, "b")
	assert_null(director.penguin_with_number(9))
