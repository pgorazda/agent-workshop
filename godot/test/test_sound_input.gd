extends GutTest
## The sound in the live view, through the real input path: sound starts off, M turns it on (a key becomes an `InputEventKey`
## pushed into the viewport, as in the scripted input test), S opens the menu, and the keys and clicks of the menu work.
## The cues of the actors reach the players. The drawing of the switch and its menu runs for each state. A headless run has no sound
## device: Godot uses the dummy audio driver, and nothing here is heard.

const InputScript := preload("res://test/support/input_script.gd")
const SoundUiArt := preload("res://art/sound_ui_art.gd")
const SoundModel := preload("res://src/core/sound_model.gd")
const TextArt := preload("res://art/text_art.gd")
const Trace := preload("res://test/support/trace.gd")

var view: Node
var driver: InputScript
var _effects_before: int = 0


func before_each() -> void:
	_effects_before = AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Master"))
	var scene: PackedScene = load("res://src/live.tscn")
	view = scene.instantiate()
	add_child(view)
	view.client.set_process(false)
	driver = InputScript.new(view)


func after_each() -> void:
	view.free()
	assert_eq(AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Master")), _effects_before, "the master bus is as it was")


## The centre of a row of the open menu: a tune (0 to 3), no music (4) or the event sounds (5).
func _row_point(row: int) -> Vector2:
	var y: int = (SoundUiArt.row_y(row) if row < 5 else SoundUiArt.events_y(4)) + 4
	return Vector2(float(SoundUiArt.MENU_X + 60), float(y))


func _pill_point() -> Vector2:
	return Vector2(SoundUiArt.PILL.position) + Vector2(SoundUiArt.PILL.size) / 2.0


# ---------------------------------------------------------------- the start

func test_all_sound_starts_off_and_nothing_exists() -> void:
	assert_false(view.sound_model.on)
	assert_false(view.sound_player.running())
	assert_eq(view.sound_player.get_child_count(), 0, "no player node")
	assert_false(view.director.record_sounds, "the actors collect no cues")
	assert_eq(view.sound_player.limiter_index(), -1)
	assert_false(view.sound_model.menu_open)


func test_a_run_with_no_sound_collects_no_cue_and_plays_nothing() -> void:
	assert_true(view.load_scene("multi"))
	view.simulate(60 * 30)
	assert_eq(view.sound_player.plays, 0)
	assert_eq(view.director.take_sound_cues().size(), 0, "nothing was collected")
	assert_eq(view.sound_model.pending_count(), 0)


func test_the_sound_option_starts_with_sound_on() -> void:
	var options: RefCounted = load("res://src/core/options.gd").parse(PackedStringArray(["--sound=oberek"]))
	assert_eq(options.sound, "oberek")
	assert_eq(options.warnings.size(), 0)
	assert_eq(load("res://src/core/options.gd").parse(PackedStringArray([])).sound, "", "no option: all sound off")


# ---------------------------------------------------------------- the keys

func test_m_turns_sound_on_through_the_input_path_and_again_off() -> void:
	driver.push_key(KEY_M)
	assert_true(view.sound_model.on, "M turns sound on")
	assert_true(view.sound_player.running())
	assert_true(view.sound_player.music_playing(), "the default tune plays")
	assert_eq(view.sound_player.tune_loaded, "krakowiak")
	assert_true(view.director.record_sounds, "the actors collect cues now")
	assert_gte(view.sound_player.limiter_index(), 0, "the master limiter is on")
	driver.push_key(KEY_M)
	assert_false(view.sound_model.on, "M turns sound off")
	assert_false(view.sound_player.running())
	assert_false(view.director.record_sounds, "no more cues")
	assert_eq(view.sound_player.limiter_index(), -1)


func test_s_opens_the_menu_and_its_digits_pick_a_tune() -> void:
	driver.push_key(KEY_S)
	assert_true(view.sound_model.menu_open)
	driver.push_key(KEY_3)
	assert_eq(view.sound_model.tune, "oberek")
	assert_eq(view.sound_player.tune_loaded, "oberek")
	driver.push_key(KEY_0)
	assert_eq(view.sound_model.tune, "")
	assert_false(view.sound_player.music_playing())
	driver.push_key(KEY_E)
	assert_false(view.sound_model.events)
	driver.push_key(KEY_ESCAPE)
	assert_false(view.sound_model.menu_open)


func test_1_to_3_are_the_demo_speed_only_while_both_menus_are_closed() -> void:
	assert_true(view.load_scene("multi"))
	driver.push_key(KEY_2)
	assert_eq(view.clock.speed, 2.0, "menus closed: the speed")
	driver.push_key(KEY_1)
	assert_eq(view.clock.speed, 1.0)
	assert_false(view.sound_model.on, "and no tune was picked")
	driver.push_key(KEY_S)
	driver.push_key(KEY_3)
	assert_eq(view.clock.speed, 1.0, "the sound menu is open: 3 is not the speed")
	assert_eq(view.sound_model.tune, "oberek", "it is a tune")
	driver.push_key(KEY_ESCAPE)
	driver.push_key(KEY_3)
	assert_eq(view.clock.speed, 4.0, "the sound menu is closed again: the speed")


func test_the_keys_of_the_follow_menu_are_not_taken_while_the_sound_menu_is_closed() -> void:
	assert_true(view.load_scene("arenas"))
	view.simulate(60 * 9)
	var follow: Dictionary = (view.interface.build(view.director, view.camera, view.clock.now) as Dictionary)["follow"]
	driver.click_at(Vector2((follow["rect"] as Rect2i).get_center()))
	assert_true(view.interface.menu_open, "the follow menu is open")
	driver.push_key(KEY_1)
	assert_false(view.sound_model.on, "1 belongs to the follow menu")
	assert_true(view.interface.menu_open)


func test_the_sound_menu_and_the_follow_menu_are_never_open_together() -> void:
	assert_true(view.load_scene("arenas"))
	view.simulate(60 * 9)
	var follow: Dictionary = (view.interface.build(view.director, view.camera, view.clock.now) as Dictionary)["follow"]
	var follow_point: Vector2 = Vector2((follow["rect"] as Rect2i).get_center())
	driver.click_at(follow_point)
	assert_true(view.interface.menu_open)
	driver.push_key(KEY_S)
	assert_true(view.sound_model.menu_open)
	assert_false(view.interface.menu_open, "S closes the follow menu")
	driver.click_at(follow_point)
	assert_false(view.sound_model.menu_open, "a click elsewhere closes the sound menu")
	assert_false(view.interface.menu_open, "and does nothing else")
	driver.click_at(follow_point)
	assert_true(view.interface.menu_open, "the next click opens the follow menu")
	driver.click_at(_pill_point())
	assert_true(view.sound_model.menu_open, "a click on the sound switch opens its menu")
	assert_false(view.interface.menu_open, "and closes the follow menu")


# ---------------------------------------------------------------- the mouse

func test_a_click_on_the_switch_opens_the_menu_and_a_click_on_a_row_picks_it() -> void:
	driver.click_at(_pill_point())
	assert_true(view.sound_model.menu_open)
	driver.click_at(_row_point(2))
	assert_eq(view.sound_model.tune, "oberek")
	assert_true(view.sound_model.on)
	assert_true(view.sound_player.music_playing())
	driver.click_at(_row_point(5))
	assert_false(view.sound_model.events, "the event sounds line")
	driver.click_at(_row_point(4))
	assert_eq(view.sound_model.tune, "", "no music")
	assert_true(view.sound_model.menu_open, "the menu stays open")
	driver.click_at(_pill_point())
	assert_false(view.sound_model.menu_open)


func test_a_click_elsewhere_closes_the_menu_and_does_nothing_else() -> void:
	driver.click_at(_pill_point())
	driver.click_at(Vector2(30.0, 100.0))
	assert_false(view.sound_model.menu_open)
	assert_false(view.sound_model.on, "nothing was picked")
	driver.click_at(Vector2(30.0, 100.0))
	assert_false(view.sound_model.menu_open, "a click with the menu closed goes to the room as before")


func test_the_mouse_over_a_row_is_the_hover() -> void:
	driver.click_at(_pill_point())
	driver.move_mouse(_row_point(1))
	assert_eq(view.sound_model.hover, 1)
	driver.move_mouse(_row_point(5))
	assert_eq(view.sound_model.hover, SoundModel.ROW_EVENTS)
	driver.move_mouse(Vector2(10.0, 10.0))
	assert_eq(view.sound_model.hover, -1)


# ---------------------------------------------------------------- the cues reach the players

func test_the_events_of_a_scene_make_event_sounds_when_sound_is_on() -> void:
	driver.push_key(KEY_M)
	assert_true(view.load_scene("multi"))
	view.simulate(60 * 40)
	assert_gt(view.sound_player.plays, 3, "tinks, flops, chimes and fanfares of the scene")


func test_the_event_sounds_can_be_off_with_the_music_on() -> void:
	driver.push_key(KEY_S)
	driver.push_key(KEY_E)
	driver.push_key(KEY_2)
	assert_false(view.sound_model.events)
	assert_true(view.sound_player.music_playing())
	assert_true(view.load_scene("multi"))
	view.simulate(60 * 40)
	assert_eq(view.sound_player.plays, 0)
	assert_false(view.director.record_sounds)


func test_a_new_session_forgets_a_cue_that_waits() -> void:
	driver.push_key(KEY_M)
	view.sound_model.offer([{ "name": "fanfare", "t": 99.0, "arena": "A" }] as Array[Dictionary], "A")
	assert_eq(view.sound_model.pending_count(), 1)
	view.restart()
	assert_eq(view.sound_model.pending_count(), 0)


func test_the_arena_of_the_camera_is_known_only_while_it_rests() -> void:
	assert_true(view.load_scene("arenas"))
	view.simulate(60 * 9)
	assert_eq(view.rest_arena(), "B", "the camera rests on arena B, which opened at 7 s")
	view.camera.press("Tab", view.clock.now)
	view.simulate(5)
	assert_eq(view.rest_arena(), "", "the overview is on its way: no arena")
	view.simulate(60 * 3)
	assert_true(view.camera.in_overview())
	assert_eq(view.rest_arena(), "", "the overview shows no arena: only the chime and the fanfare sound")


func test_the_pause_of_a_demo_pauses_the_tune() -> void:
	assert_true(view.load_scene("multi"))
	driver.push_key(KEY_M)
	driver.push_key(KEY_SPACE)
	assert_true(view.clock.paused)
	await wait_process_frames(2)
	assert_true((view.sound_player.get_child(0) as AudioStreamPlayer).stream_paused)
	driver.push_key(KEY_SPACE)
	await wait_process_frames(2)
	assert_false((view.sound_player.get_child(0) as AudioStreamPlayer).stream_paused)


# ---------------------------------------------------------------- the switch

func test_the_places_of_the_switch_and_its_menu_are_those_of_the_mockup() -> void:
	assert_eq(SoundUiArt.PILL, Rect2i(453, 3, 23, 9))
	var rows: Array[int] = []
	for i in 5:
		rows.append(SoundUiArt.row_y(i))
	assert_eq(rows, [42, 53, 64, 75, 86] as Array[int], "four tunes and no music")
	assert_eq(SoundUiArt.events_y(4), 112)
	assert_eq(SoundUiArt.menu_rect(4), Rect2i(326, 15, 150, 126))


func test_the_hit_test_names_what_is_under_the_point() -> void:
	var closed: Dictionary = view.sound_model.ui(0.0)
	assert_eq(SoundUiArt.hit(Vector2(460.0, 7.0), closed)["kind"], "pill")
	assert_eq(SoundUiArt.hit(Vector2(400.0, 50.0), closed)["kind"], "none", "a closed menu has no rows")
	view.sound_model.set_menu(true)
	var open: Dictionary = view.sound_model.ui(0.0)
	assert_eq(SoundUiArt.hit(Vector2(460.0, 7.0), open)["kind"], "pill")
	for i in 4:
		var hit: Dictionary = SoundUiArt.hit(_row_point(i), open)
		assert_eq(hit["kind"], "tune")
		assert_eq(hit["tune"], SoundModel.TUNES[i]["name"])
	assert_eq(SoundUiArt.hit(_row_point(4), open), { "kind": "tune", "tune": "" })
	assert_eq(SoundUiArt.hit(_row_point(5), open), { "kind": "events" })
	assert_eq(SoundUiArt.hit(Vector2(400.0, 30.0), open)["kind"], "menu", "the title of the menu")
	assert_eq(SoundUiArt.hit(Vector2(400.0, 100.0), open)["kind"], "menu", "the line between the rows and the events")
	assert_eq(SoundUiArt.hit(Vector2(400.0, 150.0), open)["kind"], "none", "under the menu")
	assert_eq(SoundUiArt.hit(Vector2(300.0, 50.0), open)["kind"], "none", "left of the menu")
	assert_eq(SoundUiArt.hit(Vector2(325.0, 50.0), open)["kind"], "none", "one pixel left of the menu")
	assert_eq(SoundUiArt.hit(Vector2(326.0, 50.0), open)["kind"], "tune", "the first pixel of the menu")
	assert_eq(SoundUiArt.hit(Vector2(475.0, 50.0), open)["kind"], "tune", "the last pixel of the menu")
	assert_eq(SoundUiArt.hit(Vector2(476.0, 50.0), open)["kind"], "none", "right of the menu")


func test_a_row_is_eleven_pixels_high_from_one_above_its_text() -> void:
	view.sound_model.set_menu(true)
	var open: Dictionary = view.sound_model.ui(0.0)
	var y: int = SoundUiArt.row_y(1)
	assert_eq(SoundUiArt.hit(Vector2(400.0, float(y - 2)), open)["kind"], "tune", "the gap above row 1 belongs to row 0")
	assert_eq(SoundUiArt.hit(Vector2(400.0, float(y - 2)), open)["tune"], "krakowiak")
	assert_eq(SoundUiArt.hit(Vector2(400.0, float(y - 1)), open)["tune"], "kujawiak")
	assert_eq(SoundUiArt.hit(Vector2(400.0, float(y + 9)), open)["tune"], "kujawiak")
	assert_eq(SoundUiArt.hit(Vector2(400.0, float(y + 10)), open)["tune"], "oberek")


func test_the_name_of_the_fourth_tune_has_its_polish_letter_in_the_glyph_atlas() -> void:
	assert_eq(str(SoundModel.TUNES[3]["label"]), "góralski")
	assert_ne(TextArt.glyph_for(TextArt.TINY5, "ó"), TextArt.glyph_name(TextArt.TINY5, "?"), "the o with an acute is in the atlas")


func test_the_switch_draws_in_every_state_without_an_error() -> void:
	var states: Array[Callable] = [
		func() -> void: pass,
		func() -> void: view.sound_model.toggle_all(0.0),
		func() -> void: view.sound_model.set_menu(true),
		func() -> void: view.sound_model.pick_tune("goralski", 0.0),
		func() -> void: view.sound_model.set_hover_from({ "kind": "tune", "tune": "" }),
		func() -> void: view.sound_model.set_hover_from({ "kind": "events" }),
		func() -> void: view.sound_model.toggle_events(0.0),
		func() -> void: view.sound_model.set_menu(false),
		func() -> void: view.sound_model.toggle_all(0.0),
	]
	for change: Callable in states:
		change.call()
		view._sound_changed()
		view._refresh()
		await wait_process_frames(1)
	assert_gt(view.sound_ui.state.size(), 0, "the switch has a state to draw")


func test_the_toast_shows_after_a_change_and_goes_after_two_seconds() -> void:
	driver.push_key(KEY_M)
	view._refresh()
	assert_eq(view.sound_ui.state["toast"], "all sound on   (M)")
	view.sound_model.toast_until = view._wall() - 0.1
	view._refresh()
	assert_eq(view.sound_ui.state["toast"], "", "the toast has expired")
