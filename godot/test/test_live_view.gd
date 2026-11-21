extends GutTest
## The live room: one scene that gets its events from the bridge or from a timeline, and draws the director's penguins.

const LiveView := preload("res://src/view/live_view.gd")
const Trace := preload("res://test/support/trace.gd")
const FramePolicy := preload("res://src/core/frame_policy.gd")

var view: Node


func before_each() -> void:
	var scene: PackedScene = load("res://src/live.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.client.set_process(false)


func test_it_starts_in_live_mode_with_a_bridge_client_and_an_empty_room() -> void:
	assert_not_null(view.client)
	assert_null(view.player)
	assert_eq(view.director.penguin_count(), 0)
	assert_eq(view.status_info()["source"], "live")


func test_an_event_from_the_bridge_makes_a_penguin() -> void:
	view._handle(Trace.tool_start("read"))
	view.simulate(120)
	assert_eq(view.director.penguin_count(), 1)
	assert_eq(view.status_info()["counts"], "1 agent, 0 helpers")
	await wait_process_frames(2)
	assert_eq(view.stage.penguins.size(), 1)


func test_two_frameworks_give_two_penguins_with_their_own_cords() -> void:
	view._handle(Trace.tool_start("read", "a", "c1", "main", "claude-code", "s1"))
	view._handle(Trace.tool_start("exec", "b", "c2", "main", "pi", "s2"))
	view._handle(Trace.tool_start("write", "c", "c3", "main", "hermes", "s3"))
	view.simulate(180)
	var cords: Array = []
	for penguin: RefCounted in view.director.penguins():
		cords.append(penguin.cord)
	assert_eq(cords, ["claude-code", "pi", "hermes"])
	await wait_process_frames(2)
	assert_eq(view.stage.penguins.size(), 3)


func test_a_scene_plays_from_its_timeline_and_loops() -> void:
	assert_true(view.load_scene("session"))
	assert_null(view.client, "demo mode does not read the bridge")
	assert_eq(view.status_info()["source"], "demo")
	view.simulate(60 * 12)
	assert_eq(view.director.penguin_count(), 1)
	assert_eq(view.director.helpers().size(), 1, "the helper is there at 12 s")
	var duration: float = view.player.duration
	view.simulate(int((duration + view.LOOP_PAUSE) * 60.0) + 120)
	assert_eq(view.restarts, 1, "after the scene it started again")
	assert_lt(view.clock.now, view.player.duration, "and the clock went back to 0")


func test_the_multi_scene_shows_six_agents_and_takes_its_inputs() -> void:
	assert_true(view.load_scene("multi"))
	view.simulate(60 * 24)
	assert_eq(view.director.penguin_count(), 6)
	assert_eq(view.camera.mode, "MANUAL", "the scripted F key at 22.6 s")
	assert_eq(view.director.letters(), ["A"] as Array[String], "the scene asks for one room for everyone")
	view.simulate(60 * 2)
	assert_eq(view.camera.focus_of("A"), 4, "the scripted click pins penguin 4")


func test_an_unknown_scene_is_a_note_and_the_room_stays_live() -> void:
	assert_false(view.load_scene("nothing-like-it"))
	assert_true("No scene named nothing-like-it" in view.status_info()["notes"])


func test_a_timeline_file_of_the_users_own() -> void:
	var path: String = "user://test_timeline.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"title":"mine","events":[{"t":0.1,"event":{"v":1,"framework":"pi","session":"x","agent":"main","type":"thinking","ts":1}}]}')
	file.close()
	assert_true(view.load_timeline(path))
	view.simulate(60)
	assert_eq(view.director.penguin_count(), 1)
	assert_eq(view.status_info()["state"], "mine")
	DirAccess.remove_absolute(path)
	assert_false(view.load_timeline("user://not-there.json"))


func test_the_clock_pause_and_speed_move_the_story() -> void:
	view.load_scene("session")
	view.clock.paused = true
	assert_eq(view.clock.advance(0.1), 0)
	view.clock.paused = false
	view.clock.speed = 4.0
	assert_gt(view.clock.advance(0.05), 10)


func test_restart_starts_again_from_time_zero() -> void:
	view.load_scene("session")
	view.simulate(60 * 5)
	view.restart()
	assert_eq(view.clock.now, 0.0)
	assert_eq(view.director.penguin_count(), 0)
	view.simulate(60 * 5)
	assert_eq(view.director.penguin_count(), 1, "the timeline plays from its first event again")


func test_the_scene_menu_lists_live_and_the_demo_files() -> void:
	view._menu_open = true
	var info: Dictionary = view.status_info()
	assert_eq(info["menu"][0], LiveView.LIVE_ENTRY)
	assert_has(info["menu"], "session")
	assert_has(info["menu"], "multi")


func test_the_window_policy_is_applied() -> void:
	view._on_focus_changed(false)
	assert_eq(Engine.max_fps, 30)
	view._on_focus_changed(true)
	assert_eq(Engine.max_fps, 60)
	view._minimized = true
	view._apply_window_policy()
	assert_false(RenderingServer.render_loop_enabled)
	view._minimized = false
	view._apply_window_policy()
	assert_true(RenderingServer.render_loop_enabled)


func test_frames_draw_without_errors_through_a_whole_scene() -> void:
	view.load_scene("multi")
	for i in 12:
		view.simulate(150)
		await wait_process_frames(1)
	assert_gt(view.director.penguin_count(), 3)


func test_a_scene_with_arenas_plays_through_the_camera() -> void:
	assert_true(view.load_scene("arenas"))
	view.simulate(60 * 8)
	assert_eq(view.director.letters(), ["A", "B"] as Array[String], "the fifth agent opened arena B at 7 s")
	assert_eq(view.camera.arena_shown(), "B", "and pulled the camera there")
	assert_eq(view.status_info()["view"], "arena B, page 1 of 1")
	await wait_process_frames(2)
	assert_eq(view.stage.letter, "B", "the sign of arena B says its letter")
	assert_true(view.arena_view.visible_letters.has("B"))
	assert_false(view.arena_view.visible_letters.has("A"), "a room that is not in view is hidden")


func test_the_keys_of_the_camera_reach_it() -> void:
	assert_true(view.load_scene("arenas"))
	view.simulate(60 * 8)
	view.camera.press("Tab", view.clock.now)
	view.simulate(60 * 2)
	assert_true(view.camera.in_overview())
	await wait_process_frames(2)
	assert_eq(view.arena_view.visible_letters.size(), 2, "the overview shows both rooms")
	assert_true(view.arena_view.smooth, "a scaled world uses the smooth filter")
	view.camera.press("Esc", view.clock.now)
	view.simulate(60 * 2)
	assert_false(view.camera.in_overview())
	await wait_process_frames(2)
	assert_false(view.arena_view.smooth, "one arena is on whole pixels with the nearest filter")


func test_a_scene_that_starts_before_zero_has_its_agents_at_the_first_frame() -> void:
	assert_true(view.load_scene("follow"))
	assert_lt(view.player.start_time(), 0.0)
	assert_eq(view.clock.now, 0.0, "the preroll ran before the first frame")
	assert_eq(view.director.penguin_count(), 30, "30 agents were there before the clip")


func test_a_window_that_is_not_shown_keeps_time_with_the_clock_and_steps_the_actors_in_pieces() -> void:
	view.load_scene("multi")
	view.simulate(60 * 6)
	var before: float = view.clock.now
	# a minimized window: a slow frame counts as long as it lasts
	var steps: int = view.clock.advance(0.25, FramePolicy.MINIMIZED_MAX_FRAME)
	assert_eq(steps, 15, "0.25 s is 15 steps of 1/60 s: it is not cut to 0.1 s")
	view.simulate(steps, true)
	assert_almost_eq(view.clock.now, before + 0.25, 1e-6)
	assert_eq(view._coarse_steps, 0, "every step was handed to the actors by the end of the frame")
	assert_eq(view.clock.advance(0.25), 6, "a shown window counts a frame at most 0.1 s")


func test_the_story_in_coarse_pieces_ends_in_the_same_places_as_the_story_in_fine_steps() -> void:
	# the scene `multi` in steps of 1/60 s and again as a minimized window plays it: the same agents, helpers and camera moves, and
	# the agents in the same phase of their story (but for one that is at a boundary)
	var fine: Node = view
	fine.load_scene("multi")
	fine.simulate(60 * 28)
	var scene: PackedScene = load("res://src/live.tscn")
	var coarse: Node = scene.instantiate()
	add_child_autofree(coarse)
	coarse.client.set_process(false)
	coarse.load_scene("multi")
	for _i in 28 * 4:
		coarse.simulate(15, true)
	assert_eq(coarse.director.penguin_count(), fine.director.penguin_count())
	assert_eq(coarse.director.helpers().size(), fine.director.helpers().size())
	assert_eq(coarse.camera.log.size(), fine.camera.log.size())
	var same: int = 0
	for actor: RefCounted in fine.director.penguins():
		var other: RefCounted = coarse.director.penguin_with_number(actor.number)
		assert_not_null(other)
		if other != null and other.activity == actor.activity:
			same += 1
	assert_gte(same, fine.director.penguin_count() - 1, "at most one agent is in another phase of its story")
