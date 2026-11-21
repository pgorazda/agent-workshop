extends GutTest
## The players, under the dummy audio driver (a headless run has no sound device). Each sound file loads, plays and stops
## with no error, nothing exists while sound is off, and a tune is loaded when it is chosen and freed when another one is chosen.
## No test here listens to anything: a test can only see that a player says it plays.

const SoundModel := preload("res://src/core/sound_model.gd")
const SoundPlayer := preload("res://src/view/sound_player.gd")

const LOOP_FORWARD := 1

var model: SoundModel
var player: SoundPlayer
var _effects_before: int = 0


func before_each() -> void:
	model = SoundModel.new()
	player = SoundPlayer.new()
	add_child(player)
	_effects_before = AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Master"))


func after_each() -> void:
	player.free()
	assert_eq(AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Master")), _effects_before, "the master bus is as it was")


func _children_count() -> int:
	return player.get_child_count()


func test_the_audio_driver_of_a_headless_run_is_the_dummy_driver() -> void:
	# the tests rely on it: a real device would make a sound while the tests run
	assert_eq(DisplayServer.get_name(), "headless", "this run has no window, so Godot uses the dummy audio driver")


func test_nothing_exists_while_sound_is_off() -> void:
	player.apply(model)
	assert_false(player.running())
	assert_eq(_children_count(), 0, "no player node")
	assert_eq(player.limiter_index(), -1, "no effect on the master bus")
	assert_eq(player.tune_loaded, "", "no tune in memory")
	assert_false(player.music_playing())
	assert_eq(AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Master")), _effects_before)


func test_a_sound_asked_for_while_sound_is_off_does_nothing() -> void:
	player.play_event("flop")
	assert_eq(player.plays, 0)
	assert_false(player.running())


func test_each_tune_loads_plays_and_loops() -> void:
	for entry in SoundModel.TUNES:
		var tune_name: String = str(entry["name"])
		model.pick_tune(tune_name, 0.0)
		player.apply(model)
		assert_true(player.running(), tune_name)
		assert_eq(player.tune_loaded, tune_name)
		assert_true(player.music_playing(), "%s plays" % tune_name)
		assert_eq(player.failures.size(), 0, "no file failed to load")
		var stream: AudioStream = player.get_child(0).stream
		assert_not_null(stream, "%s has a stream" % tune_name)
		assert_eq(int(stream.get("loop_mode")), LOOP_FORWARD, "%s loops (the .import file says so)" % tune_name)
	await get_tree().process_frame
	assert_true(player.music_playing(), "it still plays a frame later")


func test_each_event_sound_loads_plays_and_stops() -> void:
	model.start_with("events")
	player.apply(model)
	assert_true(player.running())
	assert_false(player.music_playing(), "no music: event sounds only")
	for sound_name: String in SoundModel.EVENT_SOUNDS:
		var before: int = player.plays
		player.play_event(sound_name)
		assert_eq(player.plays, before + 1, "%s started" % sound_name)
		await get_tree().process_frame
		var found: bool = false
		for child in player.get_children():
			var node: AudioStreamPlayer = child as AudioStreamPlayer
			if node != null and node.playing and node.stream != null and node.stream.resource_path.get_file() == "%s.wav" % sound_name:
				found = true
				node.stop()
				assert_false(node.playing, "%s stops" % sound_name)
		assert_true(found, "%s plays on one of the event players" % sound_name)
	assert_eq(player.failures.size(), 0)


func test_an_unknown_sound_name_does_nothing() -> void:
	model.start_with("events")
	player.apply(model)
	player.play_event("boom")
	assert_eq(player.plays, 0)


func test_the_pool_has_four_players_and_a_fifth_sound_at_once_is_dropped() -> void:
	model.start_with("events")
	player.apply(model)
	for i in SoundPlayer.POOL_SIZE + 2:
		player.play_event("bell")
	assert_eq(player.plays, SoundPlayer.POOL_SIZE, "a sound with no free player is dropped, not queued")


func test_turning_sound_off_stops_everything_and_frees_what_it_held() -> void:
	model.start_with("kujawiak")
	player.apply(model)
	assert_true(player.music_playing())
	var held: WeakRef = weakref(player.get_child(0).stream)
	player.play_event("chime")
	model.toggle_all(0.0)
	player.apply(model)
	await get_tree().process_frame
	assert_false(player.running())
	assert_false(player.music_playing())
	assert_eq(player.limiter_index(), -1, "the limiter is gone")
	assert_eq(_children_count(), 0, "the player nodes are gone")
	await get_tree().create_timer(0.3).timeout
	assert_null(held.get_ref(), "the tune is out of memory")


func test_a_tune_is_loaded_when_chosen_and_freed_when_another_is_chosen() -> void:
	model.pick_tune("krakowiak", 0.0)
	player.apply(model)
	var old: WeakRef = weakref(player.get_child(0).stream)
	assert_not_null(old.get_ref(), "the chosen tune is loaded")
	model.pick_tune("oberek", 0.0)
	player.apply(model)
	await get_tree().create_timer(0.3).timeout
	assert_eq(player.tune_loaded, "oberek")
	assert_null(old.get_ref(), "the old tune is freed")


func test_no_music_frees_the_tune_but_keeps_the_event_sounds() -> void:
	model.pick_tune("goralski", 0.0)
	player.apply(model)
	var old: WeakRef = weakref(player.get_child(0).stream)
	model.pick_tune("", 0.0)
	player.apply(model)
	await get_tree().create_timer(0.3).timeout
	assert_false(player.music_playing())
	assert_null(old.get_ref(), "the tune is freed")
	player.play_event("tink")
	assert_eq(player.plays, 1, "the event sounds still sound")


func test_turning_the_event_sounds_off_frees_them_and_the_tune_goes_on() -> void:
	model.pick_tune("oberek", 0.0)
	player.apply(model)
	player.play_event("flop")
	assert_eq(player.plays, 1)
	model.toggle_events(0.0)
	player.apply(model)
	player.play_event("flop")
	assert_eq(player.plays, 1, "no event sound now")
	assert_true(player.music_playing(), "the tune goes on")


func test_a_new_tune_starts_from_its_beginning() -> void:
	model.pick_tune("krakowiak", 0.0)
	player.apply(model)
	var node: AudioStreamPlayer = player.get_child(0)
	await get_tree().create_timer(0.3).timeout
	assert_gt(node.get_playback_position(), 0.1, "the first tune has been playing")
	model.pick_tune("oberek", 0.0)
	player.apply(model)
	assert_lt(node.get_playback_position(), 0.1, "the new tune starts at the beginning")
	# the same tune again is not a new start
	await get_tree().create_timer(0.3).timeout
	var before: float = node.get_playback_position()
	model.pick_tune("oberek", 0.0)
	player.apply(model)
	assert_gt(node.get_playback_position(), before - 0.05, "the same tune goes on")


func test_the_limiter_is_on_the_master_bus_while_sound_is_on() -> void:
	model.start_with("on")
	player.apply(model)
	var at: int = player.limiter_index()
	assert_gte(at, 0, "there is a limiter")
	var effect: AudioEffect = AudioServer.get_bus_effect(AudioServer.get_bus_index("Master"), at)
	assert_eq(effect.get_class(), "AudioEffectHardLimiter")
	assert_almost_eq(float(effect.get("ceiling_db")), SoundPlayer.LIMITER_CEILING_DB, 0.001)
	player.apply(model)
	assert_eq(AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Master")), _effects_before + 1, "applying again adds no second limiter")


func test_the_pause_of_the_clock_pauses_the_players() -> void:
	model.start_with("on")
	player.apply(model)
	var music: AudioStreamPlayer = player.get_child(0)
	player.set_paused(true)
	assert_true(music.stream_paused)
	player.set_paused(false)
	assert_false(music.stream_paused)


func test_a_player_that_starts_while_the_clock_is_paused_starts_paused() -> void:
	player.set_paused(true)
	model.start_with("on")
	player.apply(model)
	var music: AudioStreamPlayer = player.get_child(0)
	assert_true(music.stream_paused, "the tune starts paused")
	player.play_event("tink")
	var started: AudioStreamPlayer = null
	for child in player.get_children():
		var node: AudioStreamPlayer = child as AudioStreamPlayer
		if node != music and node.stream != null and node.stream.resource_path.get_file() == "tink.wav":
			started = node
	assert_not_null(started)
	assert_true(started.stream_paused, "so does an event sound")


func test_a_tune_in_memory_costs_a_few_megabytes_and_leaves_with_the_tune() -> void:
	var before: float = float(Performance.get_monitor(Performance.MEMORY_STATIC))
	model.pick_tune("kujawiak", 0.0)
	player.apply(model)
	var during: float = float(Performance.get_monitor(Performance.MEMORY_STATIC))
	model.toggle_all(0.0)
	player.apply(model)
	await get_tree().create_timer(0.3).timeout
	var after: float = float(Performance.get_monitor(Performance.MEMORY_STATIC))
	gut.p("static memory: %.2f MB before, %.2f MB with kujawiak playing, %.2f MB after sound is off again" % [before / 1048576.0, during / 1048576.0, after / 1048576.0])
	assert_gt(during - before, 2.0 * 1048576.0, "the tune (3 MB of samples) is in memory")
	assert_lt(after - before, 0.5 * 1048576.0, "and it is gone when sound is off")
