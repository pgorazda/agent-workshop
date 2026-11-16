extends GutTest
## The sound files in art/sound/ load as streams, and the import settings are right: the four tunes loop, the five
## event sounds do not. The test only loads the files and reads their properties. It plays nothing.
##
## The code does not name the stream class. The license check keeps sound-making classes out of the code outside
## art/, and a stream is only loaded here. Properties are read with get().

const FOLDER := "res://art/sound/"
## The length of one loop in seconds. It is bars * beats * 60 / tempo for the whole loop (two passes of the melody).
const TUNES: Dictionary = {
	"krakowiak": 1280.0 / 23.0, # 64 bars of 2 beats at 138 beats a minute
	"kujawiak": 480.0 / 7.0, # 32 bars of 3 beats at 84
	"oberek": 60.0, # 64 bars of 3 beats at 192
	"goralski": 40.0, # 40 bars of 2 beats at 120
}
const EVENT_SOUNDS: Array[String] = ["tink", "bell", "flop", "chime", "fanfare"]
## The sample rates of the files stay near this rate. The render tool moves a tune's rate by 0.1% at most, so that the loop
## is a whole number of render blocks.
const NOMINAL_RATE := 22050
const RATE_TOLERANCE := 0.001
## The values of the stream's properties (the enums of the stream class).
const FORMAT_16_BITS := 1
const LOOP_DISABLED := 0
const LOOP_FORWARD := 1
## The jump between the last and the first sample of a loop. The render tool measured 10 steps at most.
const MAX_SEAM_JUMP := 50


func _stream(sound_name: String) -> AudioStream:
	var path := "%s%s.wav" % [FOLDER, sound_name]
	assert_true(ResourceLoader.exists(path), "%s exists as a resource (was the project imported?)" % path)
	var stream := load(path) as AudioStream
	assert_not_null(stream, "%s loads as an audio stream" % path)
	return stream


func _frames(stream: AudioStream) -> int:
	var data: PackedByteArray = stream.get("data")
	return floori(data.size() / 2.0)


func test_each_tune_loads_and_has_the_length_of_its_loop() -> void:
	for tune: String in TUNES:
		var stream := _stream(tune)
		if stream == null:
			continue
		assert_almost_eq(stream.get_length(), float(TUNES[tune]), 0.001, "%s: the length is one loop" % tune)


func test_each_tune_loops_over_the_whole_file() -> void:
	for tune: String in TUNES:
		var stream := _stream(tune)
		if stream == null:
			continue
		assert_eq(int(stream.get("loop_mode")), LOOP_FORWARD, "%s: loops forward" % tune)
		assert_eq(int(stream.get("loop_begin")), 0, "%s: the loop begins at the first sample" % tune)
		assert_eq(int(stream.get("loop_end")), _frames(stream), "%s: the loop ends at the last sample" % tune)


func test_each_event_sound_loads_and_does_not_loop() -> void:
	for sound_name in EVENT_SOUNDS:
		var stream := _stream(sound_name)
		if stream == null:
			continue
		assert_eq(int(stream.get("loop_mode")), LOOP_DISABLED, "%s: plays once" % sound_name)
		assert_between(stream.get_length(), 0.05, 2.0, "%s: a short sound" % sound_name)


func test_the_format_is_16_bit_mono_near_the_nominal_rate() -> void:
	var names: Array[String] = EVENT_SOUNDS.duplicate()
	names.append_array(Array(TUNES.keys(), TYPE_STRING, "", null))
	for sound_name in names:
		var stream := _stream(sound_name)
		if stream == null:
			continue
		assert_eq(int(stream.get("format")), FORMAT_16_BITS, "%s: 16 bit, not compressed" % sound_name)
		assert_false(bool(stream.get("stereo")), "%s: mono" % sound_name)
		var rate := int(stream.get("mix_rate"))
		assert_almost_eq(float(rate), float(NOMINAL_RATE), NOMINAL_RATE * RATE_TOLERANCE, "%s: the rate %d is near %d" % [sound_name, rate, NOMINAL_RATE])
		assert_almost_eq(float(_frames(stream)) / rate, stream.get_length(), 0.001, "%s: the data fit the length" % sound_name)


func test_a_tune_joins_its_end_to_its_start_without_a_jump() -> void:
	for tune: String in TUNES:
		var stream := _stream(tune)
		if stream == null:
			continue
		var data: PackedByteArray = stream.get("data")
		var last := data.decode_s16(data.size() - 2)
		var first := data.decode_s16(0)
		assert_lte(absi(last - first), MAX_SEAM_JUMP, "%s: last sample %d, first sample %d" % [tune, last, first])


func test_no_file_reaches_full_scale() -> void:
	var names: Array[String] = EVENT_SOUNDS.duplicate()
	names.append_array(Array(TUNES.keys(), TYPE_STRING, "", null))
	for sound_name in names:
		var stream := _stream(sound_name)
		if stream == null:
			continue
		var data: PackedByteArray = stream.get("data")
		var peak := 0
		for i in range(0, data.size(), 2):
			peak = maxi(peak, absi(data.decode_s16(i)))
		assert_lt(peak, 32767, "%s: no sample at full scale" % sound_name)
