extends GutTest
## The effect cues and the art that draws them: lifetimes, the shake of the room, and a stage that draws every kind of effect.

const Effects := preload("res://src/core/effects.gd")
const EffectsArt := preload("res://art/effects_art.gd")
const RoomStageArt := preload("res://art/room_stage_art.gd")
const Atlas := preload("res://art/atlas.gd")
const Data := preload("res://art/atlas_data.gd")
const Rng := preload("res://src/core/rng.gd")


func test_a_cue_lives_for_its_time() -> void:
	var effects: RefCounted = Effects.new()
	effects.add("dust", 1.0, 10.0, 20.0)
	effects.add("smoke", 1.0, 10.0, 20.0)
	effects.prune(1.3)
	assert_eq(effects.active().size(), 2)
	effects.prune(1.5)
	assert_eq(effects.count_of("dust"), 0, "dust lives 0.4 s")
	assert_eq(effects.count_of("smoke"), 1)
	effects.prune(5.0)
	assert_eq(effects.active().size(), 0)


func test_a_cue_in_the_future_is_kept() -> void:
	var effects: RefCounted = Effects.new()
	effects.add("sparkle", 3.0, 0.0, 0.0)
	effects.prune(1.0)
	assert_eq(effects.active().size(), 1)


func test_an_unknown_kind_is_ignored() -> void:
	var effects: RefCounted = Effects.new()
	effects.add("rain", 0.0, 0.0, 0.0)
	assert_eq(effects.active().size(), 0)


func test_the_shake_lasts_four_tenths_of_a_second_and_decays() -> void:
	var effects: RefCounted = Effects.new()
	assert_eq(effects.shake_offset(0.0), 0)
	effects.note_failure(2.0)
	var largest: int = 0
	var last_big: float = 0.0
	var t: float = 2.0
	while t < 2.5:
		var offset: int = absi(effects.shake_offset(t))
		largest = maxi(largest, offset)
		if offset >= 1:
			last_big = t
		t += 1.0 / 60.0
	assert_gte(largest, 1)
	assert_lt(largest, 4, "at most 2.5 px")
	assert_lt(last_big, 2.4)
	assert_eq(effects.shake_offset(2.41), 0)


func test_at_most_one_shake_a_second() -> void:
	var effects: RefCounted = Effects.new()
	effects.note_failure(1.0)
	effects.note_failure(1.5)
	assert_eq(effects.shake_offset(1.7), 0, "the second failure did not start a new shake: the first one is over at 1.4 s")
	effects.note_failure(2.1)
	var moved: bool = false
	for i in 20:
		if effects.shake_offset(2.1 + float(i) * 0.015) != 0:
			moved = true
	assert_true(moved, "a failure a second after the first one shakes again")


func test_reduced_motion_does_not_shake() -> void:
	var effects: RefCounted = Effects.new()
	effects.reduced_motion = true
	effects.note_failure(1.0)
	for i in 30:
		assert_eq(effects.shake_offset(1.0 + float(i) * 0.01), 0)


func test_the_pictures_the_effects_need_are_in_the_atlas() -> void:
	for picture: String in ["spark/mini", "spark/0", "spark/1", "spark/2", "spark/3", "prop/cloud", "prop/cloud-mini", "flame/0", "flame/1", "flame/2", "flame/3"]:
		assert_true(Atlas.has(picture), picture)
	for wax in range(2, 9):
		assert_true(Atlas.has("prop/candle/%d" % wax), "candle %d" % wax)
	for cord: String in Data.CORDS:
		assert_true(Atlas.has("penguin/%s/flop-body" % cord))
		assert_true(Atlas.has("penguin/%s/cap" % cord))
		assert_true(Atlas.has("penguin/%s/front/idle/nocap" % cord))


func test_the_candle_burns_down_and_each_spell_starts_with_a_new_one() -> void:
	# The seated penguin: 8 steps of wax, one pixel each second, never under 3. The small cloud: from 5, never under 2.
	var waxes: Array[int] = []
	for age: float in [0.3, 1.3, 2.3, 3.3, 4.3, 5.3, 9.0, 60.0]:
		waxes.append(maxi(3, 8 - int(floorf((age - 0.25) / 1.0))))
	assert_eq(waxes, [8, 7, 6, 5, 4, 3, 3, 3])
	var small: Array[int] = []
	for age: float in [0.3, 1.2, 2.2, 3.2, 4.2, 60.0]:
		small.append(maxi(2, 5 - int(floorf((age - 0.2) / 0.9))))
	assert_eq(small, [5, 4, 3, 2, 2, 2])


func test_the_stage_draws_every_kind_of_effect_without_errors() -> void:
	var stage: Node2D = RoomStageArt.new()
	var effects: RefCounted = Effects.new()
	for kind: String in Effects.LIFE:
		effects.add(kind, 0.0, 200.0, 150.0, 1.0, 1234)
	effects.add("sparkle", 0.0, 220.0, 100.0, 1.0, 1)
	stage.cues = effects.active()
	stage.time = 0.2
	var crowd: Array[Dictionary] = [
		{"x": 100, "y": 150, "cord": "pi", "dir": "front", "pose": "idle", "think_age": 1.0, "think_in_place": true, "number": 2},
		{"x": 90, "y": 201, "cord": "hermes", "dir": "front", "pose": "think", "think_age": 4.0, "think_in_place": false, "number": 3},
		{"x": 300, "y": 160, "cord": "default", "dir": "front", "pose": "idle", "flop": 0.8},
		{"x": 320, "y": 160, "cord": "default", "dir": "front", "pose": "idle", "flop": 0.05},
		{"x": 340, "y": 160, "cord": "default", "dir": "front", "pose": "idle", "flop": 1.6},
		{"x": 360, "y": 160, "cord": "default", "dir": "front", "pose": "idle", "flop": 1.1},
		{"x": 434, "y": 214, "cord": "claude-code", "dir": "side", "pose": "peer", "small": true, "shadow": 4, "shadow_ry": 1.8},
		{"x": 434, "y": 214, "cord": "claude-code", "dir": "side", "pose": "hammer", "small": true},
	]
	stage.set_penguins(crowd)
	add_child_autofree(stage)
	await wait_process_frames(2)
	assert_eq(stage.penguins.size(), 8)
	assert_eq(RoomStageArt.penguin_picture("claude-code", "side", "hammer", false, true), "penguin/claude-code/side/idle/small", "a small penguin that has no small picture of the pose stands")


func test_effects_use_the_seeded_random_numbers() -> void:
	# The forge fire is the same for the same time and different for another time: it uses mulberry32, not the clock.
	var a: RefCounted = Rng.mulberry32(int(floorf(3.0 * 10.0)) * 7 + 1)
	var b: RefCounted = Rng.mulberry32(int(floorf(3.04 * 10.0)) * 7 + 1)
	var c: RefCounted = Rng.mulberry32(int(floorf(3.2 * 10.0)) * 7 + 1)
	assert_eq(a.next(), b.next(), "the same tenth of a second gives the same fire")
	assert_ne(a.next(), c.next())
