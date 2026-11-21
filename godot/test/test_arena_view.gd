extends GutTest
## The camera view: where the world is for a pose, which rooms are drawn, the filter at each scale, the free places and the
## page numbers of a wide view. The pictures themselves are looked at by a person (README.md).

const ArenaView := preload("res://src/view/arena_view.gd")
const ArenaRules := preload("res://src/core/arena_rules.gd")
const Camera := preload("res://src/core/camera.gd")
const Director := preload("res://src/core/director.gd")
const Trace := preload("res://test/support/trace.gd")
const RoomStageArtType := preload("res://art/room_stage_art.gd")

var view: ArenaView
var director: RefCounted
var camera: Camera


func before_each() -> void:
	view = ArenaView.new()
	add_child_autofree(view)
	director = Director.new()
	director.set_arena_size(1)
	director.limit = 100
	camera = Camera.new({ "follow": { "activity": false, "open": false } })
	director.attach_camera(camera)


func _agents(count: int) -> void:
	for n in count:
		director.handle_event(Trace.ev("thinking", { }, "main", "claude-code", "s%d" % n))


func _pose(cx: float, cy: float, s: float) -> ArenaRules.Pose:
	return ArenaRules.Pose.new(cx, cy, s)


func test_one_arena_is_on_whole_pixels_at_scale_one() -> void:
	var t: Dictionary = ArenaView.transform_of(_pose(0.5, 0.5, 1.0))
	assert_eq(t["scale"], 1.0)
	assert_eq(t["origin"], Vector2(0, 0))
	var b: Rect2 = ArenaView.screen_rect("B", _pose(1.5, 0.5, 1.0))
	assert_eq(b, Rect2(0, 0, 480, 232), "arena B fills the view when the camera is on it")
	var moving: Dictionary = ArenaView.transform_of(_pose(0.5127, 0.5127, 1.0))
	assert_eq(moving["origin"], (moving["origin"] as Vector2).round(), "in a slide the room still stays on whole pixels")


func test_a_page_is_at_half_size_and_a_wide_view_is_smaller() -> void:
	var page: Dictionary = ArenaView.transform_of(ArenaRules.page_pose(0))
	assert_almost_eq(float(page["scale"]), 0.5, 1e-9)
	assert_eq(ArenaView.screen_rect("A", ArenaRules.page_pose(0)).size, Vector2(240, 116))
	assert_eq(ArenaView.screen_rect("D", ArenaRules.page_pose(0)).position, Vector2(240, 116), "D is the bottom right cell")
	var wide: Dictionary = ArenaView.transform_of(_pose(4.0, 1.0, 8.0))
	assert_almost_eq(float(wide["scale"]), 0.125, 1e-9)


func test_the_gutter_is_between_pages() -> void:
	var pose: ArenaRules.Pose = ArenaRules.page_pose(0)
	var b: Rect2 = ArenaView.screen_rect("B", pose)
	var e: Rect2 = ArenaView.screen_rect("E", pose)
	assert_almost_eq(e.position.x - b.end.x, 0.1 * 480.0 * 0.5, 1e-6, "0.1 of a room: 24 px at the scale of a page")


func test_only_the_rooms_in_view_are_given_their_data() -> void:
	_agents(8)
	camera.advance(1.0)
	view.update_view(director, camera, 1.0)
	assert_eq(view.visible_letters, ["A"] as Array[String])
	assert_true((view.stages["A"] as Node2D).visible)
	assert_false((view.stages["B"] as Node2D).visible)
	var before: int = view.rooms_updated
	view.update_view(director, camera, 1.0)
	assert_eq(view.rooms_updated - before, 1, "one room is updated in a frame, not eight")


func test_the_overview_shows_the_four_rooms_of_a_page_with_the_smooth_filter() -> void:
	_agents(6)
	camera.advance(1.0)
	camera.press("Tab", 1.0)
	camera.advance(2.0)
	view.update_view(director, camera, 2.0)
	assert_eq(view.visible_letters, ["A", "B", "C", "D"] as Array[String], "the page of A: E and F are on the next page")
	assert_true(view.smooth)
	assert_eq((view.stages["A"] as Node2D).texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	assert_eq((view.stages["A"] as Node2D).scale, Vector2.ONE)
	assert_almost_eq(view.world.scale.x, 0.5, 1e-9)
	await wait_process_frames(2) # the smooth world draws without an error
	camera.press("Esc", 2.1)
	camera.advance(3.0)
	view.update_view(director, camera, 3.0)
	assert_false(view.smooth)
	assert_eq((view.stages["A"] as Node2D).texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)


func test_a_far_room_leaves_out_the_glow_the_effects_and_the_shadows() -> void:
	_agents(12)
	camera.advance(1.0)
	camera.click_tab("L", 1.0)
	camera.advance(1.2)
	var found_far: bool = false
	var found_near: bool = false
	var t: float = 1.2
	while t < 3.0:
		t += 0.05
		camera.advance(t)
		view.update_view(director, camera, t)
		for letter in view.visible_letters:
			var far: bool = (view.stages[letter] as RoomStageArtType).far
			found_far = found_far or far
			found_near = found_near or not far
		if view.drawn_pose.s > ArenaView.FAR_FROM:
			for letter in view.visible_letters:
				assert_true((view.stages[letter] as RoomStageArtType).far, "wider than %s rooms: far" % ArenaView.FAR_FROM)
	assert_true(found_far, "a fly across three pages widens the view")
	assert_true(found_near, "and a room at a small width is drawn in full")


func test_the_page_numbers_show_in_a_wide_view_and_the_target_page_is_gold() -> void:
	_agents(40)
	camera.advance(1.0)
	camera.click_tab("Z", 1.0)
	camera.advance(1.3)
	var t: float = 1.3
	var numbers: bool = false
	var gold_texts: Array[String] = []
	while t < 2.4:
		t += 0.03
		camera.advance(t)
		view.update_view(director, camera, t)
		if view.overlay.page_labels.size() > 0:
			numbers = true
			assert_gt(view.overlay.label_alpha, 0.0)
		for label: Dictionary in view.overlay.page_labels:
			if bool(label["gold"]) and not gold_texts.has(str(label["text"])):
				gold_texts.append(str(label["text"]))
	assert_true(numbers, "a fly across six pages widens the view enough for the numbers")
	assert_eq(gold_texts, ["7"] as Array[String], "the page of Z is the only one in gold, whenever it is in view")
	camera.advance(4.0)
	view.update_view(director, camera, 4.0)
	assert_eq(view.overlay.page_labels.size(), 0, "no numbers once the camera has arrived")


func test_a_free_place_of_a_page_in_view_is_a_dark_cell() -> void:
	_agents(6)
	camera.advance(1.0)
	camera.press("Tab", 1.0)
	camera.advance(2.0)
	camera.press("Right", 2.0)
	camera.advance(3.5)
	view.update_view(director, camera, 3.5)
	assert_eq(camera.pages.size(), 2)
	assert_eq(view.visible_letters, ["E", "F"] as Array[String])
	assert_eq(view.backdrop.free_cells.size(), 2, "G and H are free places")
	var cell: Rect2 = view.backdrop.free_cells[0]
	assert_eq(cell.size, Vector2(238, 114), "one pixel gap on each side, as in the mockup")


func test_the_room_of_a_closed_arena_is_removed() -> void:
	_agents(3)
	camera.advance(1.0)
	view.update_view(director, camera, 1.0)
	assert_true(view.stages.has("A"))
	camera.arena_closed("C", 1.1)
	camera.advance(1.3)
	view.update_view(director, camera, 1.3)
	await wait_process_frames(1)
	assert_false(view.stages.has("C"))


func test_the_sign_says_agent_workshop_for_one_arena_and_the_letter_for_several() -> void:
	_agents(1)
	camera.advance(1.0)
	view.update_view(director, camera, 1.0)
	assert_eq((view.stages["A"] as RoomStageArtType).letter, "")
	_agents(2)
	camera.advance(2.0)
	view.update_view(director, camera, 2.0)
	assert_eq((view.stages["A"] as RoomStageArtType).letter, "A")


func test_the_new_arena_ribbon_shows_when_the_camera_arrives() -> void:
	camera = Camera.new()
	director = Director.new()
	director.set_arena_size(1)
	director.attach_camera(camera)
	director.sync_time(3.0)
	_agents(1)
	director.handle_event(Trace.ev("thinking", { }, "main", "claude-code", "s9"))
	camera.advance(3.1)
	camera.advance(4.0)
	assert_eq(camera.arena_shown(), "B")
	assert_not_null(camera.ribbon)
	var t: float = float((camera.ribbon as Dictionary)["t"]) + 0.5
	view.update_view(director, camera, t)
	await wait_process_frames(2) # the ribbon and the sparkles draw without an error
	assert_almost_eq((view.stages["B"] as RoomStageArtType).ribbon_age, 0.5, 1e-9)
	view.update_view(director, camera, t + 3.0)
	assert_eq((view.stages["B"] as RoomStageArtType).ribbon_age, -1.0, "the ribbon is gone after 2.6 s")


func test_reduced_motion_fades_instead_of_moving() -> void:
	camera = Camera.new({ "reduced_motion": true })
	director = Director.new()
	director.set_arena_size(1)
	director.attach_camera(camera)
	_agents(2)
	camera.advance(1.0)
	camera.click_tab("B", 1.0)
	camera.advance(1.05)
	var start: float = float(camera.log[0]["t"])
	view.update_view(director, camera, start + 0.01)
	assert_eq(view.drawn_pose.cx, 0.5, "the old arena is still there at the start of the cut")
	assert_gt(view.drawn_alpha, 0.5)
	view.update_view(director, camera, start + 0.075)
	assert_lt(view.drawn_alpha, 0.1, "dark in the middle of the cut")
	view.update_view(director, camera, start + 0.14)
	assert_eq(view.drawn_pose.cx, 1.5, "the new arena at the end")


func test_arena_at_finds_the_room_under_a_point() -> void:
	_agents(6)
	camera.advance(1.0)
	camera.press("Tab", 1.0)
	camera.advance(2.0)
	assert_eq(view.arena_at(Vector2(100, 50), camera, 2.0), "A")
	assert_eq(view.arena_at(Vector2(300, 50), camera, 2.0), "B")
	assert_eq(view.arena_at(Vector2(100, 200), camera, 2.0), "C")
	assert_eq(view.arena_at(Vector2(300, 200), camera, 2.0), "D")


func test_the_ribbon_has_the_width_of_its_label() -> void:
	const RibbonArt := preload("res://art/ribbon_art.gd")
	assert_gt(RibbonArt.ribbon_width("ARENA AM"), RibbonArt.ribbon_width("ARENA B"), "a longer name makes a wider ribbon")
	assert_eq(RibbonArt.LIFE, 2.6)
