extends GutTest
## The scripted input test of phase G-6. A scene of `demo/` has the keys and clicks of a person (`inputs`). The timeline player hands
## them to the camera directly. Here the same inputs go through the real input path instead: a key is an `InputEventKey`, a click is a
## mouse move and a left click on the place where the interface shows the tab, the box, the cell or the follow switch, and a line of
## the follow menu is a click on the switch and a key of the menu. The events are pushed into the viewport with `push_input`, so they
## reach `LiveView._unhandled_key_input` and `_unhandled_input`, the hit tests and `UiInput`, as a real key or click does.
##
## The expected camera log is the one that the same scene gives when the timeline hands on its inputs (`test_scene_camera.gd` compares
## that log with the mockup's). The two logs must be equal: the same moves, at the same times, with the same reasons.

const InputScript := preload("res://test/support/input_script.gd")

var _views: Array[Node] = []


func after_each() -> void:
	for view: Node in _views:
		if is_instance_valid(view):
			view.free()
	_views.clear()


func _make_view() -> Node:
	var scene: PackedScene = load("res://src/live.tscn")
	var view: Node = scene.instantiate()
	add_child(view)
	view.client.set_process(false)
	_views.append(view)
	return view


## The camera log of a scene when its timeline hands on its own inputs, the inputs, and the follow mode at the end.
func _expected(scene_name: String) -> Dictionary:
	var view: Node = _make_view()
	assert_true(view.load_scene(scene_name), scene_name)
	var script: Array = view.player.inputs.duplicate(true)
	view.simulate(int(view.player.duration / view.clock.STEP) + 1)
	var moves: Array = view.camera.log.duplicate(true)
	var mode: String = view.camera.mode
	_views.erase(view)
	view.free()
	return { "log": moves, "script": script, "mode": mode }


func _check_scene(scene_name: String) -> void:
	var expected: Dictionary = _expected(scene_name)
	var script: Array = expected["script"]
	assert_gt(script.size(), 0, "the scene has inputs")
	var view: Node = _make_view()
	assert_true(view.load_scene(scene_name))
	view.player.inputs.clear()
	var driver: InputScript = InputScript.new(view)
	var duration: float = float(view.player.duration)
	for entry: Dictionary in script:
		duration = maxf(duration, float(entry["t"]) + 1.0)
	driver.play(script, duration)
	assert_eq(driver.problems, [] as Array[String], "every input found its place on the screen")
	var moves: Array = view.camera.log
	var expected_log: Array = expected["log"]
	var lines: Array[String] = []
	for i in maxi(moves.size(), expected_log.size()):
		var a: String = "-" if i >= expected_log.size() else "%.2f %s %s" % [float(expected_log[i]["t"]), expected_log[i]["to"], expected_log[i]["why"]]
		var b: String = "-" if i >= moves.size() else "%.2f %s %s" % [float(moves[i]["t"]), moves[i]["to"], moves[i]["why"]]
		lines.append("%s | %s" % [a, b])
	assert_eq(moves.size(), expected_log.size(), "the same number of moves
" + "
".join(lines))
	for i in mini(moves.size(), expected_log.size()):
		assert_eq(moves[i]["to"], expected_log[i]["to"], "move %d goes to the same place" % i)
		assert_eq(moves[i]["why"], expected_log[i]["why"], "move %d has the same reason" % i)
		assert_almost_eq(float(moves[i]["t"]), float(expected_log[i]["t"]), 1e-9, "move %d is at the same time" % i)
	assert_eq(view.camera.mode, expected["mode"], "the same follow mode at the end")
	gut.p("%s: %d inputs pushed (%d events), %d moves, equal to the timeline's" % [scene_name, script.size(), driver.pushed.size(), moves.size()])


func test_the_arenas_scene_clicks_and_keys_through_the_input_path_give_the_timelines_camera_log() -> void:
	_check_scene("arenas")


func test_the_follow_scene_menu_through_the_input_path_gives_the_timelines_camera_log() -> void:
	_check_scene("follow")


func test_the_many_scene_keys_and_clicks_through_the_input_path_give_the_timelines_camera_log() -> void:
	_check_scene("many")


func test_the_ten_scene_keys_and_clicks_through_the_input_path_give_the_timelines_camera_log() -> void:
	_check_scene("ten")


func test_the_arenas_scene_has_the_expected_moves_from_its_inputs() -> void:
	# the four inputs of the scene (a click on tab B, Tab, a click on cell C, F) and what they did, in words
	var view: Node = _make_view()
	assert_true(view.load_scene("arenas"))
	view.player.inputs.clear()
	var driver: InputScript = InputScript.new(view)
	var script: Array = [
		{ "t": 24.0, "click": "tab", "arena": "B" },
		{ "t": 30.5, "key": "Tab" },
		{ "t": 34.0, "click": "cell", "arena": "C" },
		{ "t": 36.0, "key": "F" },
	]
	driver.play(script, 38.0)
	assert_eq(driver.problems, [] as Array[String])
	var moves: Array[String] = []
	for entry: Dictionary in view.camera.log:
		if entry["why"] == "click" or entry["why"] == "tab":
			moves.append("%.1f %s %s" % [float(entry["t"]), entry["to"], entry["why"]])
	assert_has(moves, "24.0 B click", "the click on tab B moved the camera to B at 24 s")
	assert_has(moves, "30.5 page 1 tab", "Tab opened the overview of page 1")
	assert_has(moves, "34.0 C click", "the click on cell C zoomed into C")
	assert_eq(view.camera.mode, "AUTO", "F brought AUTO back")
	assert_eq(driver.pushed.size(), 6, "four inputs: two keys, and two clicks that each leave a click and a note")


func test_a_hover_over_a_tab_shows_that_arenas_cards_through_the_input_path() -> void:
	var view: Node = _make_view()
	assert_true(view.load_scene("arenas"))
	view.player.inputs.clear()
	view.simulate(int(23.2 / view.clock.STEP))
	var shown: String = view.camera.arena_shown()
	var other: String = "B" if shown == "A" else "A"
	var driver: InputScript = InputScript.new(view)
	var tab: Rect2i = Rect2i(14 + (83 if other == "B" else 0), 233, 80, 9)
	driver.move_mouse(Vector2(tab.get_center()))
	var ui: Dictionary = view.interface.build(view.director, view.camera, view.clock.now)
	assert_eq(ui["hover"], other)
	assert_eq(ui["cards"]["arena"], other, "the row of cards is the hovered arena's")
	assert_true(ui["cards"]["plate"])
	assert_eq(view.camera.arena_shown(), shown, "the camera stays")
	driver.move_mouse(Vector2(300, 100))
	ui = view.interface.build(view.director, view.camera, view.clock.now)
	assert_eq(ui["cards"]["arena"], shown)


func test_a_click_on_a_penguin_and_on_a_card_moves_the_focus_through_the_input_path() -> void:
	var view: Node = _make_view()
	assert_true(view.load_scene("multi"))
	view.player.inputs.clear()
	view.simulate(int(9.5 / view.clock.STEP))
	var driver: InputScript = InputScript.new(view)
	var ui: Dictionary = view.interface.build(view.director, view.camera, view.clock.now)
	var card: Dictionary = ui["cards"]["items"][2]
	var number: int = int(card["card"]["number"])
	driver.click_at(Vector2((card["rect"] as Rect2i).get_center()))
	view.simulate(2)
	assert_eq(view.camera.focus_of("A"), number, "a click on a card sets the focus")
	ui = view.interface.build(view.director, view.camera, view.clock.now)
	var other: Dictionary = {}
	for penguin: Dictionary in ui["penguins"]:
		if int(penguin["number"]) != number and not penguin["helper"]:
			other = penguin
			break
	assert_false(other.is_empty())
	driver.click_at((other["rect"] as Rect2).get_center())
	view.simulate(2)
	assert_eq(view.camera.focus_of("A"), int(other["number"]), "a click on a penguin sets the focus")


func test_a_click_on_the_switch_opens_the_menu_and_the_keys_of_the_menu_work_through_the_input_path() -> void:
	var view: Node = _make_view()
	assert_true(view.load_scene("arenas"))
	view.player.inputs.clear()
	view.simulate(int(12.0 / view.clock.STEP))
	var driver: InputScript = InputScript.new(view)
	var ui: Dictionary = view.interface.build(view.director, view.camera, view.clock.now)
	driver.click_at(Vector2((ui["follow"]["rect"] as Rect2i).get_center()))
	assert_true(view.interface.menu_open, "a click on the switch opens the menu")
	driver.push_key(KEY_2)
	driver.push_key(KEY_BRACKETLEFT)
	view.simulate(3)
	assert_true(view.camera.follow["fail"], "key 2 ticked the failures")
	assert_almost_eq(view.camera.pace, 0.2, 1e-9, "[ lowered the pace by one level")
	driver.push_key(KEY_ESCAPE)
	assert_false(view.interface.menu_open, "Esc closed the menu")
	# with the menu closed, 1 to 3 are the speed of the demo, not ticks
	driver.push_key(KEY_2)
	assert_eq(view.clock.speed, 2.0)
	assert_true(view.camera.follow["fail"], "the failures stay ticked")
	driver.push_key(KEY_1)
	assert_eq(view.clock.speed, 1.0)
	driver.push_key(KEY_3)
	assert_eq(view.clock.speed, 4.0)
	# a click elsewhere closes the menu and does nothing else
	driver.click_at(Vector2((ui["follow"]["rect"] as Rect2i).get_center()))
	assert_true(view.interface.menu_open)
	driver.click_at(Vector2(30, 60))
	assert_false(view.interface.menu_open)


func test_space_pauses_only_in_demo_mode() -> void:
	var view: Node = _make_view()
	var driver: InputScript = InputScript.new(view)
	driver.push_key(KEY_SPACE)
	assert_false(view.clock.paused, "the live view follows real time: Space does nothing")
	assert_true(view.load_scene("session"))
	driver.push_key(KEY_SPACE)
	assert_true(view.clock.paused)
	driver.push_key(KEY_SPACE)
	assert_false(view.clock.paused)
