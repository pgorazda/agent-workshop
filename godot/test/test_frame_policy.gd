extends GutTest
## The frame policy: the frame cap without focus and no drawing when minimized.

const FramePolicy := preload("res://src/core/frame_policy.gd")
const Options := preload("res://src/core/options.gd")


func test_a_window_with_focus_draws_at_sixty_frames_a_second_by_default() -> void:
	assert_eq(FramePolicy.fps_cap(true, false, 30), 60, "the rate of the simulation: more would draw the same picture again")
	assert_eq(FramePolicy.fps_cap(true, false, 30, 120), 120)
	assert_eq(FramePolicy.fps_cap(true, false, 30, 0), 0, "0 means no cap")
	assert_eq(Options.parse(PackedStringArray()).focused_fps, FramePolicy.FOCUSED_FPS)
	assert_eq(Options.parse(PackedStringArray(["--focused-fps=144"])).focused_fps, 144)
	assert_eq(Options.parse(PackedStringArray(["--focused-fps=fast"])).warnings.size(), 1)


func test_a_window_without_focus_draws_at_the_setting() -> void:
	assert_eq(FramePolicy.fps_cap(false, false, 30), 30)
	assert_eq(FramePolicy.fps_cap(false, false, 15), 15)
	assert_eq(FramePolicy.fps_cap(false, false, 0), 0, "0 means no cap")


func test_the_default_is_thirty_frames_a_second() -> void:
	assert_eq(Options.DEFAULT_UNFOCUSED_FPS, 30)
	assert_eq(Options.parse(PackedStringArray()).unfocused_fps, 30)


func test_a_minimized_window_does_not_draw_and_runs_slowly() -> void:
	assert_false(FramePolicy.should_draw(true))
	assert_true(FramePolicy.should_draw(false))
	assert_eq(FramePolicy.fps_cap(true, true, 30), FramePolicy.MINIMIZED_FPS)
	assert_eq(FramePolicy.fps_cap(false, true, 30), FramePolicy.MINIMIZED_FPS)
	assert_lt(FramePolicy.MINIMIZED_FPS, 30)
	assert_gte(FramePolicy.MINIMIZED_MAX_FRAME, 1.0 / float(FramePolicy.MINIMIZED_FPS), "a frame of a minimized window counts as long as it lasts")


func test_the_engine_takes_the_cap_and_the_render_loop_switch() -> void:
	var old_cap: int = Engine.max_fps
	Engine.max_fps = FramePolicy.fps_cap(false, false, 30)
	assert_eq(Engine.max_fps, 30)
	Engine.max_fps = FramePolicy.fps_cap(true, false, 30)
	assert_eq(Engine.max_fps, 60)
	RenderingServer.render_loop_enabled = FramePolicy.should_draw(true)
	assert_false(RenderingServer.render_loop_enabled)
	RenderingServer.render_loop_enabled = FramePolicy.should_draw(false)
	assert_true(RenderingServer.render_loop_enabled)
	Engine.max_fps = old_cap
