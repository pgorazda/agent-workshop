extends GutTest
## Command-line options.

const Options := preload("res://src/core/options.gd")


func test_default_bridge_address() -> void:
	var options: RefCounted = Options.parse(PackedStringArray())
	assert_eq(options.bridge, "ws://127.0.0.1:8787/ws")
	assert_eq(options.bridge, Options.DEFAULT_BRIDGE)
	assert_false(options.log_events)
	assert_eq(options.warnings.size(), 0)


func test_bridge_argument_sets_the_address() -> void:
	var options: RefCounted = Options.parse(PackedStringArray(["--bridge=ws://127.0.0.1:9000/ws"]))
	assert_eq(options.bridge, "ws://127.0.0.1:9000/ws")
	var secure: RefCounted = Options.parse(PackedStringArray(["--bridge=wss://example.test/ws"]))
	assert_eq(secure.bridge, "wss://example.test/ws")


func test_bad_address_keeps_the_default_and_warns() -> void:
	var options: RefCounted = Options.parse(PackedStringArray(["--bridge=http://127.0.0.1:8787/ws"]))
	assert_eq(options.bridge, Options.DEFAULT_BRIDGE)
	assert_eq(options.warnings.size(), 1)


func test_log_events_flag_and_unknown_arguments() -> void:
	var options: RefCounted = Options.parse(PackedStringArray(["--log-events", "--nonsense"]))
	assert_true(options.log_events)
	assert_eq(options.warnings.size(), 1)


func test_the_options_of_the_live_room() -> void:
	var options: RefCounted = Options.parse(PackedStringArray(["--demo=session", "--speed=2", "--paused", "--clean", "--at=12.5", "--limit=5", "--unfocused-fps=15", "--reduced-motion"]))
	assert_eq(options.demo, "session")
	assert_eq(options.speed, 2.0)
	assert_true(options.paused)
	assert_true(options.clean)
	assert_eq(options.at, 12.5)
	assert_eq(options.penguin_limit, 5)
	assert_eq(options.unfocused_fps, 15)
	assert_true(options.reduced_motion)
	assert_eq(options.warnings.size(), 0)


func test_the_defaults_of_the_live_room() -> void:
	var options: RefCounted = Options.parse(PackedStringArray())
	assert_eq([options.demo, options.timeline, options.speed, options.paused, options.clean, options.at], ["", "", 1.0, false, false, 0.0])
	assert_eq(options.penguin_limit, Options.DEFAULT_PENGUIN_LIMIT)
	assert_eq(options.unfocused_fps, 30)
	assert_false(options.reduced_motion)


func test_bad_values_keep_the_defaults_and_warn() -> void:
	var options: RefCounted = Options.parse(PackedStringArray(["--speed=fast", "--speed=0", "--at=-3", "--limit=0", "--unfocused-fps=x"]))
	assert_eq(options.speed, 1.0)
	assert_eq(options.at, 0.0)
	assert_eq(options.penguin_limit, Options.DEFAULT_PENGUIN_LIMIT)
	assert_eq(options.unfocused_fps, 30)
	assert_eq(options.warnings.size(), 5)


func test_the_arguments_of_the_shot_tool_are_not_a_mistake() -> void:
	var options: RefCounted = Options.parse(PackedStringArray(["--scene=res://src/live.tscn", "--out=a.png", "--frames=3", "--count=2"]))
	assert_eq(options.warnings.size(), 0)


func test_the_options_of_the_arenas() -> void:
	var options: RefCounted = Options.parse(PackedStringArray(["--arena-size=2", "--leave-after=90", "--follow=manual"]))
	assert_eq(options.arena_size, 2)
	assert_true(options.arena_size_set)
	assert_eq(options.leave_after, 90.0)
	assert_true(options.follow_manual)
	assert_eq(options.warnings.size(), 0)
	var defaults: RefCounted = Options.parse(PackedStringArray())
	assert_eq([defaults.arena_size, defaults.arena_size_set, defaults.leave_after, defaults.follow_manual], [4, false, 600.0, false])
	var bad: RefCounted = Options.parse(PackedStringArray(["--arena-size=x", "--leave-after=-1"]))
	assert_eq(bad.arena_size, 4)
	assert_eq(bad.leave_after, 600.0)
	assert_eq(bad.warnings.size(), 2)


func test_the_options_of_the_benchmark() -> void:
	var options: RefCounted = Options.parse(PackedStringArray(["--benchmark=ten", "--benchmark-out=run.csv", "--vsync=off"]))
	assert_eq(options.benchmark, "ten")
	assert_eq(options.benchmark_out, "run.csv")
	assert_true(options.vsync_off)
	assert_eq(options.warnings.size(), 0)
