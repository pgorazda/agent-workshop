extends GutTest
## Recording mode (phase G-8): the pure helpers of `core/recording.gd`, the new options, and the live view that runs in recording mode
## (a frame is a time, the scripted pointer, key caps and follow menu, no keys, no wall clock). The files are written by the engine's
## Movie Maker, which a unit test cannot run: `tools/determinism.mjs` and `tools/record.mjs` cover that.

const Recording := preload("res://src/core/recording.gd")
const Options := preload("res://src/core/options.gd")
const TimelinePlayer := preload("res://src/net/timeline_player.gd")
const PointerArt := preload("res://art/pointer_art.gd")

var view: Node


func before_each() -> void:
	var scene: PackedScene = load("res://src/live.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.client.set_process(false)


func _record(fps: int = 30) -> void:
	view.options.record_fps = fps
	view._recording = true


# ---------------------------------------------------------------- the frames

func test_a_clip_has_ceil_of_duration_times_fps_frames() -> void:
	assert_eq(Recording.frame_count(28.474, 30), 855, "28.474 s at 30 fps")
	assert_eq(Recording.frame_count(43.0, 30), 1290)
	assert_eq(Recording.frame_count(30.5, 24), 732)
	assert_eq(Recording.frame_count(0.0, 30), 1, "at least one frame")
	assert_eq(Recording.frame_count(1.0, 30), 30, "no extra frame for a float that is a whole number of frames")


func test_frame_i_shows_the_step_at_i_over_fps() -> void:
	assert_eq(Recording.steps_at_frame(0, 30), 0, "the first frame is the start of the story")
	assert_eq(Recording.steps_at_frame(1, 30), 2)
	assert_eq(Recording.steps_at_frame(30, 30), 60)
	assert_eq(Recording.steps_at_frame(1, 60), 1)
	assert_eq(Recording.steps_at_frame(1, 144), 0, "a frame shorter than a step shows the step before")
	assert_eq(Recording.steps_at_frame(3, 144), 1)
	assert_eq(Recording.steps_at_frame(1, 25), 2, "2.4 steps: the last whole step")
	assert_eq(Recording.steps_at_frame(24, 25), 57)
	assert_eq(Recording.steps_at_frame(25, 25), 60)


func test_the_steps_of_a_frame_do_not_depend_on_the_frame_rate() -> void:
	# a clip at 30 fps and a clip at 60 fps show the same simulation time at a time that both have
	for second: int in [1, 7, 22, 40]:
		assert_eq(Recording.steps_at_frame(second * 30, 30), Recording.steps_at_frame(second * 60, 60), "at %d s" % second)
		assert_eq(Recording.steps_at_frame(second * 25, 25), second * 60)
	assert_eq(Recording.steps_at_time(1.05), 63, "1.05 s is step 63, not 62")
	assert_eq(Recording.steps_at_time(0.6 + 0.45), 63)


func test_the_time_of_a_frame() -> void:
	assert_almost_eq(Recording.time_of_frame(15, 30), 0.5, 1e-12)


# ---------------------------------------------------------------- the pointer

func test_the_pointer_follows_its_path_with_an_ease() -> void:
	var path: Array = [[10.0, 100, 50], [12.0, 200, 150], [13.0, 200, 150]]
	assert_null(Recording.cursor_at(9.99, path), "not there before the first point")
	assert_null(Recording.cursor_at(13.01, path), "not there after the last point")
	assert_eq(Recording.cursor_at(10.0, path), Vector2i(100, 50))
	assert_eq(Recording.cursor_at(11.0, path), Vector2i(150, 100), "half way at half the time (smoothstep(0.5) is 0.5)")
	assert_eq(Recording.cursor_at(12.0, path), Vector2i(200, 150))
	assert_eq(Recording.cursor_at(12.5, path), Vector2i(200, 150), "it stays where the next two points are equal")
	var early: Vector2i = Recording.cursor_at(10.5, path)
	assert_lt(early.x, 125, "smoothstep is slow at the start")


func test_the_pointer_rounds_like_math_round() -> void:
	# half way from -1 to 0 is -0.5: Math.round gives -0 (a pixel at 0), and round() would give -1
	assert_eq(Recording.cursor_at(0.5, [[0.0, -1, 0], [1.0, 0, 0]]), Vector2i(0, 0))
	assert_eq(Recording.cursor_at(0.5, [[0.0, 0, 225], [1.0, 0, 226]]), Vector2i(0, 226), "225.5 rounds up")


func test_the_mockups_pointer_of_the_scene_multi_is_at_the_same_places() -> void:
	# computed with cursorAt of the JavaScript mockup (removed) for the path of the scene multi
	var path: Array = [[21.9, 486, 214], [22.6, 232, 237], [23.4, 279, 255], [24.4, 279, 255], [25.2, 492, 268]]
	assert_eq(Recording.cursor_at(22.25, path), Vector2i(359, 226))
	assert_eq(Recording.cursor_at(23.0, path), Vector2i(256, 246))
	assert_eq(Recording.cursor_at(24.0, path), Vector2i(279, 255))
	assert_eq(Recording.cursor_at(24.8, path), Vector2i(386, 262))


func test_the_pointers_and_the_rings_of_a_scene() -> void:
	var paths: Array = [{ "path": [[1.0, 10, 10], [2.0, 20, 20]], "clicks": [1.5, 1.9] }, { "path": [[5.0, 1, 1], [6.0, 2, 2]], "clicks": [] }]
	assert_eq(Recording.pointers_at(0.5, paths).size(), 0)
	var now: Array[Dictionary] = Recording.pointers_at(1.6, paths)
	assert_eq(now.size(), 1)
	assert_almost_eq(float(now[0]["ring_ages"][0]), 0.1, 1e-9, "a click 0.1 s ago")
	assert_almost_eq(float(now[0]["ring_ages"][1]), -0.3, 1e-9, "a click that has not come yet: the art draws no ring")
	assert_eq(Recording.hover_point_at(1.6, paths), Vector2(Recording.cursor_at(1.6, paths[0]["path"]) as Vector2i))
	assert_eq(Recording.hover_point_at(3.0, paths), Recording.NO_POINT)


func test_a_key_cap_shows_for_1_1_seconds() -> void:
	var keys: Array = [{ "t": 10.0, "label": "TAB" }, { "t": 10.5, "label": "F" }]
	assert_eq(Recording.key_caps_at(9.9, keys).size(), 0)
	assert_eq(Recording.key_caps_at(10.2, keys).size(), 1)
	assert_eq(Recording.key_caps_at(10.6, keys).size(), 2, "two keys at once")
	assert_eq(Recording.key_caps_at(11.2, keys).size(), 1, "the first one is gone")
	assert_eq(Recording.key_caps_at(11.7, keys).size(), 0)


func test_the_menu_is_open_in_its_windows() -> void:
	var menus: Array = [{ "open": 16.0, "close": 19.8 }, { "open": 30.0, "close": 30.9 }]
	assert_false(Recording.menu_open_at(15.9, menus))
	assert_true(Recording.menu_open_at(16.0, menus))
	assert_false(Recording.menu_open_at(19.8, menus), "closed at its close time")
	assert_true(Recording.menu_open_at(30.5, menus))


# ---------------------------------------------------------------- the check of the spots

class FakeActor:
	extends RefCounted
	var key: String = ""
	var hidden: bool = false
	var think_in_place: bool = false
	var position: Vector2 = Vector2.ZERO
	var kind: String = "work"

	func _init(new_key: String, at: Vector2, new_kind: String = "work") -> void:
		key = new_key
		position = at
		kind = new_kind

	func current_segment() -> Dictionary:
		return { "kind": kind }


class FakeDirector:
	extends RefCounted
	var actors: Array[RefCounted] = []

	func letters() -> Array[String]:
		return ["A"]

	func actors_in(_letter: String) -> Array[RefCounted]:
		return actors


func test_two_penguins_on_one_spot_are_found() -> void:
	var director: FakeDirector = FakeDirector.new()
	director.actors.append(FakeActor.new("a", Vector2(100, 100)))
	director.actors.append(FakeActor.new("b", Vector2(100.5, 100)))
	var found: Array[String] = Recording.spot_conflicts(director, 3.0)
	assert_eq(found.size(), 1)
	assert_string_contains(found[0], "a and b")


func test_penguins_that_are_not_standing_on_a_spot_are_left_out() -> void:
	var director: FakeDirector = FakeDirector.new()
	director.actors.append(FakeActor.new("a", Vector2(100, 100)))
	director.actors.append(FakeActor.new("walking", Vector2(100, 100), "walk"))
	var thinker: FakeActor = FakeActor.new("thinker", Vector2(100, 100), "think")
	thinker.think_in_place = true
	director.actors.append(thinker)
	var hidden: FakeActor = FakeActor.new("hidden", Vector2(100, 100))
	hidden.hidden = true
	director.actors.append(hidden)
	director.actors.append(FakeActor.new("far", Vector2(130, 100)))
	assert_eq(Recording.spot_conflicts(director, 0.0).size(), 0)


func test_a_real_scene_has_no_penguins_on_one_spot() -> void:
	# the scene with the most agents in one room: six agents, many stations
	assert_true(view.load_scene("multi"))
	var found: int = 0
	for _frame in 61 * 30:
		view.simulate(2)
		found += Recording.spot_conflicts(view.director, view.clock.now).size()
	assert_eq(found, 0)


# ---------------------------------------------------------------- the options

func test_the_recording_options() -> void:
	var options: Options = Options.parse(PackedStringArray(["--demo=tour", "--record-fps=24", "--stills=7,22.5,x,-1", "--stills-out=somewhere", "--menu=3", "--events=0", "--no-switch"]))
	assert_eq(options.record_fps, 24)
	assert_eq(options.stills, PackedFloat64Array([7.0, 22.5]), "numbers only, none below 0")
	assert_eq(options.stills_out, "somewhere")
	assert_eq(options.menu_seconds, 3.0)
	assert_true(options.events_off)
	assert_true(options.hide_switch)
	assert_true(options.recording())
	assert_eq(options.warnings.size(), 0)


func test_a_plain_run_is_not_a_recording() -> void:
	var options: Options = Options.parse(PackedStringArray(["--demo=session"]))
	assert_false(options.recording())
	assert_eq(options.record_fps, 0)
	assert_eq(Options.parse(PackedStringArray(["--record"])).record_fps, Options.DEFAULT_RECORD_FPS)
	assert_eq(Options.parse(PackedStringArray(["--stills=3"])).recording(), true)


func test_bad_recording_options_are_notes() -> void:
	var options: Options = Options.parse(PackedStringArray(["--record-fps=0", "--stills=a,b", "--menu=-1"]))
	assert_eq(options.record_fps, 0)
	assert_eq(options.warnings.size(), 3)


# ---------------------------------------------------------------- the view in recording mode

func test_a_frame_runs_the_simulation_up_to_its_time() -> void:
	_record()
	assert_true(view.load_scene("session"))
	view._show_clip(Recording.time_of_frame(90, 30))
	assert_eq(view.clock.steps, 180, "frame 90 at 30 fps is 3 s")
	view._show_clip(Recording.time_of_frame(91, 30))
	assert_eq(view.clock.steps, 182)
	view._show_clip(Recording.time_of_frame(91, 30))
	assert_eq(view.clock.steps, 182, "the same frame again runs nothing")


func test_a_recording_plays_a_scene_once_and_does_not_start_it_again() -> void:
	_record()
	assert_true(view.load_scene("session"))
	view._show_clip(view.player.duration + 10.0)
	assert_eq(view.restarts, 0)
	assert_gt(view.clock.now, view.player.duration + view.LOOP_PAUSE)


func test_the_scripted_pointer_and_key_caps_are_drawn_in_a_recording() -> void:
	_record()
	assert_true(view.load_scene("arenas"))
	view._show_clip(23.6)
	var state: Dictionary = view.pointer_art.state
	assert_eq((state["pointers"] as Array).size(), 1, "the person's pointer over tab B")
	assert_eq(view.interface.ui["hover"], "B", "the pointer hovers over tab B, so the bar shows B's cards")
	view._show_clip(30.7)
	assert_eq(((view.pointer_art.state["keys"]) as Array)[0]["label"], "TAB", "the key cap of the Tab key at 30.5 s")
	view._show_clip(40.0)
	assert_eq((view.pointer_art.state["pointers"] as Array).size(), 0, "no pointer when no path is on")


func test_the_scripted_follow_menu_opens_and_closes_in_a_recording() -> void:
	_record()
	assert_true(view.load_scene("follow"))
	view._show_clip(15.0)
	assert_false(view.interface.menu_open)
	view._show_clip(17.0)
	assert_true(view.interface.menu_open, "the script opens the menu at 16 s")
	view._show_clip(20.5)
	assert_false(view.interface.menu_open, "and closes it at 19.8 s")


func test_the_scripted_pointer_is_also_drawn_in_demo_mode() -> void:
	assert_true(view.load_scene("multi"))
	view.simulate(60 * 23)
	view._refresh()
	assert_eq((view.pointer_art.state["pointers"] as Array).size(), 1)


func test_a_scene_without_a_script_draws_no_pointer() -> void:
	_record()
	assert_true(view.load_scene("session"))
	view._show_clip(10.0)
	assert_eq((view.pointer_art.state["pointers"] as Array).size(), 0)
	assert_eq((view.pointer_art.state["keys"] as Array).size(), 0)


func test_keys_and_the_mouse_do_nothing_in_a_recording() -> void:
	_record()
	assert_true(view.load_scene("multi"))
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_M
	event.pressed = true
	view._unhandled_key_input(event)
	assert_false(view.sound_model.on, "the M key does not turn sound on")
	var space: InputEventKey = InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	view._unhandled_key_input(space)
	assert_false(view.clock.paused)


func test_the_frames_do_not_read_the_wall_clock() -> void:
	_record()
	view._clip_time = 12.5
	assert_eq(view._wall(), 12.5, "the toast of the switch runs on the clip's time")


func test_the_menu_option_opens_the_sound_menu_for_the_first_seconds() -> void:
	_record()
	view.options.menu_seconds = 3.0
	assert_true(view.load_scene("session"))
	view._show_clip(1.0)
	assert_true(view.sound_model.menu_open)
	view._show_clip(3.5)
	assert_false(view.sound_model.menu_open)


func test_the_empty_room_shows_before_the_first_agent() -> void:
	assert_true(view.load_scene("session"))
	view._refresh()
	await wait_process_frames(2)
	assert_eq(view.arena_view.visible_letters, ["A"] as Array[String], "arena A is there at 0, empty, as in the mockup")


# ---------------------------------------------------------------- the pointer art

func test_the_key_cap_is_one_pixel_lower_while_it_is_pressed() -> void:
	var pressed: Rect2i = PointerArt.key_rect("TAB", 0.05)
	var up: Rect2i = PointerArt.key_rect("TAB", 0.5)
	assert_eq(pressed.position.y, up.position.y + 1)
	assert_eq(pressed.position.x, up.position.x)
	assert_eq(up.end.x, PointerArt.KEY_RIGHT, "its right edge is at 466")
	assert_eq(up.position.y, 206)
	assert_gt(PointerArt.key_rect("RIGHT", 0.5).size.x, PointerArt.key_rect("F", 0.5).size.x, "a longer label makes a wider cap")


func test_the_pointer_art_draws_in_every_state() -> void:
	var node: Node2D = PointerArt.new()
	add_child_autofree(node)
	node.set_state({ "pointers": [{ "x": 100, "y": 100, "ring_ages": [0.1, 0.5, -1.0] }], "keys": [{ "label": "RIGHT", "age": 0.05 }, { "label": "F", "age": 0.9 }] })
	await wait_process_frames(2)
	assert_eq(node.state["keys"].size(), 2)
	node.set_state({ })
