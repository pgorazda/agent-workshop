extends GutTest
## What the interface shows and where (phase G-6): the three kinds of bar, the tabs and their states, the list of pages, the cards
## of the arena on screen or under the mouse, the overview, the follow menu, the state of the link, and the hit tests.
## The scenes of `demo/` give the situations: `arenas` (three arenas, approvals, failures) and `many` (three pages).

const InterfaceModel := preload("res://src/view/interface_model.gd")
const BarLayout := preload("res://src/core/bar_layout.gd")
const Director := preload("res://src/core/director.gd")
const Camera := preload("res://src/core/camera.gd")
const Clock := preload("res://src/core/clock.gd")
const Trace := preload("res://test/support/trace.gd")

var view: Node


func before_each() -> void:
	var scene: PackedScene = load("res://src/live.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.client.set_process(false)


## Plays a scene to a time and builds the interface there.
func _at(scene_name: String, seconds: float) -> Dictionary:
	assert_true(view.load_scene(scene_name), scene_name)
	view.player.inputs.clear()
	view.simulate(int(seconds / Clock.STEP))
	return view.interface.build(view.director, view.camera, view.clock.now)


func _centre(rect: Rect2i) -> Vector2:
	return Vector2(rect.position) + Vector2(rect.size) / 2.0


# ---------------------------------------------------------------- the kinds of bar

func test_one_agent_in_one_arena_shows_the_log() -> void:
	var ui: Dictionary = _at("arenas", 1.0)
	assert_eq(ui["mode"], "log")
	assert_eq(ui["log"]["agent"]["number"], 1)
	assert_false(ui["follow"]["rect"].has_point(Vector2i(450, 237)), "one agent: no follow switch")


func test_the_log_of_the_session_scene_has_its_lines_with_their_states() -> void:
	var ui: Dictionary = _at("session", 10.0)
	assert_eq(ui["mode"], "log")
	var lines: Array = ui["log"]["lines"]
	assert_gt(lines.size(), 0)
	assert_lte(lines.size(), 3)
	for line: Dictionary in lines:
		assert_has(["run", "OK", "FAIL", "WAIT", ""], line["state"])


func test_several_agents_in_one_arena_show_the_top_line_and_the_cards() -> void:
	var ui: Dictionary = _at("arenas", 4.0)
	assert_eq(ui["mode"], "cards")
	assert_eq(ui["top"]["agents"], 4)
	assert_eq(ui["cards"]["items"].size(), 4)
	assert_true(ui["follow"]["pill"], "one arena: the follow switch is a pill with the word")
	assert_true((ui["tabs"] as Array).is_empty(), "no tabs with one arena")


func test_two_arenas_show_the_tabs_and_the_cards_of_the_arena_on_screen() -> void:
	var ui: Dictionary = _at("arenas", 12.0)
	assert_eq(ui["mode"], "arenas")
	assert_eq((ui["tabs"] as Array).size(), 2, "tabs A and B: a free place has no tab")
	assert_eq(ui["tabs"][0]["letter"], "A")
	assert_eq(ui["tabs"][0]["rect"], BarLayout.tab_rect(0))
	assert_eq(ui["tabs"][1]["rect"], BarLayout.tab_rect(1))
	assert_false(ui["follow"]["pill"])
	assert_eq(ui["follow"]["rect"], BarLayout.follow_rect(false, 37))
	assert_eq(ui["cards"]["arena"], view.camera.arena_shown())


# ---------------------------------------------------------------- tabs and states

func test_a_tab_says_waiting_failed_running_or_done() -> void:
	var ui: Dictionary = _at("arenas", 11.5)
	assert_eq(ui["labels"]["A"]["state"], "WAIT", "#2 in arena A asks for an approval")
	ui = _at("arenas", 14.5)
	assert_eq(ui["labels"]["B"]["state"], "FAIL", "#6 in arena B has failed")
	var chips: Array = ui["labels"]["B"]["chips"]
	var failed: Array = chips.filter(func(c: Dictionary) -> bool: return c["state"] == "FAIL")
	assert_eq(failed.size(), 1, "its chip is red")


func test_the_state_of_a_tab_is_the_most_urgent_state_of_its_agents() -> void:
	assert_eq(InterfaceModel.tab_state_of("WAIT"), "WAIT")
	assert_eq(InterfaceModel.tab_state_of("FAIL"), "FAIL")
	assert_eq(InterfaceModel.tab_state_of("run"), "run")
	assert_eq(InterfaceModel.tab_state_of("DONE"), "DONE")
	assert_eq(InterfaceModel.tab_state_of("OK"), "idle")
	assert_eq(InterfaceModel.tab_state_of(""), "idle")


func test_the_lit_tab_is_the_arena_on_screen() -> void:
	var ui: Dictionary = _at("arenas", 12.0)
	var shown: String = view.camera.arena_shown()
	var slot: int = ["A", "B", "C", "D"].find(shown)
	assert_not_null(ui["lit"])
	assert_eq(ui["lit"]["x"], BarLayout.tab_x(slot))


func test_a_new_tab_is_new_for_a_moment() -> void:
	var ui: Dictionary = _at("arenas", 7.2)
	var age: float = float(ui["tabs"][1]["opened_age"])
	assert_gt(age, 0.0)
	assert_lt(age, 1.0, "arena B opened at 7 s")
	ui = _at("arenas", 12.0)
	assert_gt(float(ui["tabs"][1]["opened_age"]), 4.0)


func test_the_overview_is_a_matrix_of_four_cells_with_free_places() -> void:
	var ui: Dictionary = _at("arenas", 12.0)
	view.camera.press("Tab", view.clock.now)
	view.simulate(60)
	ui = view.interface.build(view.director, view.camera, view.clock.now)
	assert_not_null(ui["overview"])
	var cells: Array = ui["overview"]["cells"]
	assert_eq(cells.size(), 4)
	assert_false(cells[0]["free"])
	assert_false(cells[1]["free"])
	assert_true(cells[2]["free"], "arena C has not opened")
	assert_true(cells[3]["free"])
	assert_eq(view.interface.hit(_centre(cells[0]["rect"]))["arena"], "A")
	assert_eq(view.interface.hit(_centre(cells[2]["rect"]))["kind"], "none", "a free place does nothing")


func test_the_overview_of_one_page_among_three_has_an_arrow_at_the_edge_for_the_pages_beyond() -> void:
	var ui: Dictionary = _at("many", 8.0)
	view.camera.press("Tab", view.clock.now)
	view.simulate(60)
	ui = view.interface.build(view.director, view.camera, view.clock.now)
	var arrows: Array = ui["overview"]["arrows"]
	assert_gt(arrows.size(), 0, "there are pages beyond the one on screen")
	for arrow: Dictionary in arrows:
		var other: int = int(arrow["page"])
		assert_ne(other, view.camera.page_shown())
	var hit: Dictionary = view.interface.hit(_centre(arrows[0]["rect"]))
	assert_eq(hit["kind"], "edge_arrow")


# ---------------------------------------------------------------- pages

func test_three_pages_give_three_boxes_and_the_one_on_screen_is_lit() -> void:
	var ui: Dictionary = _at("many", 10.0)
	var items: Array = ui["pages"]["items"]
	assert_gte(items.size(), 2)
	var lit: Array = items.filter(func(i: Dictionary) -> bool: return i["lit"])
	assert_eq(lit.size(), 1)
	assert_eq(lit[0]["page"], view.camera.page_shown())
	assert_eq(view.interface.hit(_centre(items[0]["rect"]))["kind"], "page")
	assert_eq(view.interface.hit(_centre(items[0]["rect"]))["page"], items[0]["page"])


func test_a_page_with_a_waiting_agent_is_outlined_in_the_state_of_its_most_urgent_arena() -> void:
	var ui: Dictionary = _at("many", 13.6)
	var states: Array = []
	for item: Dictionary in ui["pages"]["items"]:
		states.append(item["state"])
	assert_true(states.has("WAIT") or states.has("FAIL"), "an approval waits somewhere: %s" % str(states))


func test_agents_that_are_not_shown_give_a_plus_n_after_the_boxes() -> void:
	var director: Director = Director.new()
	var camera: Camera = Camera.new()
	director.set_arena_size(1)
	director.limit = 2
	director.attach_camera(camera)
	for n in 5:
		director.handle_event(Trace.ev("thinking", { }, "main", "pi", "s%d" % n))
	camera.advance(0.1)
	var model: InterfaceModel = InterfaceModel.new()
	var ui: Dictionary = model.build(director, camera, 0.1)
	assert_eq(director.unplaced_count(), 3)
	assert_not_null(ui["unplaced"])
	assert_eq(ui["unplaced"]["n"], 3)
	assert_eq(ui["unplaced"]["text"], "+3")


# ---------------------------------------------------------------- cards and hover

func test_a_hover_over_a_tab_shows_the_cards_of_that_arena_with_its_letter() -> void:
	var ui: Dictionary = _at("arenas", 12.0)
	var shown: String = view.camera.arena_shown()
	var other: String = "B" if shown == "A" else "A"
	var rect: Rect2i = BarLayout.tab_rect(["A", "B"].find(other))
	view.interface.hover_point = _centre(rect)
	ui = view.interface.build(view.director, view.camera, view.clock.now)
	assert_eq(ui["hover"], other)
	assert_eq(ui["cards"]["arena"], other)
	assert_true(ui["cards"]["plate"], "the letter comes first")
	assert_eq(view.camera.arena_shown(), shown, "the camera does not move")
	view.interface.hover_point = Vector2(-100, -100)
	ui = view.interface.build(view.director, view.camera, view.clock.now)
	assert_eq(ui["cards"]["arena"], shown)
	assert_false(ui["cards"]["plate"])


func test_the_cards_are_full_up_to_five_agents_and_compact_from_six() -> void:
	var director: Director = Director.new()
	var camera: Camera = Camera.new()
	director.attach_camera(camera)
	var model: InterfaceModel = InterfaceModel.new()
	for n in 5:
		director.handle_event(Trace.ev("thinking", { }, "main", "pi", "s%d" % n))
	camera.advance(0.1)
	var ui: Dictionary = model.build(director, camera, 0.1)
	assert_eq(ui["cards"]["items"].size(), 5)
	for item: Dictionary in ui["cards"]["items"]:
		assert_false(item["card"]["compact"])
	director.handle_event(Trace.ev("thinking", { }, "main", "hermes", "s6"))
	ui = model.build(director, camera, 0.1)
	assert_eq(ui["cards"]["items"].size(), 6)
	for item: Dictionary in ui["cards"]["items"]:
		assert_true(item["card"]["compact"])
		assert_lte((item["rect"] as Rect2i).end.x, 476)


func test_the_card_of_the_focused_agent_is_marked() -> void:
	var ui: Dictionary = _at("multi", 9.5)
	var focused: Array = ui["cards"]["items"].filter(func(i: Dictionary) -> bool: return i["focused"])
	assert_eq(focused.size(), 1)
	assert_eq(focused[0]["card"]["number"], view.camera.focus_of("A"))


func test_a_click_on_a_card_or_a_penguin_gives_the_focus() -> void:
	var ui: Dictionary = _at("multi", 9.5)
	var card: Dictionary = ui["cards"]["items"][0]
	var hit: Dictionary = view.interface.hit(_centre(card["rect"]))
	assert_eq(hit["kind"], "card")
	assert_eq(hit["number"], card["card"]["number"])
	var penguin: Dictionary = ui["penguins"][0]
	var at: Vector2 = (penguin["rect"] as Rect2).get_center()
	var penguin_hit: Dictionary = view.interface.hit(at)
	assert_eq(penguin_hit["kind"], "penguin")
	assert_true(penguin_hit.has("number"))


func test_the_penguin_in_front_gets_the_click_where_two_overlap() -> void:
	var director: Director = Director.new()
	var camera: Camera = Camera.new()
	director.attach_camera(camera)
	director.handle_event(Trace.ev("thinking", { }, "main", "pi", "s1"))
	director.handle_event(Trace.ev("thinking", { }, "main", "pi", "s2"))
	var model: InterfaceModel = InterfaceModel.new()
	var clock: Clock = Clock.new()
	var now: float = Trace.run(director, clock, 0.6)
	camera.advance(now)
	var ui: Dictionary = model.build(director, camera, now)
	var list: Array = ui["penguins"]
	assert_eq(list.size(), 2)
	# put the two penguins on top of each other, the second one in front
	list[0]["rect"] = Rect2(100, 100, 30, 50)
	list[1]["rect"] = Rect2(100, 100, 30, 50)
	list[0]["y"] = 120.0
	list[1]["y"] = 130.0
	model.ui["penguins"] = list
	assert_eq(model.hit(Vector2(110, 110))["number"], list[1]["number"])


# ---------------------------------------------------------------- the follow switch and its menu

func test_the_switch_opens_the_menu_and_a_click_elsewhere_closes_it() -> void:
	var ui: Dictionary = _at("arenas", 12.0)
	var follow_hit: Dictionary = view.interface.hit(_centre(ui["follow"]["rect"]))
	assert_eq(follow_hit["kind"], "follow")
	view.interface.menu_open = true
	ui = view.interface.build(view.director, view.camera, view.clock.now)
	assert_not_null(ui["menu"])
	assert_eq(ui["menu"]["lines"].size(), 8)
	var line: Dictionary = view.interface.hit(_centre(BarLayout.menu_line_rect(1)))
	assert_eq(line["kind"], "menu_line")
	assert_eq(line["line"], "fail")
	assert_eq(view.interface.hit(_centre(BarLayout.menu_line_rect(7)))["line"], "manual")
	var down: Dictionary = view.interface.hit(_centre(BarLayout.pace_arrow_rect(-1)))
	assert_eq(down["line"], "pace")
	assert_eq(down["direction"], -1)
	assert_eq(view.interface.hit(Vector2(10, 100))["kind"], "close_menu")
	assert_eq(view.interface.hit(_centre(ui["follow"]["rect"]))["kind"], "follow", "the switch closes it again")


func test_the_menu_says_the_pace_in_moves_in_ten_seconds() -> void:
	_at("arenas", 12.0)
	view.interface.menu_open = true
	var ui: Dictionary = view.interface.build(view.director, view.camera, view.clock.now)
	assert_eq(ui["menu"]["pace_text"], "at most 3 moves / 10 s")
	view.camera.set_pace(INF, view.clock.now)
	view.simulate(3)
	ui = view.interface.build(view.director, view.camera, view.clock.now)
	assert_eq(ui["menu"]["pace_text"], "moves: no limit")


func test_the_menu_ticks_show_what_the_camera_has() -> void:
	_at("arenas", 12.0)
	view.interface.menu_open = true
	var ui: Dictionary = view.interface.build(view.director, view.camera, view.clock.now)
	var on: Array = []
	for line: Dictionary in ui["menu"]["lines"]:
		if line["on"]:
			on.append(line["kind"])
	assert_eq(on, ["approval", "open", "done", "activity"], "the defaults: failures and new agents are not ticked")


# ---------------------------------------------------------------- the link

func test_the_state_of_the_link() -> void:
	assert_eq(InterfaceModel.connection_of(false, true, true, 0.0)["kind"], "connected")
	assert_eq(InterfaceModel.connection_of(false, true, true, 0.0)["word"], "online")
	assert_eq(InterfaceModel.connection_of(false, false, false, 1.0)["kind"], "connecting", "never connected yet")
	assert_eq(InterfaceModel.connection_of(false, false, true, 1.0)["kind"], "reconnecting", "it was open and dropped")
	assert_eq(InterfaceModel.connection_of(false, false, true, 9.9)["kind"], "reconnecting")
	assert_eq(InterfaceModel.connection_of(false, false, true, 10.0)["kind"], "lost")
	assert_eq(InterfaceModel.connection_of(false, false, false, 30.0)["kind"], "lost", "a bridge that never answered is lost too")
	assert_eq(InterfaceModel.connection_of(true, false, false, 99.0)["kind"], "demo", "a scripted scene has no link")


func test_the_bar_shows_the_state_of_the_link_of_the_live_view() -> void:
	view.load_live()
	view.interface.connection = view._connection()
	assert_eq(view.interface.connection["kind"], "connecting")
	view._down_since_msec -= 20000
	assert_eq(view._connection()["kind"], "lost")
