extends GutTest
## The tour: the stops of `demo/tour.json`, the clip clock against the scene clock, the lit parts of a stop, the drawing of a
## callout, and the tour as it runs in the live view.

const Tour := preload("res://src/core/tour.gd")
const TourHoles := preload("res://src/view/tour_holes.gd")
const TourArt := preload("res://art/tour_art.gd")
const TimelinePlayer := preload("res://src/net/timeline_player.gd")
const Recording := preload("res://src/core/recording.gd")

const HOLE_KINDS: Array[String] = ["rect", "ell", "agent", "card", "helper", "near"]

var tour: Tour
var player: RefCounted
var view: Node


func before_each() -> void:
	player = TimelinePlayer.load_file("res://demo/tour.json")
	tour = Tour.from_dictionary(player.tour)


func _view() -> void:
	var scene: PackedScene = load("res://src/live.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.client.set_process(false)
	view._recording = true
	view.options.record_fps = 30


# ---------------------------------------------------------------- the file

func test_the_tour_file_has_31_stops_and_four_agents() -> void:
	assert_not_null(tour)
	assert_eq(tour.stops.size(), 31)
	assert_eq(player.options.get("bar"), "cards", "the tour shows the top line and the cards from the first agent on")
	var agents: Dictionary = { }
	for item: Dictionary in player.events:
		agents[(item["event"] as RefCounted).session] = true
	assert_eq(agents.keys().size(), 4, "claude-code, opencode, pi and hermes")


func test_the_stops_are_in_order_and_every_hole_is_a_known_kind() -> void:
	var last: float = -1.0
	for stop in tour.stops:
		assert_gte(float(stop["at"]), last, "stops in the order of the scene time")
		last = float(stop["at"])
		assert_gt(float(stop["dur"]), 4.0, "a stop lasts at least 4.4 s, as the mockup's readTime gives")
		assert_true(["event", "thing", "title"].has(stop["kind"]))
		for hole: Dictionary in stop["holes"]:
			var known: int = 0
			for kind in HOLE_KINDS:
				known += 1 if hole.has(kind) else 0
			assert_gte(known, 1, "a hole of a known kind in %s" % stop["title"])
		assert_lte(float(stop["at"]), tour.scene_end, "no stop after the end of the story")


func test_the_events_in_the_file_have_the_mockups_times() -> void:
	# the first agent: session_start at 0.6 s, the tool of the map table straight after its pop and wait
	var first: Dictionary = player.events[0]
	assert_eq((first["event"] as RefCounted).type, "session_start")
	assert_almost_eq(float(first["t"]), 0.6, 1e-9)


# ---------------------------------------------------------------- the clip clock and the scene clock

func test_the_clip_is_the_story_and_every_stop() -> void:
	var total: float = tour.scene_end
	for stop in tour.stops:
		total += float(stop["dur"])
	assert_almost_eq(tour.clip_duration(), total, 1e-9)
	assert_between(tour.clip_duration(), 270.0, 290.0, "about 4.7 minutes, as the mockup's tour")


func test_a_stop_stands_the_scene_still_while_the_clip_runs() -> void:
	var stop: Dictionary = tour.stops[2]
	var begins: float = tour.scene_to_clip(float(stop["at"]))
	assert_almost_eq(begins, float(stop["at"]) + float(tour.stops[0]["dur"]) + float(tour.stops[1]["dur"]), 1e-9, "the two stops before it come first")
	var before: Dictionary = tour.at(begins - 0.5)
	assert_eq(before["index"], -1, "not in a stop yet")
	assert_almost_eq(float(before["t"]), float(stop["at"]) - 0.5, 1e-9)
	var inside: Dictionary = tour.at(begins + 1.0)
	assert_eq(inside["index"], 2)
	assert_eq(inside["stop"], stop)
	assert_almost_eq(float(inside["t"]), float(stop["at"]), 1e-12, "the scene time stands still")
	assert_almost_eq(float(inside["age"]), 1.0, 1e-9)
	var late: Dictionary = tour.at(begins + float(stop["dur"]) - 0.01)
	assert_almost_eq(float(late["t"]), float(stop["at"]), 1e-12)
	# three stops share the time 1.05: the scene goes on only after the last of them
	var last: Dictionary = tour.stops[4]
	var after: Dictionary = tour.at(begins + float(stop["dur"]) + float(tour.stops[3]["dur"]) + float(last["dur"]) + 0.2)
	assert_eq(after["index"], -1)
	assert_almost_eq(float(after["t"]), float(stop["at"]) + 0.2, 1e-9, "the scene goes on after the stops of that moment")


func test_two_stops_at_one_time_follow_each_other() -> void:
	# THE ARENA is at the same scene time as WELCOME: the clip goes from the first to the second at 10 s
	assert_eq(tour.stops[0]["at"], tour.stops[1]["at"])
	assert_eq(tour.at(5.0)["index"], 0)
	assert_eq(tour.at(10.5)["index"], 1)
	assert_almost_eq(float(tour.at(10.5)["t"]), 0.0, 1e-12)


func test_the_scene_time_never_goes_back_and_ends_at_the_end_of_the_story() -> void:
	var last: float = -1.0
	var clip: float = 0.0
	while clip < tour.clip_duration() + 3.0:
		var t: float = float(tour.at(clip)["t"])
		assert_gte(t, last - 1e-12, "at clip %.2f" % clip)
		last = t
		clip += 0.37
	assert_almost_eq(float(tour.at(tour.clip_duration() + 100.0)["t"]), tour.scene_end, 1e-9)


func test_scene_to_clip_is_the_inverse_of_at_outside_the_stops() -> void:
	for s: float in [0.3, 5.0, 20.0, 33.3, 41.0]:
		var clip: float = tour.scene_to_clip(s)
		var at: Dictionary = tour.at(clip)
		if int(at["index"]) < 0:
			assert_almost_eq(float(at["t"]), s, 1e-9, "scene time %.1f" % s)


func test_a_tour_without_stops_is_not_a_tour() -> void:
	assert_null(Tour.from_dictionary({ "stops": [] }))
	assert_null(Tour.from_dictionary({ }))


# ---------------------------------------------------------------- the live view

func test_the_tour_plays_in_a_recording_with_the_scene_clock_stopped_in_a_stop() -> void:
	_view()
	assert_true(view.load_scene("tour"))
	assert_not_null(view._tour)
	view._show_clip(12.0)
	assert_eq(view.clock.steps, 0, "THE ARENA stops the scene at 0")
	assert_eq(view.tour_art.state["stop"]["title"], "THE ARENA")
	assert_eq(view.tour_art.state["step"], 2)
	view._show_clip(18.0)
	assert_eq(view.clock.steps, 0, "still stopped")
	var clip: float = tour.scene_to_clip(1.05) + 1.0
	view._show_clip(clip)
	assert_eq(view.tour_art.state["stop"]["title"], "EVENT: SESSION START")
	assert_eq(view.clock.steps, Recording.steps_at_time(1.05), "the scene is at the stop's time")
	view._show_clip(clip + 5.0)
	assert_eq(view.clock.steps, Recording.steps_at_time(1.05), "and has not moved in 5 s of the clip")
	view._show_clip(tour.scene_to_clip(1.05) + float(tour.stops[2]["dur"]) + float(tour.stops[3]["dur"]) + float(tour.stops[4]["dur"]) + 3.0)
	assert_gt(view.clock.steps, Recording.steps_at_time(1.05), "after the stops of that moment the scene goes on")


func test_the_lit_parts_of_a_stop_are_worked_out_from_the_live_scene() -> void:
	_view()
	assert_true(view.load_scene("tour"))
	var clip: float = tour.scene_to_clip(float(tour.stops[2]["at"])) + 1.0
	view._show_clip(clip)
	var holes: Array[Dictionary] = view.tour_art.state["holes"]
	assert_gt(holes.size(), 2, "the penguin, its chip or label, and the top line")
	var penguin: RefCounted = view.director.penguin_with_number(1)
	assert_not_null(penguin)
	var found: bool = false
	for hole in holes:
		if hole.has("ell") and absi(int(hole["ell"][0]) - roundi(penguin.position.x)) <= 1:
			found = true
	assert_true(found, "an ellipse round the penguin")
	# a card of the bar
	var card: Variant = TourHoles.card_rect(view.interface.ui, 1)
	assert_not_null(card)
	assert_eq((card as Array)[1], 243, "the cards are the row at y 243")


func test_the_focus_stop_lights_whoever_has_the_focus() -> void:
	_view()
	assert_true(view.load_scene("tour"))
	var focus_stop: int = -1
	for i in tour.stops.size():
		if tour.stops[i]["title"] == "FOCUS":
			focus_stop = i
	assert_gt(focus_stop, 0)
	view._show_clip(tour.scene_to_clip(float(tour.stops[focus_stop]["at"])) + 1.0 + 0.0)
	var focus_number: Variant = view.camera.focus_of(view.camera.arena_shown())
	assert_not_null(focus_number)
	var actor: RefCounted = view.director.penguin_with_number(int(focus_number))
	var holes: Array[Dictionary] = view.tour_art.state["holes"]
	assert_gt(holes.size(), 1)
	assert_almost_eq(float(holes[0]["ell"][0]), roundf(actor.position.x), 1.0, "the first hole is the focused penguin")


func test_every_stop_of_the_tour_draws_with_its_holes() -> void:
	_view()
	assert_true(view.load_scene("tour"))
	for i in tour.stops.size():
		var clip: float = tour.scene_to_clip(float(tour.stops[i]["at"])) + float(tour.stops[i]["dur"]) * 0.5
		for j in i:
			if float(tour.stops[j]["at"]) == float(tour.stops[i]["at"]):
				clip += float(tour.stops[j]["dur"])
		view._show_clip(clip)
		var title: String = str((view.tour_art.state.get("stop", { }) as Dictionary).get("title", ""))
		assert_eq(title, tour.stops[i]["title"], "stop %d is on at %.1f s" % [i + 1, clip])


func test_after_the_end_the_tour_shows_no_stop() -> void:
	_view()
	assert_true(view.load_scene("tour"))
	view._show_clip(tour.clip_duration() + 0.5)
	assert_true(view.tour_art.state.is_empty())
	assert_almost_eq(view.clock.now, tour.scene_end, 0.05)


func test_the_tour_in_a_window_runs_on_the_frame_time() -> void:
	var scene: PackedScene = load("res://src/live.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.client.set_process(false)
	assert_true(view.load_scene("tour"))
	view._tour_frame(0.05)
	view._tour_frame(0.05)
	assert_almost_eq(view._clip_time, 0.1, 1e-9)
	view.clock.paused = true
	view._tour_frame(1.0)
	assert_almost_eq(view._clip_time, 0.1, 1e-9, "a pause stops the clip clock")
	view.clock.paused = false
	view.clock.speed = 2.0
	view._tour_frame(0.05)
	assert_almost_eq(view._clip_time, 0.2, 1e-9, "the speed counts for the clip clock")


func test_the_room_with_one_agent_shows_the_chip_and_the_cards_in_the_tour() -> void:
	_view()
	assert_true(view.load_scene("tour"))
	view._show_clip(tour.scene_to_clip(8.0))
	assert_eq(view.interface.ui["mode"], "cards", "the top line and one card, not the log of a lone agent")
	assert_false(view.arena_view.stage_of("A").solo)


# ---------------------------------------------------------------- the art

func test_the_lit_runs_of_a_rectangle_and_an_ellipse() -> void:
	var holes: Array = [{ "rect": [10, 20, 30, 5] }, { "ell": [100, 50, 10, 10] }]
	assert_eq(TourArt.spans(holes, 19), [])
	assert_eq(TourArt.spans(holes, 20), [[10, 40]])
	assert_eq(TourArt.spans(holes, 24), [[10, 40]])
	assert_eq(TourArt.spans(holes, 25), [])
	var row: Array = TourArt.spans(holes, 50)
	assert_eq(row, [[90, 110]], "the middle row of the ellipse is its full width")
	assert_eq(TourArt.spans([{ "rect": [50, 20, 10, 5] }, { "rect": [10, 20, 10, 5] }], 21), [[10, 20], [50, 60]], "sorted from the left")


func test_the_dim_covers_the_screen_except_the_lit_runs() -> void:
	var rects: Array[Rect2i] = TourArt.dim_rects([{ "rect": [10, 20, 30, 5] }])
	var covered: int = 0
	for rect in rects:
		covered += rect.size.x * rect.size.y
	assert_eq(covered, 480 * 270 - 30 * 5)
	assert_eq(TourArt.dim_rects([]).size(), 270, "no hole: one rectangle for each row")


func test_the_dashes_of_the_outline_move_with_the_age() -> void:
	var rect: Dictionary = { "rect": [10, 10, 20, 8] }
	var a: Array[Vector2i] = TourArt.outline_points(rect, 0.0)
	var b: Array[Vector2i] = TourArt.outline_points(rect, 0.17)
	assert_gt(a.size(), 20)
	assert_ne(a, b, "after 1/6 s the dashes have moved on")
	for point in a:
		var on_edge: bool = point.x == 9 or point.x == 30 or point.y == 9 or point.y == 18
		assert_true(on_edge, "only the line just outside the box")
	var ellipse: Array[Vector2i] = TourArt.outline_points({ "ell": [100, 100, 20, 10] }, 0.0)
	assert_gt(ellipse.size(), 10)


func test_the_fade_of_a_stop_is_0_at_its_ends_and_1_in_the_middle() -> void:
	assert_eq(TourArt.fade_of(0.0, 5.0), 0.0)
	assert_almost_eq(TourArt.fade_of(0.09, 5.0), 0.5, 1e-9)
	assert_eq(TourArt.fade_of(2.5, 5.0), 1.0)
	assert_almost_eq(TourArt.fade_of(4.91, 5.0), 0.5, 1e-9)
	assert_eq(TourArt.fade_of(5.0, 5.0), 0.0)


func test_a_callout_goes_next_to_the_first_lit_part_and_covers_nothing_lit() -> void:
	var holes: Array = [{ "rect": [104, 50, 52, 36] }]
	var at: Vector2i = TourArt.place(120, 40, holes, null, false)
	assert_eq(at, Vector2i(168, 48), "to the right of the first part, centred on it")
	var lit: Rect2i = Rect2i(104, 50, 52, 36).grow(3)
	assert_false(lit.intersects(Rect2i(at, Vector2i(120, 40))))
	assert_eq(TourArt.place(100, 40, [], null, true), Vector2i(190, 96), "centred in the room")
	assert_eq(TourArt.place(100, 40, holes, [7, 9], false), Vector2i(7, 9), "a place that the stop asks for")
	var wide: Array = [{ "rect": [3, 3, 474, 226] }]
	assert_eq(TourArt.place(60, 30, wide, null, false), Vector2i(210, 96), "nowhere fits: the middle")


func test_the_size_of_a_callout_follows_its_text() -> void:
	var small: Dictionary = { "kind": "thing", "title": "A", "lines": ["short"] }
	var tall: Dictionary = { "kind": "thing", "title": "A", "lines": ["short", "one", "two"] }
	var wide: Dictionary = { "kind": "thing", "title": "A", "lines": ["a much longer line of words than the first one had"] }
	assert_eq(TourArt.callout_size(tall, 1, 31).y, TourArt.callout_size(small, 1, 31).y + 18)
	assert_gt(TourArt.callout_size(wide, 1, 31).x, TourArt.callout_size(small, 1, 31).x)
	var title: Dictionary = { "kind": "title", "title": "WELCOME", "heading": "AGENT WORKSHOP", "lines": ["x"] }
	assert_eq(TourArt.callout_size(title, 1, 31).y, TourArt.callout_size(small, 1, 31).y + 20)


func test_a_quoted_line_is_in_cobalt_without_the_quote_mark() -> void:
	assert_eq(TourArt._plain("` done"), "done")
	assert_eq(TourArt._plain("plain"), "plain")


func test_the_art_draws_every_stop_with_no_error() -> void:
	var node: Node2D = TourArt.new()
	add_child_autofree(node)
	for stop in tour.stops:
		node.set_state({ "stop": stop, "holes": [{ "rect": [104, 50, 52, 36] }, { "ell": [140, 124, 30, 20] }], "age": 1.0, "step": 3, "steps": 31 })
		await wait_process_frames(1)
	assert_true(true, "drawn without an error")
