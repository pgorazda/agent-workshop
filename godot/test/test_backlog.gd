extends GutTest
## The backlog rule: a long queue loses its oldest finished calls and keeps the last few events, an open permission prompt and `done`.

const Backlog := preload("res://src/core/backlog.gd")
const Trace := preload("res://test/support/trace.gd")


func _calls(count: int, first_id: int = 1) -> Array:
	var list: Array = []
	for i in count:
		var id: String = "c%d" % (first_id + i)
		list.append(Trace.tool_start("read", "f%d" % i, id))
		list.append(Trace.tool_end(true, id))
	return list


func _types(queue: Array) -> Array:
	var types: Array = []
	for event: RefCounted in queue:
		types.append(event.type)
	return types


func test_a_short_queue_is_not_changed() -> void:
	var queue: Array = _calls(5)
	assert_eq(Backlog.trim(queue), 0)
	assert_eq(queue.size(), 10)


func test_the_oldest_finished_calls_go_first_and_in_pairs() -> void:
	var queue: Array = _calls(20)
	var dropped: int = Backlog.trim(queue)
	assert_gt(dropped, 0)
	assert_lte(queue.size(), Backlog.LIMIT)
	assert_eq(dropped % 2, 0, "a start and its end go together")
	# the last events are still there, and the ids that are left are in pairs
	assert_eq((queue[queue.size() - 1] as RefCounted).id, "c20")
	var open: Dictionary = { }
	for event: RefCounted in queue:
		if event.type == "tool_start":
			open[event.id] = true
		else:
			assert_true(open.has(event.id), "an end has its start")
			open.erase(event.id)
	assert_eq(open.size(), 0)


func test_the_last_events_stay_even_when_the_queue_is_still_long() -> void:
	var queue: Array = _calls(20)
	Backlog.trim(queue, 4, 6)
	assert_gte(queue.size(), 6, "the last six events stay")
	assert_eq((queue[queue.size() - 1] as RefCounted).id, "c20")


func test_done_stays() -> void:
	var queue: Array = [Trace.ev("done")]
	queue.append_array(_calls(20))
	Backlog.trim(queue, 10, 4)
	assert_eq((queue[0] as RefCounted).type, "done")


func test_an_open_prompt_stays_and_an_answered_one_goes() -> void:
	var queue: Array = [Trace.ev("waiting_permission"), Trace.tool_end()]
	queue.append_array(_calls(12))
	queue.append(Trace.ev("waiting_permission"))
	Backlog.trim(queue, 10, 2)
	assert_eq((queue[queue.size() - 1] as RefCounted).type, "waiting_permission", "the open prompt at the end stays")
	var prompts: int = _types(queue).count("waiting_permission")
	assert_eq(prompts, 1, "the answered prompt at the start went")


func test_a_call_that_is_still_open_stays() -> void:
	var queue: Array = [Trace.tool_start("exec", "make", "open1")]
	queue.append_array(_calls(14, 2))
	Backlog.trim(queue, 10, 2)
	assert_eq((queue[0] as RefCounted).id, "open1")
	assert_eq((queue[0] as RefCounted).type, "tool_start")


func test_thinking_and_unknown_events_go() -> void:
	var queue: Array = []
	for i in 12:
		queue.append(Trace.ev("thinking"))
		queue.append(Trace.ev("something_new"))
	queue.append(Trace.ev("done"))
	Backlog.trim(queue, 10, 3)
	assert_lte(queue.size(), 10)
	assert_eq((queue[queue.size() - 1] as RefCounted).type, "done")


func test_it_stops_when_the_queue_is_short_enough() -> void:
	var queue: Array = _calls(15)
	var before: int = queue.size()
	Backlog.trim(queue, 28, 6)
	assert_eq(queue.size(), 28, "30 events and a limit of 28: one pair goes, and no more")
	assert_eq(before - queue.size(), 2)
