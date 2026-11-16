extends GutTest
## The drawing of the interface (phase G-6): the parts that are data (the focus ring, the text widths, the colours of the states), and
## a smoke test that draws every kind of bar, the overview, the follow menu, the notices and the chips for a moment of each scene.
## The pictures themselves were looked at by a person (see the README); a headless run draws nothing that a test can compare.

const Ui := preload("res://art/ui_kit.gd")
const TextArt := preload("res://art/text_art.gd")
const BarArt := preload("res://art/bar_art.gd")
const CrowdArt := preload("res://art/crowd_art.gd")
const Data := preload("res://art/atlas_data.gd")

var view: Node


func before_each() -> void:
	var scene: PackedScene = load("res://src/live.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.client.set_process(false)


# ---------------------------------------------------------------- data

func test_the_focus_ring_is_the_pixels_between_0_62_and_1_of_the_radius() -> void:
	var rects: Array[Rect2i] = Ui.ring_rects(50.0, 40.0, 13.0, 4.6)
	assert_gt(rects.size(), 5)
	var inside: Dictionary = { }
	for rect in rects:
		assert_eq(rect.size.y, 1, "one row each")
		for x in range(rect.position.x, rect.end.x):
			inside[Vector2i(x, rect.position.y)] = true
	for y in range(30, 50):
		for x in range(30, 70):
			var dx: float = (float(x) + 0.5 - 50.0) / 13.0
			var dy: float = (float(y) + 0.5 - 40.0) / 4.6
			var d: float = dx * dx + dy * dy
			assert_eq(inside.has(Vector2i(x, y)), d <= 1.0 and d > 0.62, "pixel %d, %d" % [x, y])
	assert_true(inside.has(Vector2i(50, 35)) or inside.has(Vector2i(49, 35)), "the top of the ring is there")
	assert_false(inside.has(Vector2i(50, 40)), "the middle is empty")


func test_a_text_with_the_cross_is_measured_with_the_bitmap_of_the_cross() -> void:
	var plain: int = TextArt.width(TextArt.TINY5, " exit 1")
	assert_eq(TextArt.rich_width(TextArt.TINY5, "✗ exit 1"), plain + 7, "the cross is 5 pixels wide and 2 pixels of space")
	assert_eq(TextArt.rich_width(TextArt.TINY5, "abc"), TextArt.width(TextArt.TINY5, "abc"))


func test_a_chip_is_as_wide_as_its_number_and_five_pixels() -> void:
	assert_eq(Ui.chip_width(7), TextArt.width(TextArt.TINY5, "7") + 5)
	assert_gt(Ui.chip_width(12), Ui.chip_width(7), "a number of two digits is wider")


func test_the_cord_colours_are_the_ones_of_the_atlas_and_an_unknown_one_is_grey() -> void:
	for cord: String in Data.CORDS:
		assert_eq(Ui.cord_color(cord), Color.html(str(Data.CORDS[cord])))
	assert_eq(Ui.cord_color("something-new"), Color.html(str(Data.CORDS["default"])))


func test_the_rug_colours_repeat_every_five_arenas() -> void:
	assert_eq(Ui.rug_color(0), Ui.rug_color(5))
	assert_ne(Ui.rug_color(0), Ui.rug_color(1))
	assert_ne(Ui.rug_dark(0), Ui.rug_color(0))


func test_the_light_is_green_gold_or_red() -> void:
	assert_eq(BarArt.light_color("connected"), Ui.GREEN)
	assert_eq(BarArt.light_color("demo"), Ui.GREEN)
	assert_eq(BarArt.light_color("connecting"), Ui.GOLD)
	assert_eq(BarArt.light_color("reconnecting"), Ui.GOLD)
	assert_eq(BarArt.light_color("lost"), Ui.RED)


func test_a_waiting_state_blinks_a_failure_is_red_and_a_new_page_blinks_green() -> void:
	assert_eq(BarArt.state_color("WAIT", 0.0), Ui.GOLD)
	assert_eq(BarArt.state_color("WAIT", 0.5), null, "off for the second half of 0.8 s")
	assert_eq(BarArt.state_color("FAIL", 0.5), Ui.RED)
	assert_eq(BarArt.state_color("NEW", 0.0), Ui.GREEN)
	assert_eq(BarArt.state_color("NEW", 0.3), null)
	assert_eq(BarArt.state_color("run", 0.0), null)
	assert_eq(BarArt.state_color("idle", 0.0), null)


func test_the_blink_has_a_period_of_0_8_seconds() -> void:
	assert_true(Ui.blink_on(0.0))
	assert_true(Ui.blink_on(0.39))
	assert_false(Ui.blink_on(0.41))
	assert_true(Ui.blink_on(0.81))


func test_the_follow_marks_are_four_pixels_wide() -> void:
	for kind: String in BarArt.KINDS:
		for row: String in BarArt.GLYPH[kind]:
			assert_eq(row.length(), 4, kind)


# ---------------------------------------------------------------- the drawing runs

func _draw_scene(scene_name: String, seconds: float) -> void:
	assert_true(view.load_scene(scene_name), scene_name)
	view.simulate(int(seconds / view.clock.STEP))
	view._refresh()
	await wait_process_frames(2)


func test_every_bar_and_room_is_drawn_without_an_error() -> void:
	for entry: Array in [["session", 12.5], ["multi", 17.0], ["arenas", 11.5], ["arenas", 14.5], ["follow", 27.5], ["many", 20.0]]:
		await _draw_scene(str(entry[0]), float(entry[1]))
		assert_false((view.bar.ui as Dictionary).is_empty(), "%s: the bar has its data" % entry[0])
	assert_eq(view.bar.ui["mode"], "arenas")


func test_the_overview_and_the_menu_are_drawn() -> void:
	await _draw_scene("arenas", 12.0)
	view.camera.press("Tab", view.clock.now)
	view.simulate(60)
	view.interface.menu_open = true
	view.interface.hover_point = Vector2(120, 60)
	view._refresh()
	await wait_process_frames(2)
	assert_not_null(view.overview_art.ui["overview"])
	assert_not_null(view.overview_art.ui["menu"])
	assert_eq(view.overview_art.ui["hover"], view.overview_art.ui["overview"]["cells"][0]["letter"])


func test_the_notices_are_stacked_with_a_counter_for_many_waiting_agents() -> void:
	# seven agents wait at once in one arena: the oldest is in front and the "+6" counts the others
	await _draw_scene("multi", 1.0)
	var list: Array[Dictionary] = []
	for n in 7:
		list.append({ "number": n + 1, "cord": "pi", "framework": "pi", "session": "s%d" % n, "target": "git push --force-with-lease origin main", "x": 236.0, "approved": false })
	view.set_process(false)
	view.stage.notices = list
	view.stage.queue_redraw()
	await wait_process_frames(2)
	assert_eq(view.stage.notices.size(), 7, "the room drew seven notices (an error in the drawing would fail the run)")
	assert_eq(CrowdArt.NOTICE_BEHIND_MAX, 4, "at most four notices show behind the front one")


func test_a_room_is_drawn_with_chips_a_focus_tag_a_notice_and_a_turn_ribbon() -> void:
	await _draw_scene("multi", 25.0)
	var stage: Node = view.stage
	assert_gt((stage.penguins as Array).size(), 0)
	var numbers: int = 0
	for penguin: Dictionary in stage.penguins:
		if int(penguin.get("number", 0)) > 0:
			numbers += 1
	assert_eq(numbers, (stage.penguins as Array).size(), "every penguin has the number of its agent")
	var focused: Array = (stage.penguins as Array).filter(func(p: Dictionary) -> bool: return p.get("focused", false))
	assert_eq(focused.size(), 1, "one penguin has the focus")


func test_a_room_with_one_agent_has_no_chips_and_no_ring() -> void:
	await _draw_scene("session", 12.5)
	assert_true(view.stage.solo)
	await _draw_scene("multi", 12.5)
	assert_false(view.stage.solo)
