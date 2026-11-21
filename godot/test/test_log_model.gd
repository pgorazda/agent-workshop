extends GutTest
## The activity log and the cards: the lines and their states, long targets, the numbers, the cards (full up to five
## agents, compact from six), the counts and the labels. The model is built from the events of the director.

const LogModel := preload("res://src/core/log_model.gd")
const Director := preload("res://src/core/director.gd")
const Clock := preload("res://src/core/clock.gd")
const Trace := preload("res://test/support/trace.gd")

var model: LogModel


func before_each() -> void:
	model = LogModel.new()
	model.agent_joined("a", 1, "A", "claude-code", "4f2a1c0e-9b", "claude-code", 0.0)


func _call(type: String, extra: Dictionary = { }, key: String = "a", at: float = 1.0) -> void:
	model.note_event(Trace.ev(type, extra), key, at)


func _start(tool: String, target: String, id: String, category: String = "exec", at: float = 1.0) -> void:
	_call("tool_start", { "tool": tool, "target": target, "id": id, "category": category }, "a", at)


func test_a_call_is_a_line_that_runs_and_then_ends_ok() -> void:
	_start("Bash", "npm test", "c1")
	var lines: Array[Dictionary] = model.lines_of("a")
	assert_eq(lines.size(), 1)
	assert_eq(lines[0]["state"], "run")
	assert_eq(lines[0]["tool"], "Bash")
	assert_eq(lines[0]["target"], "npm test")
	assert_eq(lines[0]["icon"], "exec")
	_call("tool_end", { "ok": true, "id": "c1" })
	assert_eq(model.lines_of("a")[0]["state"], "OK")
	assert_eq(model.cards("A")[0]["state"], "OK")


func test_a_failed_call_is_a_FAIL_line_and_keeps_its_error() -> void:
	_start("Bash", "make", "c1")
	_call("tool_end", { "ok": false, "id": "c1", "error": "exit code 1" })
	var lines: Array[Dictionary] = model.lines_of("a")
	assert_eq(lines.size(), 2)
	assert_eq(lines[0]["state"], "FAIL")
	assert_true(lines[1]["error"])
	assert_eq(lines[1]["target"], "exit code 1")
	assert_eq(model.cards("A")[0]["state"], "FAIL")
	assert_eq(model.focus_label("a")["kind"], "fail")
	assert_eq(model.focus_label("a")["text"], "✗ exit code 1")


func test_the_next_event_of_the_agent_ends_the_failure_on_its_card() -> void:
	_start("Bash", "make", "c1")
	_call("tool_end", { "ok": false, "id": "c1" })
	assert_eq(model.cards("A")[0]["state"], "FAIL")
	_start("Read", "a.txt", "c2", "read")
	assert_eq(model.cards("A")[0]["state"], "run")


func test_an_approval_makes_the_open_line_wait_and_the_next_event_ends_the_wait() -> void:
	_start("Bash", "git push origin HEAD", "c1")
	_call("waiting_permission", { "target": "git push origin HEAD", "tool": "Bash" }, "a", 2.0)
	assert_eq(model.lines_of("a")[0]["state"], "WAIT")
	assert_eq(model.lines_of("a")[0]["icon"], "ask")
	assert_eq(model.cards("A")[0]["state"], "WAIT")
	assert_eq(model.cards("A")[0]["icon"], "ask")
	assert_eq(model.waiting("A").size(), 1)
	assert_eq(model.focus_label("a")["text"], "needs approval")
	_call("tool_end", { "ok": true, "id": "c1" }, "a", 5.0)
	assert_eq(model.lines_of("a")[0]["state"], "OK")
	assert_eq(model.waiting("A").size(), 0)
	assert_eq(model.cards("A")[0]["state"], "OK")


func test_an_approval_with_no_open_call_makes_its_own_line() -> void:
	_call("waiting_permission", { "target": "rm -rf build", "tool": "Bash" })
	var lines: Array[Dictionary] = model.lines_of("a")
	assert_eq(lines.size(), 1)
	assert_eq(lines[0]["state"], "WAIT")
	assert_eq(lines[0]["target"], "rm -rf build")


func test_a_wait_that_ends_by_another_event_runs_again() -> void:
	_start("Bash", "make", "c1")
	_call("waiting_permission", { "target": "make" })
	_call("thinking")
	assert_eq(model.lines_of("a")[0]["state"], "run", "the call is still open: it runs again")
	assert_eq(model.cards("A")[0]["state"], "run")


func test_thinking_is_a_line_only_while_it_lasts() -> void:
	_call("thinking")
	_call("thinking")
	assert_eq(model.lines_of("a").size(), 1, "more thinking while it thinks adds no line")
	assert_eq(model.lines_of("a")[0]["target"], "Thinking")
	assert_eq(model.cards("A")[0]["target"], "thinking")
	_start("Read", "x", "c1", "read")
	var lines: Array[Dictionary] = model.lines_of("a")
	assert_eq(lines.size(), 1, "the spell is over: its line is gone")
	assert_eq(lines[0]["tool"], "Read")


func test_a_think_call_counts_as_thinking() -> void:
	_start("Think", "", "c1", "think")
	assert_true(model.lines_of("a")[0]["thinking"])
	assert_eq(model.calls, 0, "thinking is not a call")


func test_a_finished_turn_says_its_calls_helpers_and_seconds() -> void:
	_start("Read", "a", "c1", "read", 1.0)
	_call("tool_end", { "ok": true, "id": "c1" }, "a", 2.0)
	_start("Bash", "ls", "c2", "exec", 3.0)
	_call("tool_end", { "ok": true, "id": "c2" }, "a", 4.0)
	model.helper_started("a", "h1", 4.5)
	_call("done", { }, "a", 10.0)
	var last: Dictionary = model.lines_of("a").back()
	assert_eq(last["target"], "Turn complete")
	assert_eq(last["detail"], "2 calls  ·  1 helper  ·  10 s")
	assert_eq(model.cards("A")[0]["state"], "DONE")
	assert_eq(model.cards("A")[0]["target"], "turn complete")
	assert_eq(model.focus_label("a")["kind"], "done")


func test_only_the_last_lines_are_kept() -> void:
	for i in 10:
		_start("Read", "f%d" % i, "c%d" % i, "read")
		_call("tool_end", { "ok": true, "id": "c%d" % i })
	assert_eq(model.lines_of("a", 100).size(), LogModel.MAX_LINES)
	assert_eq(model.lines_of("a").size(), LogModel.SHOWN_LINES)
	assert_eq(model.lines_of("a").back()["target"], "f9", "the newest line is last")


func test_a_long_target_is_cleaned_to_one_line_and_cut() -> void:
	var long_text: String = "line one\n\tline  two " + "x".repeat(400)
	_start("Bash", long_text, "c1")
	var target: String = model.lines_of("a")[0]["target"]
	assert_false("\n" in target)
	assert_false("\t" in target)
	assert_false("  " in target, "runs of spaces become one")
	assert_true(target.begins_with("line one line two x"))
	assert_lte(target.length(), LogModel.MAX_TEXT)
	assert_eq(LogModel.clean("  a \r\n b  "), "a b")
	assert_eq(LogModel.clean(""), "")


func test_the_art_cuts_a_target_to_a_width() -> void:
	const TextArt := preload("res://art/text_art.gd")
	var text: String = "src/adapters/claude-code-transcript-reader.js"
	var width: int = 60
	var fitted: String = TextArt.fit(TextArt.TINY5, text, width)
	assert_lte(TextArt.width(TextArt.TINY5, fitted), width)
	assert_true(fitted.ends_with(".."))
	assert_true(fitted.begins_with("src/"))
	assert_eq(TextArt.fit(TextArt.TINY5, "short", width), "short", "a text that fits stays")


func test_a_helper_wears_the_number_of_its_parent_and_counts_on_its_card() -> void:
	model.helper_started("a", "h1", 1.0)
	model.helper_started("a", "h2", 1.2)
	assert_eq(model.cards("A")[0]["helpers"], 2)
	assert_eq(model.helper_count(), 2)
	assert_eq(model.cards("A")[0]["number"], 1, "the card is the parent's: one card, the parent's number")
	model.helper_ended("h1", 3.0)
	assert_eq(model.helper_count(), 1)
	assert_eq(model.agent_count(), 1, "a helper is not an agent")


func test_the_events_of_a_helper_make_no_line_and_change_no_card() -> void:
	model.helper_started("a", "h1", 1.0)
	_start("Read", "mine", "c1", "read")
	model.note_event(Trace.ev("tool_start", { "tool": "Grep", "target": "helper work", "id": "x", "category": "search" }, "h1"), "h1", 2.0)
	assert_eq(model.lines_of("a").size(), 1)
	assert_eq(model.cards("A")[0]["target"], "mine")


func test_each_agent_has_its_number_and_keeps_it() -> void:
	model.agent_joined("b", 2, "A", "pi", "31", "pi", 1.0)
	model.agent_joined("c", 3, "B", "opencode", "ses_7", "opencode", 2.0)
	model.agent_joined("a", 99, "A", "claude-code", "x", "claude-code", 3.0)
	assert_eq(model.agents["a"]["number"], 1, "a second join of the same key changes nothing")
	var numbers: Array = []
	for card in model.cards("A"):
		numbers.append(card["number"])
	assert_eq(numbers, [1, 2], "the cards of an arena are in the order of their numbers")
	assert_eq(model.cards("B")[0]["number"], 3)
	model.agent_left("b", 5.0)
	assert_eq(model.cards("A").size(), 1)
	assert_eq(model.agent_count(), 2)


func test_the_cards_are_full_up_to_five_agents_and_compact_from_six() -> void:
	for n in range(2, 6):
		model.agent_joined("k%d" % n, n, "A", "pi", "s%d" % n, "pi", 0.0)
	assert_eq(model.agent_count("A"), 5)
	assert_false(model.is_compact("A"))
	for card in model.cards("A"):
		assert_false(card["compact"], "five agents: every card is full")
	model.agent_joined("k6", 6, "A", "hermes", "s6", "hermes", 0.0)
	assert_eq(model.agent_count("A"), 6)
	assert_true(model.is_compact("A"))
	for card in model.cards("A"):
		assert_true(card["compact"], "six agents: every card is compact")
	model.agent_left("k6", 1.0)
	assert_false(model.is_compact("A"), "back to five: full again")


func test_the_cards_count_an_arena_on_its_own() -> void:
	for n in range(2, 9):
		model.agent_joined("k%d" % n, n, "A" if n < 4 else "B", "pi", "s%d" % n, "pi", 0.0)
	assert_eq(model.agent_count("A"), 3)
	assert_eq(model.agent_count("B"), 5)
	assert_false(model.is_compact("B"))
	assert_eq(model.agent_count(), 8)
	assert_true(model.is_compact(), "all arenas together: more than five agents")


func test_a_card_says_the_framework_the_session_and_the_short_name() -> void:
	var card: Dictionary = model.cards("A")[0]
	assert_eq(card["framework"], "claude-code")
	assert_eq(card["short"], "claude")
	assert_eq(card["session"], "e-9b", "a long session id shows its last 4 characters")
	assert_eq(LogModel.short_session("ses_7"), "ses_7")
	assert_eq(LogModel.short_session("abcdef"), "abcdef")
	assert_eq(LogModel.short_name("pi"), "pi")
	assert_eq(LogModel.short_name("a-very-long-framework"), "a-very-l", "an unknown framework is cut to 8 characters")


func test_the_notices_of_several_agents_are_in_the_order_of_their_requests() -> void:
	model.agent_joined("b", 2, "A", "pi", "s2", "pi", 0.0)
	model.agent_joined("c", 3, "A", "hermes", "s3", "hermes", 0.0)
	model.note_event(Trace.ev("waiting_permission", { "target": "t2" }), "b", 4.0)
	model.note_event(Trace.ev("waiting_permission", { "target": "t1" }), "a", 6.0)
	model.note_event(Trace.ev("waiting_permission", { "target": "t3" }), "c", 5.0)
	var order: Array = []
	for a in model.waiting("A"):
		order.append(a["number"])
	assert_eq(order, [2, 3, 1], "the oldest request is first")
	assert_eq(model.waiting("B").size(), 0)


func test_the_counts_and_the_join_notice() -> void:
	model.agent_joined("b", 2, "A", "pi", "s2", "pi", 5.0)
	_start("Read", "x", "c1", "read")
	_start("Bash", "y", "c2", "exec")
	assert_eq(model.calls, 2)
	assert_eq(model.agent_count(), 2)
	assert_eq(model.recent_join(5.5)["number"], 2)
	assert_true(model.recent_join(7.3).is_empty(), "the notice lasts 2.2 s")
	model.agent_left("b", 6.0)
	assert_true(model.recent_join(6.5).is_empty(), "an agent that left is not announced")


func test_an_unknown_event_type_is_a_generic_line() -> void:
	_call("something-new", { })
	assert_eq(model.lines_of("a")[0]["tool"], "something-new")
	assert_eq(model.lines_of("a")[0]["icon"], "other")


func test_an_unknown_category_uses_the_other_icon() -> void:
	_start("Odd", "x", "c1", "other")
	assert_eq(model.lines_of("a")[0]["icon"], "other")
	for category: String in ["read", "search", "write", "exec", "web", "delegate", "think", "ask_permission", "other"]:
		assert_true(LogModel.ICONS.has(category), category)


# ---------------------------------------------------------------- the director feeds the model

func test_the_director_feeds_the_log_with_the_same_events() -> void:
	var director: Director = Director.new()
	var clock: Clock = Clock.new()
	director.set_arena_size(2)
	director.handle_event(Trace.tool_start("read", "a.txt", "c1", "main", "claude-code", "s1"))
	director.handle_event(Trace.ev("subagent_start", { "id": "h1" }, "main", "claude-code", "s1"))
	director.handle_event(Trace.tool_start("search", "helper job", "x1", "h1", "claude-code", "s1"))
	director.handle_event(Trace.tool_start("exec", "ls", "c2", "main", "pi", "s2"))
	director.handle_event(Trace.tool_start("exec", "ls", "c3", "main", "pi", "s3"))
	Trace.run(director, clock, 1.0)
	var activity: LogModel = director.activity_log
	assert_eq(activity.agent_count(), 3)
	assert_eq(activity.agent_count("A"), 2)
	assert_eq(activity.agent_count("B"), 1)
	assert_eq(activity.helper_count("A"), 1)
	assert_eq(activity.cards("A")[0]["target"], "a.txt", "the helper's call is not on its parent's card")
	assert_eq(activity.cards("A")[0]["number"], director.penguin_with_number(1).number)
	director.handle_event(Trace.ev("subagent_end", { "id": "h1" }, "main", "claude-code", "s1"))
	assert_eq(activity.helper_count("A"), 0)
	director.handle_event(Trace.tool_end(false, "c2", "main", "pi", "s2"))
	assert_eq(director.activity_log.cards("A")[1]["state"], "FAIL")


func test_an_agent_that_leaves_is_gone_from_the_log_and_comes_back_with_a_new_number() -> void:
	var director: Director = Director.new()
	var clock: Clock = Clock.new()
	director.leave_after = 5.0
	director.handle_event(Trace.ev("thinking"))
	Trace.run(director, clock, 1.0)
	assert_eq(director.activity_log.agent_count(), 1)
	Trace.run(director, clock, 8.0)
	assert_eq(director.activity_log.agent_count(), 0)
	director.handle_event(Trace.ev("thinking"))
	assert_eq(director.activity_log.cards()[0]["number"], 2, "the agent that comes back is a new arrival")
