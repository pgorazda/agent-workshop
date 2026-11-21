extends GutTest
## The focus: AUTO and MANUAL, the hold, the events that take it at once, and a click.

const Focus := preload("res://src/core/focus.gd")


## Runs the focus for `seconds` in steps of 1/60 s from `from`. Returns the new time.
func _run(focus: RefCounted, from: float, seconds: float) -> float:
	var now: float = from
	var end: float = from + seconds
	while now < end - 1e-9:
		now += 1.0 / 60.0
		focus.step(now)
	return now


func test_the_first_event_gives_the_focus_at_once() -> void:
	var focus: RefCounted = Focus.new()
	focus.note("a", false)
	focus.step(0.0)
	assert_eq(focus.focused, "a")


func test_auto_follows_the_newest_event_after_the_hold() -> void:
	var focus: RefCounted = Focus.new()
	focus.note("a", false)
	var now: float = _run(focus, 0.0, 0.1)
	focus.note("b", false)
	now = _run(focus, now, 1.0)
	assert_eq(focus.focused, "a", "less than 1.5 s after the last switch: the focus stays")
	now = _run(focus, now, 0.6)
	assert_eq(focus.focused, "b", "after the hold it follows the newest event")


func test_a_failure_an_approval_and_a_finished_turn_take_it_at_once() -> void:
	var focus: RefCounted = Focus.new()
	focus.note("a", false)
	var now: float = _run(focus, 0.0, 0.1)
	focus.note("b", true)
	_run(focus, now, 0.05)
	assert_eq(focus.focused, "b", "a priority event does not wait for the hold")


func test_a_priority_event_is_used_up_and_does_not_pin_the_focus() -> void:
	var focus: RefCounted = Focus.new()
	focus.note("a", true)
	var now: float = _run(focus, 0.0, 0.1)
	assert_eq(focus.focused, "a")
	focus.note("b", false)
	now = _run(focus, now, 2.0)
	assert_eq(focus.focused, "b", "the priority of a was used up: b gets the focus after the hold")


func test_a_priority_event_of_the_agent_that_has_the_focus_is_used_up_too() -> void:
	var focus: RefCounted = Focus.new()
	focus.note("a", false)
	var now: float = _run(focus, 0.0, 0.1)
	focus.note("a", true)
	focus.note("b", false)
	now = _run(focus, now, 0.1)
	assert_eq(focus.focused, "a")
	now = _run(focus, now, 2.0)
	assert_eq(focus.focused, "b")


func test_manual_does_not_move_with_events() -> void:
	var focus: RefCounted = Focus.new()
	focus.note("a", false)
	var now: float = _run(focus, 0.0, 0.1)
	focus.toggle_mode()
	assert_eq(focus.mode_name(), "MANUAL")
	focus.note("b", true)
	now = _run(focus, now, 5.0)
	assert_eq(focus.focused, "a")


func test_manual_without_a_focus_takes_the_first_event() -> void:
	var focus: RefCounted = Focus.new()
	focus.toggle_mode()
	focus.note("a", false)
	_run(focus, 0.0, 0.1)
	assert_eq(focus.focused, "a")


func test_a_click_moves_the_focus_in_both_modes() -> void:
	var focus: RefCounted = Focus.new()
	focus.note("a", false)
	var now: float = _run(focus, 0.0, 0.1)
	focus.click("c", now)
	assert_eq(focus.focused, "c")
	focus.toggle_mode()
	focus.note("b", true)
	now = _run(focus, now, 3.0)
	assert_eq(focus.focused, "c", "in MANUAL the click pins the focus")


func test_a_click_in_auto_holds_for_the_hold_time() -> void:
	var focus: RefCounted = Focus.new()
	focus.note("a", false)
	var now: float = _run(focus, 0.0, 0.1)
	focus.click("c", now)
	focus.note("b", false)
	now = _run(focus, now, 1.2)
	assert_eq(focus.focused, "c")
	now = _run(focus, now, 0.5)
	assert_eq(focus.focused, "b")


func test_toggling_back_to_auto_does_not_replay_old_priority_events() -> void:
	var focus: RefCounted = Focus.new()
	focus.note("a", false)
	var now: float = _run(focus, 0.0, 0.1)
	focus.toggle_mode()
	focus.note("b", true)
	now = _run(focus, now, 0.5)
	focus.toggle_mode()
	now = _run(focus, now, 0.05)
	assert_eq(focus.focused, "a", "the old priority of b was dropped in MANUAL")


func test_an_agent_that_leaves_loses_the_focus() -> void:
	var focus: RefCounted = Focus.new()
	focus.note("a", false)
	var now: float = _run(focus, 0.0, 0.1)
	focus.remove("a")
	assert_eq(focus.focused, "")
	focus.note("b", false)
	_run(focus, now, 0.1)
	assert_eq(focus.focused, "b")
