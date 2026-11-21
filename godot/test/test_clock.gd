extends GutTest
## The simulation clock: fixed steps, whatever the frame rate.

const Clock := preload("res://src/core/clock.gd")


func test_a_step_is_one_sixtieth_of_a_second() -> void:
	assert_almost_eq(Clock.STEP, 1.0 / 60.0, 1e-12)


func test_the_number_of_steps_follows_the_time_not_the_frame_rate() -> void:
	for frame_rate: int in [24, 30, 60, 144, 240]:
		var clock: RefCounted = Clock.new()
		var steps: int = 0
		for _frame: int in frame_rate:
			steps += clock.advance(1.0 / float(frame_rate))
		assert_almost_eq(float(steps), 60.0, 1.0, "one second at %d fps gives 60 steps (+-1)" % frame_rate)


func test_now_is_the_step_count_times_the_step() -> void:
	var clock: RefCounted = Clock.new()
	for i in 6000:
		clock.tick()
	assert_eq(clock.steps, 6000)
	assert_almost_eq(clock.now, 100.0, 1e-9)


func test_a_long_frame_counts_at_most_a_tenth_of_a_second() -> void:
	var clock: RefCounted = Clock.new()
	assert_eq(clock.advance(30.0), 6, "30 s of frame time count as 0.1 s: 6 steps")


func test_a_paused_clock_gives_no_steps() -> void:
	var clock: RefCounted = Clock.new()
	clock.paused = true
	assert_eq(clock.advance(0.05), 0)
	clock.paused = false
	assert_gt(clock.advance(0.05), 0)


func test_the_speed_multiplies_the_steps() -> void:
	var clock: RefCounted = Clock.new()
	clock.speed = 4.0
	var steps: int = 0
	for _frame in 60:
		steps += clock.advance(1.0 / 60.0)
	assert_almost_eq(float(steps), 240.0, 2.0)


func test_the_speed_list_has_a_first_and_a_last() -> void:
	var clock: RefCounted = Clock.new()
	for i in 10:
		clock.faster()
	assert_eq(clock.speed, 4.0)
	for i in 10:
		clock.slower()
	assert_eq(clock.speed, 0.5)


func test_reset_keeps_the_speed_and_the_pause() -> void:
	var clock: RefCounted = Clock.new()
	clock.speed = 2.0
	clock.paused = true
	clock.tick()
	clock.reset()
	assert_eq([clock.steps, clock.now, clock.speed, clock.paused], [0, 0.0, 2.0, true])
