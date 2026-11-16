extends GutTest
## The timeline player of demo mode: events and inputs at the right moment, pause and speed on the clock, a restart.

const TimelinePlayer := preload("res://src/net/timeline_player.gd")
const Clock := preload("res://src/core/clock.gd")
const Director := preload("res://src/core/director.gd")


func _event(t: float, type: String, extra: Dictionary = { }) -> Dictionary:
	var event: Dictionary = {"v": 1, "framework": "claude-code", "session": "s", "agent": "main", "type": type, "ts": 1000 + int(t * 1000)}
	event.merge(extra, true)
	return {"t": t, "event": event}


func _timeline() -> Dictionary:
	return {
		"title": "A test", "duration": 5.0,
		"events": [
			_event(0.5, "session_start"),
			_event(1.0, "tool_start", {"category": "read", "tool": "Read", "id": "a"}),
			_event(2.0, "tool_end", {"ok": true, "id": "a"}),
		],
		"inputs": [{"t": 1.5, "key": "F"}, {"t": 4.0, "click": {"number": 1}}],
	}


func test_it_reads_a_timeline() -> void:
	var player: RefCounted = TimelinePlayer.from_dictionary(_timeline())
	assert_not_null(player)
	assert_eq(player.title, "A test")
	assert_eq(player.events.size(), 3)
	assert_eq(player.inputs.size(), 2)
	assert_eq(player.duration, 5.0)
	assert_eq(player.rejected, 0)


func test_the_duration_is_at_least_the_last_item() -> void:
	var data: Dictionary = _timeline()
	data["duration"] = 1.0
	var player: RefCounted = TimelinePlayer.from_dictionary(data)
	assert_eq(player.duration, 4.0)


func test_a_file_without_a_list_of_events_is_not_a_timeline() -> void:
	assert_null(TimelinePlayer.from_dictionary({"title": "x"}))


func test_a_bad_item_is_skipped_and_counted() -> void:
	var data: Dictionary = _timeline()
	(data["events"] as Array).append({"t": 3.0, "event": {"v": 2, "type": "x"}})
	(data["events"] as Array).append("not an item")
	var player: RefCounted = TimelinePlayer.from_dictionary(data)
	assert_eq(player.events.size(), 3)
	assert_eq(player.rejected, 2)


func test_each_event_comes_once_when_its_time_is_reached() -> void:
	var player: RefCounted = TimelinePlayer.from_dictionary(_timeline())
	var clock: RefCounted = Clock.new()
	var seen: Array[String] = []
	while clock.now < 3.0:
		for event: RefCounted in player.due_events(clock.now):
			seen.append("%s@%.2f" % [event.type, clock.now])
		clock.tick()
	assert_eq(seen.size(), 3)
	assert_eq(seen[0], "session_start@0.50")
	assert_eq(seen[1], "tool_start@1.00")
	assert_eq(seen[2], "tool_end@2.00")


func test_inputs_come_once_in_order() -> void:
	var player: RefCounted = TimelinePlayer.from_dictionary(_timeline())
	assert_eq(player.due_inputs(1.4).size(), 0)
	var first: Array[Dictionary] = player.due_inputs(1.5)
	assert_eq(first.size(), 1)
	assert_eq(first[0]["key"], "F")
	assert_eq(player.due_inputs(1.6).size(), 0)
	var second: Array[Dictionary] = player.due_inputs(9.0)
	assert_eq(second[0]["click"]["number"], 1)


func test_pause_and_speed_come_from_the_clock() -> void:
	var player: RefCounted = TimelinePlayer.from_dictionary(_timeline())
	var clock: RefCounted = Clock.new()
	clock.paused = true
	for _frame in 120:
		for _i: int in clock.advance(1.0 / 60.0):
			clock.tick()
	assert_eq(player.due_events(clock.now).size(), 0, "a paused clock stays at time 0: no event is due")
	clock.paused = false
	clock.speed = 4.0
	var frame_time: float = 0.0
	while player.due_events(clock.now).size() < 1 and frame_time < 5.0:
		for _i: int in clock.advance(1.0 / 60.0):
			clock.tick()
		frame_time += 1.0 / 60.0
	assert_lt(frame_time, 0.2, "at 4x the first event (0.5 s) comes within 0.2 s of frames")


func test_finished_after_everything_and_the_time() -> void:
	var player: RefCounted = TimelinePlayer.from_dictionary(_timeline())
	assert_false(player.finished(9.0), "items are left")
	player.due_events(9.0)
	player.due_inputs(9.0)
	assert_true(player.finished(9.0))
	assert_false(player.finished(4.0), "the story is not over before its duration")


func test_a_restart_gives_the_same_state_every_time() -> void:
	var player: RefCounted = TimelinePlayer.from_dictionary(_timeline())
	var states: Array = []
	for round_number in 2:
		var director: RefCounted = Director.new()
		var clock: RefCounted = Clock.new()
		player.rewind()
		while clock.now < 3.0:
			for event: RefCounted in player.due_events(clock.now):
				director.handle_event(event)
			clock.tick()
			director.step(clock.now)
		var penguin: RefCounted = director.penguins()[0]
		states.append([penguin.position, penguin.activity, penguin.pose, director.world.effects.active().size()])
	assert_eq(states[0], states[1], "a restart looks the same every time")


func test_the_demo_scenes_are_found_and_valid() -> void:
	var scenes: Array[Dictionary] = TimelinePlayer.scenes()
	var names: Array = []
	for scene in scenes:
		names.append(scene["name"])
		var player: RefCounted = TimelinePlayer.load_file(str(scene["path"]))
		assert_not_null(player, "%s loads" % scene["name"])
		assert_eq(player.rejected, 0, "%s has no bad event" % scene["name"])
		assert_gt(player.events.size(), 10)
		assert_ne(player.title, "")
	assert_has(names, "session")
	assert_has(names, "multi")


func test_a_missing_file_is_null() -> void:
	assert_null(TimelinePlayer.load_file("res://demo/does-not-exist.json"))
