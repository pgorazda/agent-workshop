extends GutTest
## The levels of the sound files, and the master limiter (phase G-7). Each file has its own limiter from the mockup's mixer, so each file
## alone stays below full scale. A tune and an event sound can add up above it (`tools/sound-levels.mjs` measures how far, from the
## files). This test checks the files' own peaks, and then measures the master bus itself: sounds that add up far above full scale are
## played under the dummy audio driver, and an `AudioEffectCapture` after the limiter reads what leaves the bus.
##
## The capture needs real time (the dummy driver mixes at the pace of a real device), so the measuring tests take about a second each.
## Nothing here says how it sounds. It says that the level is held.

const SoundModel := preload("res://src/core/sound_model.gd")
const SoundPlayer := preload("res://src/view/sound_player.gd")

## Full scale is 1.0 on the bus. The limiter holds the level at its ceiling (-1 dBFS is 0.891); a small tolerance covers the shape of its release.
const FULL_SCALE := 1.0
const CEILING_TOLERANCE := 1.03
const BUS := "Master"


func _samples(sound_name: String) -> PackedInt32Array:
	var stream: AudioStream = load("res://art/sound/%s.wav" % sound_name)
	var data: PackedByteArray = stream.get("data")
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(floori(data.size() / 2.0))
	for i in out.size():
		out[i] = data.decode_s16(i * 2)
	return out


func _peak(sound_name: String) -> float:
	var peak: int = 0
	for value in _samples(sound_name):
		peak = maxi(peak, absi(value))
	return float(peak) / 32768.0


func test_each_file_stays_below_full_scale_on_its_own() -> void:
	var loudest: float = 0.0
	for entry in SoundModel.TUNES:
		var peak: float = _peak(str(entry["name"]))
		assert_lt(peak, 0.9, "%s: the peak %.3f is below full scale with some room" % [entry["name"], peak])
	for sound_name: String in SoundModel.EVENT_SOUNDS:
		var peak: float = _peak(sound_name)
		loudest = maxf(loudest, peak)
		assert_lt(peak, 0.9, "%s: the peak %.3f" % [sound_name, peak])
	gut.p("the loudest event sound peaks at %.1f dBFS" % (20.0 * log(loudest) / log(10.0)))


func test_the_loudest_tune_and_the_loudest_event_sound_can_add_up_above_full_scale() -> void:
	# this is why the master limiter exists: the sum of the two largest peaks
	var tune_peak: float = 0.0
	for entry in SoundModel.TUNES:
		tune_peak = maxf(tune_peak, _peak(str(entry["name"])))
	var event_peak: float = 0.0
	for sound_name: String in SoundModel.EVENT_SOUNDS:
		event_peak = maxf(event_peak, _peak(sound_name))
	var gain: float = pow(10.0, SoundPlayer.MUSIC_VOLUME_DB / 20.0)
	var worst: float = tune_peak * gain + event_peak
	gut.p("worst case, peaks aligned: %.3f of full scale (%.1f dBFS), with the tune at %.0f dB" % [worst, 20.0 * log(worst) / log(10.0), SoundPlayer.MUSIC_VOLUME_DB])
	assert_gt(worst, FULL_SCALE, "the sum of the peaks is above full scale: the master limiter is needed")


## Plays a tune and four event sounds that start in the same frame (they add up to far more than full scale), and returns the largest
## sample that leaves the master bus in `seconds`. `with_limiter` false turns the limiter off for a control run.
func _measure_bus_peak(with_limiter: bool, seconds: float) -> float:
	var model: SoundModel = SoundModel.new()
	model.pick_tune("oberek", 0.0)
	var player: SoundPlayer = SoundPlayer.new()
	add_child(player)
	player.apply(model)
	var bus: int = AudioServer.get_bus_index(BUS)
	var limiter_at: int = player.limiter_index()
	AudioServer.set_bus_effect_enabled(bus, limiter_at, with_limiter)
	var capture: AudioEffectCapture = AudioEffectCapture.new()
	capture.buffer_length = 0.5
	AudioServer.add_bus_effect(bus, capture)
	await get_tree().process_frame
	var peak: float = 0.0
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	var next_burst: int = 0
	while Time.get_ticks_msec() < until:
		if Time.get_ticks_msec() >= next_burst:
			next_burst = Time.get_ticks_msec() + 250
			for i in SoundPlayer.POOL_SIZE:
				player.play_event("flop")
		var available: int = capture.get_frames_available()
		if available > 0:
			for frame: Vector2 in capture.get_buffer(available):
				peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		await get_tree().process_frame
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	player.free()
	return peak


func test_the_master_bus_stays_at_the_limiter_ceiling_when_sounds_add_up() -> void:
	var without: float = await _measure_bus_peak(false, 1.2)
	var held: float = await _measure_bus_peak(true, 1.2)
	var ceiling: float = pow(10.0, SoundPlayer.LIMITER_CEILING_DB / 20.0)
	gut.p("master bus peak: %.3f without the limiter, %.3f with it (ceiling %.3f, full scale 1.000)" % [without, held, ceiling])
	assert_gt(without, FULL_SCALE, "control: without the limiter four sounds and a tune go above full scale")
	assert_gt(held, 0.1, "control: sound reached the capture (the bus works)")
	assert_lt(held, ceiling * CEILING_TOLERANCE, "with the limiter nothing goes above its ceiling")
	assert_lt(held, FULL_SCALE, "and nothing reaches full scale")
