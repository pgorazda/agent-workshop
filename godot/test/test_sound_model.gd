extends GutTest
## The sound model: the state, the keys and clicks of the switch and its menu, and the rules for which event cue sounds. The
## model has no audio call, so these tests run with no sound device.

const SoundModel := preload("res://src/core/sound_model.gd")

var model: SoundModel


func before_each() -> void:
	model = SoundModel.new()


func _cue(sound_name: String, t: float, arena: String = "A") -> Dictionary:
	return { "name": sound_name, "t": t, "arena": arena }


## Offers one cue with the sound on, and returns the names that are due at `now`.
func _sounds(cues: Array[Dictionary], rest: String, now: float) -> Array[String]:
	model.offer(cues, rest)
	return model.due(now)


# ---------------------------------------------------------------- the state

func test_all_sound_starts_off() -> void:
	assert_false(model.on)
	assert_eq(model.tune_playing(), "", "no tune plays")
	assert_false(model.events_playing(), "no event sound plays")
	assert_false(model.menu_open)
	assert_eq(model.tune, "krakowiak", "the default tune is chosen, but it does not play")
	assert_true(model.events, "the event sounds are ticked, but they do not sound")


func test_there_are_four_tunes_and_five_event_sounds() -> void:
	var names: Array[String] = []
	for entry in SoundModel.TUNES:
		names.append(str(entry["name"]))
	assert_eq(names, ["krakowiak", "kujawiak", "oberek", "goralski"] as Array[String])
	assert_eq(SoundModel.EVENT_SOUNDS, ["tink", "bell", "flop", "chime", "fanfare"] as Array[String])


func test_m_turns_all_sound_on_and_off_and_keeps_the_tune_and_the_event_setting() -> void:
	model.pick_tune("oberek", 0.0)
	model.toggle_events(0.0)
	model.toggle_all(1.0)
	assert_false(model.on)
	model.toggle_all(2.0)
	assert_true(model.on)
	assert_eq(model.tune_playing(), "oberek", "the tune comes back")
	assert_false(model.events, "the event setting stayed")


func test_picking_a_tune_turns_all_sound_on() -> void:
	model.pick_tune("kujawiak", 0.0)
	assert_true(model.on)
	assert_eq(model.tune_playing(), "kujawiak")


func test_no_music_turns_sound_on_with_event_sounds_only() -> void:
	model.pick_tune("", 0.0)
	assert_true(model.on)
	assert_eq(model.tune_playing(), "")
	assert_true(model.events_playing())


func test_a_tune_that_does_not_exist_changes_nothing() -> void:
	model.pick_tune("polka", 0.0)
	assert_false(model.on)
	assert_eq(model.tune, "krakowiak")
	assert_eq(model.toast, "")


func test_toggling_the_event_sounds_turns_all_sound_on() -> void:
	model.toggle_events(0.0)
	assert_true(model.on, "the mockup does this too")
	assert_false(model.events)
	model.toggle_events(0.0)
	assert_true(model.events)


func test_start_with_sets_the_state_from_a_command_line_value() -> void:
	assert_true(model.start_with("on"))
	assert_true(model.on)
	assert_eq(model.tune_playing(), "krakowiak")
	assert_true(model.start_with("events"))
	assert_eq(model.tune_playing(), "")
	assert_true(model.events_playing())
	assert_true(model.start_with("goralski"))
	assert_eq(model.tune_playing(), "goralski")
	assert_true(model.start_with("off"))
	assert_false(model.on)
	assert_false(model.start_with("loud"), "an unknown value is refused")
	assert_false(model.on, "and changes nothing")


func test_version_counts_the_changes_that_the_player_must_apply() -> void:
	var v: int = model.version
	model.toggle_menu()
	assert_eq(model.version, v, "the menu is not audio")
	model.pick_tune("oberek", 0.0)
	assert_eq(model.version, v + 1)
	model.pick_tune("oberek", 0.0)
	assert_eq(model.version, v + 1, "the same tune again changes nothing")
	model.toggle_all(0.0)
	assert_eq(model.version, v + 2)


# ---------------------------------------------------------------- the toast

func test_each_change_gives_a_toast_that_says_what_changed() -> void:
	model.pick_tune("goralski", 10.0)
	assert_eq(model.toast_at(10.5), "music: góralski")
	model.pick_tune("", 10.0)
	assert_eq(model.toast_at(10.5), "music: off")
	model.toggle_events(10.0)
	assert_eq(model.toast_at(10.5), "event sounds: off")
	model.toggle_events(10.0)
	assert_eq(model.toast_at(10.5), "event sounds: on")
	model.toggle_all(10.0)
	assert_eq(model.toast_at(10.5), "all sound off   (M)")
	model.toggle_all(10.0)
	assert_eq(model.toast_at(10.5), "all sound on   (M)")


func test_a_toast_goes_after_two_seconds() -> void:
	model.pick_tune("oberek", 10.0)
	assert_ne(model.toast_at(11.9), "")
	assert_eq(model.toast_at(12.0), "")
	assert_eq(model.toast_at(99.0), "")


# ---------------------------------------------------------------- the keys

func test_s_opens_and_closes_the_menu_and_esc_closes_it() -> void:
	assert_true(model.key(KEY_S, 0.0))
	assert_true(model.menu_open)
	assert_true(model.key(KEY_S, 0.0))
	assert_false(model.menu_open)
	model.key(KEY_S, 0.0)
	assert_true(model.key(KEY_ESCAPE, 0.0))
	assert_false(model.menu_open)
	assert_false(model.on, "opening and closing the menu does not turn sound on")


func test_esc_goes_on_to_the_camera_when_the_menu_is_closed() -> void:
	assert_false(model.key(KEY_ESCAPE, 0.0), "the overview needs this key")


func test_m_works_with_the_menu_open_and_closed() -> void:
	assert_true(model.key(KEY_M, 0.0))
	assert_true(model.on)
	model.key(KEY_S, 0.0)
	assert_true(model.key(KEY_M, 0.0))
	assert_false(model.on)
	assert_true(model.menu_open, "M does not close the menu")


func test_the_digits_1_to_4_pick_a_tune_and_0_picks_none_while_the_menu_is_open() -> void:
	model.key(KEY_S, 0.0)
	var wanted: Array[String] = ["krakowiak", "kujawiak", "oberek", "goralski"]
	for i in 4:
		assert_true(model.key((KEY_1 + i) as Key, 0.0))
		assert_eq(model.tune, wanted[i], "key %d" % (i + 1))
		assert_true(model.on)
	assert_true(model.key(KEY_0, 0.0))
	assert_eq(model.tune, "", "key 0 is no music")
	assert_true(model.menu_open, "the menu stays open")


func test_the_keypad_digits_work_too() -> void:
	model.key(KEY_S, 0.0)
	assert_true(model.key(KEY_KP_3, 0.0))
	assert_eq(model.tune, "oberek")
	assert_true(model.key(KEY_KP_0, 0.0))
	assert_eq(model.tune, "")


func test_the_digits_are_not_the_sound_models_while_the_menu_is_closed() -> void:
	# 1 to 3 are the speed of a demo then (the view asks `menu_open`), so the model must not take them
	for key: Key in [KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_E]:
		assert_false(model.key(key, 0.0), "key %s" % OS.get_keycode_string(key))
	assert_false(model.on)


func test_digits_above_the_last_tune_are_ignored_in_the_menu() -> void:
	model.key(KEY_S, 0.0)
	assert_false(model.key(KEY_5, 0.0))
	assert_false(model.key(KEY_9, 0.0))
	assert_false(model.on)


func test_e_toggles_the_event_sounds_only_while_the_menu_is_open() -> void:
	assert_false(model.key(KEY_E, 0.0))
	model.key(KEY_S, 0.0)
	assert_true(model.key(KEY_E, 0.0))
	assert_false(model.events)
	assert_true(model.on)


func test_other_keys_go_on() -> void:
	model.key(KEY_S, 0.0)
	for key: Key in [KEY_F, KEY_TAB, KEY_SPACE, KEY_LEFT, KEY_N]:
		assert_false(model.key(key, 0.0), "key %s" % OS.get_keycode_string(key))


# ---------------------------------------------------------------- clicks and hover

func test_a_click_on_the_switch_opens_and_closes_the_menu() -> void:
	assert_true(model.click({ "kind": "pill" }, 0.0))
	assert_true(model.menu_open)
	assert_true(model.click({ "kind": "pill" }, 0.0))
	assert_false(model.menu_open)


func test_a_click_on_a_row_picks_it() -> void:
	model.set_menu(true)
	assert_true(model.click({ "kind": "tune", "tune": "oberek" }, 0.0))
	assert_eq(model.tune_playing(), "oberek")
	assert_true(model.click({ "kind": "tune", "tune": "" }, 0.0))
	assert_eq(model.tune, "")
	assert_true(model.click({ "kind": "events" }, 0.0))
	assert_false(model.events)
	assert_true(model.menu_open, "the menu stays open")


func test_a_click_in_the_menu_on_nothing_does_nothing() -> void:
	model.set_menu(true)
	assert_true(model.click({ "kind": "menu" }, 0.0), "the click is used up")
	assert_true(model.menu_open)
	assert_false(model.on)


func test_a_click_elsewhere_closes_the_open_menu_and_does_nothing_else() -> void:
	model.set_menu(true)
	assert_true(model.click({ "kind": "none" }, 0.0), "the click is used up")
	assert_false(model.menu_open)


func test_a_click_elsewhere_goes_on_while_the_menu_is_closed() -> void:
	assert_false(model.click({ "kind": "none" }, 0.0))


func test_the_hover_follows_the_row_under_the_mouse() -> void:
	model.set_menu(true)
	model.set_hover_from({ "kind": "tune", "tune": "kujawiak" })
	assert_eq(model.hover, 1)
	model.set_hover_from({ "kind": "tune", "tune": "" })
	assert_eq(model.hover, SoundModel.ROW_NO_MUSIC)
	model.set_hover_from({ "kind": "events" })
	assert_eq(model.hover, SoundModel.ROW_EVENTS)
	model.set_hover_from({ "kind": "none" })
	assert_eq(model.hover, -1)


func test_there_is_no_hover_when_the_menu_is_closed() -> void:
	model.set_hover_from({ "kind": "tune", "tune": "oberek" })
	assert_eq(model.hover, -1)


func test_revision_changes_when_something_that_shows_changes() -> void:
	var r: int = model.revision
	model.set_menu(true)
	assert_gt(model.revision, r)
	r = model.revision
	model.set_hover_from({ "kind": "events" })
	assert_gt(model.revision, r)
	r = model.revision
	model.set_hover_from({ "kind": "events" })
	assert_eq(model.revision, r, "the same hover again changes nothing")


# ---------------------------------------------------------------- which event plays which sound

func test_nothing_sounds_while_all_sound_is_off() -> void:
	var cues: Array[Dictionary] = [_cue("tink", 1.0), _cue("chime", 1.0), _cue("fanfare", 1.0)]
	assert_eq(model.offer(cues, "A"), 0)
	assert_eq(model.due(2.0), [] as Array[String])
	assert_eq(model.pending_count(), 0, "nothing was kept")


func test_nothing_sounds_while_the_event_sounds_are_off_even_with_music_on() -> void:
	model.pick_tune("oberek", 0.0)
	model.toggle_events(0.0)
	assert_eq(model.tune_playing(), "oberek")
	assert_eq(model.offer([_cue("flop", 1.0)] as Array[Dictionary], "A"), 0)
	assert_eq(model.pending_count(), 0)


func test_each_cue_gives_its_own_sound() -> void:
	model.start_with("on")
	for sound_name: String in SoundModel.EVENT_SOUNDS:
		model.clear_pending()
		assert_eq(_sounds([_cue(sound_name, 1.0)] as Array[Dictionary], "A", 1.0), [sound_name] as Array[String], sound_name)


func test_an_unknown_cue_is_dropped() -> void:
	model.start_with("on")
	assert_eq(model.offer([_cue("boom", 1.0)] as Array[Dictionary], "A"), 0)


func test_the_sounds_of_one_arena_sound_only_when_the_camera_rests_on_it() -> void:
	model.start_with("on")
	for sound_name: String in ["tink", "bell", "flop"]:
		model.clear_pending()
		assert_eq(_sounds([_cue(sound_name, 1.0, "B")] as Array[Dictionary], "A", 1.0), [] as Array[String], "%s from B while the camera rests on A" % sound_name)
		assert_eq(_sounds([_cue(sound_name, 1.0, "A")] as Array[Dictionary], "A", 1.0), [sound_name] as Array[String], "%s from A" % sound_name)


func test_the_sounds_of_one_arena_do_not_sound_while_the_camera_moves_or_shows_the_overview() -> void:
	model.start_with("on")
	# the view gives "" for a camera that moves or shows the overview
	for sound_name: String in ["tink", "bell", "flop"]:
		assert_eq(_sounds([_cue(sound_name, 1.0, "A")] as Array[Dictionary], "", 1.0), [] as Array[String], sound_name)


func test_the_chime_and_the_fanfare_sound_from_every_arena_and_while_the_camera_moves() -> void:
	model.start_with("on")
	for sound_name: String in ["chime", "fanfare"]:
		for rest: String in ["A", "B", ""]:
			model.clear_pending()
			assert_eq(_sounds([_cue(sound_name, 1.0, "C")] as Array[Dictionary], rest, 1.0), [sound_name] as Array[String], "%s from C, the camera at '%s'" % [sound_name, rest])


func test_a_sound_waits_until_its_time() -> void:
	model.start_with("on")
	model.offer([_cue("fanfare", 5.15)] as Array[Dictionary], "A")
	assert_eq(model.due(5.0), [] as Array[String], "the fanfare follows the cheer by 0.15 s")
	assert_eq(model.pending_count(), 1)
	assert_eq(model.due(5.15), ["fanfare"] as Array[String])
	assert_eq(model.due(5.2), [] as Array[String], "it sounds once")


func test_due_gives_the_sounds_in_the_order_of_their_times() -> void:
	model.start_with("on")
	model.offer([_cue("fanfare", 2.0), _cue("flop", 1.8), _cue("chime", 1.9)] as Array[Dictionary], "A")
	assert_eq(model.due(2.1), ["flop", "chime", "fanfare"] as Array[String])


func test_a_cue_that_is_very_late_is_dropped() -> void:
	# a window that was not shown, or a long frame: the cue is not played as a burst afterwards
	model.start_with("on")
	model.offer([_cue("flop", 1.0), _cue("chime", 9.8)] as Array[Dictionary], "A")
	assert_eq(model.due(10.0), ["chime"] as Array[String], "the flop is 9 s late: dropped")
	assert_eq(model.pending_count(), 0)


func test_two_cues_of_one_sound_in_one_instant_count_as_one() -> void:
	model.start_with("on")
	var cues: Array[Dictionary] = [_cue("tink", 1.0), _cue("tink", 1.01), _cue("tink", 1.02), _cue("flop", 1.0)]
	assert_eq(model.offer(cues, "A"), 2)
	assert_eq(model.due(1.1), ["tink", "flop"] as Array[String])
	assert_eq(model.offer([_cue("tink", 1.44)] as Array[Dictionary], "A"), 1, "the next stroke is far enough away")


func test_the_list_of_waiting_cues_has_a_limit() -> void:
	model.start_with("on")
	for i in SoundModel.MAX_PENDING + 20:
		model.offer([_cue("tink", 100.0 + float(i))] as Array[Dictionary], "A")
	assert_eq(model.pending_count(), SoundModel.MAX_PENDING)


func test_turning_all_sound_off_forgets_the_waiting_cues() -> void:
	model.start_with("on")
	model.offer([_cue("fanfare", 5.15)] as Array[Dictionary], "A")
	model.toggle_all(0.0)
	assert_eq(model.pending_count(), 0)
	model.toggle_all(0.0)
	assert_eq(model.due(6.0), [] as Array[String], "the fanfare is not played after sound comes back")


func test_a_new_session_forgets_the_waiting_cues() -> void:
	model.start_with("on")
	model.offer([_cue("fanfare", 5.15)] as Array[Dictionary], "A")
	model.clear_pending()
	assert_eq(model.due(6.0), [] as Array[String])
	assert_eq(model.offer([_cue("tink", 0.0)] as Array[Dictionary], "A"), 1, "the new session starts its own list")


func test_the_ui_dictionary_has_what_the_switch_draws() -> void:
	model.pick_tune("oberek", 5.0)
	var ui: Dictionary = model.ui(5.5)
	assert_eq(ui["on"], true)
	assert_eq(ui["tune"], "oberek")
	assert_eq(ui["events"], true)
	assert_eq(ui["open"], false)
	assert_eq(ui["toast"], "music: oberek")
	assert_eq((ui["tunes"] as Array).size(), 4)
	assert_eq(model.ui(50.0)["toast"], "", "the toast has gone")
