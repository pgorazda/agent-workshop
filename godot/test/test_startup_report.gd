extends GutTest
## The report of the start-up times (`--startup-report=<file>`) and the options that go with the cost measurements.

const StartupReport := preload("res://src/core/startup_report.gd")
const Options := preload("res://src/core/options.gd")


func test_a_mark_keeps_its_first_time() -> void:
	var report: StartupReport = StartupReport.new()
	report.mark("ready_begin", 1000)
	report.mark("ready_begin", 5000)
	assert_eq(report.marks["ready_begin"], 1000)


func test_the_report_is_complete_after_the_frames_that_it_waits_for() -> void:
	var report: StartupReport = StartupReport.new()
	for i in StartupReport.FRAMES - 1:
		report.frame_drawn()
	assert_false(report.is_complete())
	report.frame_drawn()
	assert_true(report.is_complete())


func test_the_json_has_the_marks_the_frame_times_and_the_system_time() -> void:
	var report: StartupReport = StartupReport.new()
	report.mark("ready_begin", 2_000_000)
	report.mark("atlas_loaded", 2_040_000)
	report.process_deltas.append(133.0)
	for i in 3:
		report.frame_drawn()
	var data: Variant = JSON.parse_string(report.to_json())
	assert_typeof(data, TYPE_DICTIONARY)
	var marks: Dictionary = (data as Dictionary)["marks_ms"]
	assert_almost_eq(float(marks["ready_begin"]), 2000.0, 1e-6)
	assert_almost_eq(float(marks["atlas_loaded"]), 2040.0, 1e-6)
	assert_true(marks.has("first_draw"))
	assert_eq(((data as Dictionary)["frame_ms"] as Array).size(), 2, "the time between three frames: two numbers")
	assert_eq(((data as Dictionary)["process_delta_ms"] as Array)[0], 133.0)
	assert_gt(float((data as Dictionary)["unix_ms_at_first_draw"]), 1.0e12, "the time of the system clock, in milliseconds")


func test_the_options_of_the_cost_work() -> void:
	var options: RefCounted = Options.parse(PackedStringArray(["--startup-report=out.json", "--frame-stats", "--focused-fps=30", "--shots=a:1"]))
	assert_eq(options.startup_report, "out.json")
	assert_true(options.frame_stats)
	assert_eq(options.focused_fps, 30)
	assert_eq(options.warnings.size(), 0, "the argument of a tool is not a mistake")
	assert_eq(Options.parse(PackedStringArray()).forced_focus, -1, "the window follows the system by default")
	assert_eq(Options.parse(PackedStringArray(["--force-focus=false"])).forced_focus, 0)
	assert_eq(Options.parse(PackedStringArray(["--force-focus=true"])).forced_focus, 1)
