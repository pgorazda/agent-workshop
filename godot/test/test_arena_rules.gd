extends GutTest
## The 34 cases of the arena-rules tests of the JavaScript mockup, in the same order.
## Above each test, `# JS: <title>` holds the exact title of the JavaScript test.
## `tools/parity.test.mjs` reads this file and the fixed list of titles in `test/fixtures/`, and fails when a title has no counterpart here.

const ArenaRules := preload("res://src/core/arena_rules.gd")
const DEFAULTS: Dictionary = ArenaRules.DEFAULTS
const NOTHING: Dictionary = { "approval": false, "fail": false, "open": false, "join": false, "done": false, "activity": false }

var AB: Array = _open("AB")
var ABC: Array = _open("ABC")


# ---------------------------------------------------------------- helpers

## `moves(sim)` of the JavaScript: "<time> <to> <why>" for each move of the camera.
func _moves(sim: ArenaRules.CameraResult) -> Array[String]:
	var out: Array[String] = []
	for m in sim.log:
		out.append("%.2f %s %s" % [m["t"], m["to"], m["why"]])
	return out


func _run(spec: Dictionary) -> ArenaRules.CameraResult:
	var full: Dictionary = { "duration": 30.0 }
	full.merge(spec, true)
	return ArenaRules.simulate_camera(full)


## `open('AB')`: the arenas of the string, all open at 0. An array of letters works too.
static func _open(letters: Variant) -> Array:
	var list: Array = []
	if typeof(letters) == TYPE_STRING:
		for c in (letters as String):
			list.append(c)
	else:
		list = letters
	var out: Array = []
	for letter: Variant in list:
		out.append({ "letter": letter, "t": 0.0 })
	return out


func _near(a: float, b: float, d: float = 1e-6) -> bool:
	return absf(a - b) < d


func _pose(sim: ArenaRules.CameraResult, t: float) -> Dictionary:
	return sim.at(t)["pose"]


func _names(count: int) -> Array:
	var out: Array = []
	for i in count:
		out.append(ArenaRules.name_of(i))
	return out


## The JavaScript test prints `${p.page}:${+p.x.toFixed(3)},${p.y}`. A whole number has no decimal point.
func _at(letter: String) -> String:
	var p: Dictionary = ArenaRules.place_of(letter)
	var x: float = snappedf(p["x"], 0.001)
	var x_text: String = str(int(x)) if x == floorf(x) else str(x)
	return "%d:%s,%d" % [p["page"], x_text, int(p["y"])]


# ---------------------------------------------------------------- the arena model

# JS: arenas fill up in letter order, four agents each
func test_arenas_fill_up_in_letter_order_four_agents_each() -> void:
	var a := ArenaRules.create_arenas()
	var got: Array = []
	for n: int in [1, 2, 3, 4]:
		got.append(a.place(n, 0.0))
	assert_eq(got, ["A", "A", "A", "A"])
	assert_eq(a.place(5, 1.0), "B")
	assert_eq(a.letters(), ["A", "B"])
	assert_eq(a.place(5, 2.0), "B", "an agent never changes arena")
	a.leave(2, 3.0)
	assert_eq(a.place(6, 4.0), "A", "the first arena with room")


# JS: an agent that comes back goes to its old arena if there is room
func test_an_agent_that_comes_back_goes_to_its_old_arena_if_there_is_room() -> void:
	var a := ArenaRules.create_arenas({ "arena_size": 2 })
	a.place(1, 0.0)
	a.place(2, 0.0)
	a.place(3, 0.0) # A: 1 2, B: 3
	a.leave(3, 1.0)
	a.leave(1, 1.0) # room in A and in B
	assert_eq(a.place(3, 2.0), "B")


# JS: names go on after Z like spreadsheet columns, and back
func test_names_go_on_after_z_like_spreadsheet_columns_and_back() -> void:
	var got: Array = []
	for i: int in [0, 25, 26, 27, 51, 52, 701, 702]:
		got.append(ArenaRules.name_of(i))
	assert_eq(got, ["A", "Z", "AA", "AB", "AZ", "BA", "ZZ", "AAA"])
	var wrong: Array = []
	for i in 2000:
		if ArenaRules.index_of(ArenaRules.name_of(i)) != i:
			wrong.append(i)
	assert_eq(wrong, [], "index_of(name_of(i)) is i for 0 to 1999")


# JS: arenas have no limit of their own; names go on after Z; a limit can be set
func test_arenas_have_no_limit_of_their_own_names_go_on_after_z_a_limit_can_be_set() -> void:
	var a := ArenaRules.create_arenas({ "arena_size": 1 })
	var got: Array = []
	for i in 40:
		got.append(a.place(i + 1, 0.0))
	assert_eq(got.slice(24, 28), ["Y", "Z", "AA", "AB"])
	assert_eq(got[39], "AN", "the 40th arena, the last of the tenth page")
	assert_eq(a.letters().slice(24, 28), ["Y", "Z", "AA", "AB"], "in the order of their places, not alphabetical")
	var five := ArenaRules.create_arenas({ "arena_size": 1, "max_arenas": 5 })
	var placed: Array = []
	for n: int in [1, 2, 3, 4, 5, 6]:
		placed.append(five.place(n, 0.0))
	assert_eq(placed, ["A", "B", "C", "D", "E", null], "with a limit, an agent beyond it is not shown")


# JS: an empty arena closes after 30 s, never the last one, and its letter is used again
func test_an_empty_arena_closes_after_30_s_never_the_last_one_and_its_letter_is_used_again() -> void:
	var a := ArenaRules.create_arenas({ "arena_size": 1 })
	a.place(1, 0.0)
	a.place(2, 0.0)
	a.place(3, 0.0) # A B C
	a.leave(2, 10.0)
	assert_eq(a.tick(39.9), [])
	assert_eq(a.tick(40.0), ["B"])
	assert_eq(a.place(4, 41.0), "B", "the lowest free letter")
	a.leave(1, 50.0)
	a.leave(3, 50.0)
	a.leave(4, 50.0)
	assert_eq(a.tick(80.0), ["A", "B"])
	assert_eq(a.letters(), ["C"])


# JS: an agent leaves after 10 quiet minutes, unless a call or an approval is open
func test_an_agent_leaves_after_10_quiet_minutes_unless_a_call_or_an_approval_is_open() -> void:
	assert_eq(ArenaRules.leaves({ "last_event": 0.0 }, 599.0), false)
	assert_eq(ArenaRules.leaves({ "last_event": 0.0 }, 600.0), true)
	assert_eq(ArenaRules.leaves({ "last_event": 0.0, "open_calls": 1 }, 900.0), false)
	assert_eq(ArenaRules.leaves({ "last_event": 0.0, "waiting": true }, 900.0), false)


# JS: a tab shows the most urgent state of its agents
func test_a_tab_shows_the_most_urgent_state_of_its_agents() -> void:
	assert_eq(ArenaRules.tab_state(["idle", "run", "FAIL", "DONE"]), "FAIL")
	assert_eq(ArenaRules.tab_state(["run", "WAIT"]), "WAIT")
	assert_eq(ArenaRules.tab_state(["idle", "DONE"]), "DONE")
	assert_eq(ArenaRules.tab_state(["OK", ""]), "idle")
	assert_eq(ArenaRules.tab_state([]), "empty")


# ---------------------------------------------------------------- the world: pages of four

# JS: arenas sit in pages of four, each a 2x2 matrix, and the pages side by side
func test_arenas_sit_in_pages_of_four_each_a_2x2_matrix_and_the_pages_side_by_side() -> void:
	assert_eq(["A", "B", "C", "D"].map(_at), ["0:0,0", "0:1,0", "0:0,1", "0:1,1"])
	assert_eq(["E", "F", "G", "H"].map(_at), ["1:2.1,0", "1:3.1,0", "1:2.1,1", "1:3.1,1"], "after a gutter of 0.1 rooms")
	assert_eq(_at("Z"), "6:13.6,0")
	assert_eq(_at("AA"), "6:12.6,1")
	assert_eq(_at("AN"), "9:19.9,1", "the tenth page")
	assert_eq(ArenaRules.pages_of(["A", "B", "E", "F", "I"]), [0, 1, 2])
	assert_eq(ArenaRules.pages_of(["A", "I"]), [0, 2], "a page with no open arena is skipped")


# JS: moves: a slide on a page, a fly to another page, a zoom, a scroll; a short cut with reduced motion
func test_moves_a_slide_on_a_page_a_fly_to_another_page_a_zoom_a_scroll_a_short_cut_with_reduced_motion() -> void:
	assert_eq(ArenaRules.move_duration("slide"), 0.5)
	assert_eq(ArenaRules.move_duration("fly", 1), 0.7)
	assert_eq(ArenaRules.move_duration("fly", 2), 0.85)
	assert_eq(ArenaRules.move_duration("fly", 6), 1.0)
	assert_eq(ArenaRules.move_duration("zoom"), 0.3)
	assert_eq(ArenaRules.move_duration("scroll", 1), 0.5)
	assert_eq(ArenaRules.move_duration("scroll", 4), 0.8)
	assert_eq(ArenaRules.move_duration("fly", 2, { "reduced_motion": true }), DEFAULTS["fade"])


# JS: a fly to another page widens the view to a page midway; a slide on the same page does not
func test_a_fly_to_another_page_widens_the_view_to_a_page_midway_a_slide_on_the_same_page_does_not() -> void:
	var sim := _run({ "opened": _open("ABCDEF"), "inputs": [{ "t": 1.0, "click": "tab", "arena": "D" }, { "t": 3.0, "click": "tab", "arena": "F" }] })
	var t: float = 1.0
	while t < 1.6:
		assert_eq(_pose(sim, t)["s"], 1.0, "A to D, diagonally on the first page, at %s" % t)
		t += 0.05
	assert_gt(_pose(sim, 3.35)["s"], 1.95, "D to F: the size of a page midway")
	var end: Dictionary = _pose(sim, 4.0)
	assert_true(_near(end["cx"], 3.6) and end["cy"] == 0.5 and end["s"] == 1.0, "F is on the second page, top right")


# JS: the view stays on the world: inside it up to the size of a page, centred on it when wider
func test_the_view_stays_on_the_world_inside_it_up_to_the_size_of_a_page_centred_on_it_when_wider() -> void:
	var sim := _run({
		"opened": _open(_names(40)),
		"inputs": [
			{ "t": 1.0, "click": "tab", "arena": "I" }, { "t": 3.0, "click": "tab", "arena": "C" },
			{ "t": 5.0, "click": "tab", "arena": "AN" }, { "t": 7.0, "key": "Tab" }, { "t": 9.0, "click": "page", "page": 0 },
		],
	})
	var broken: Array[String] = []
	for f in sim.frames:
		var pose: Dictionary = f["pose"]
		var cx: float = pose["cx"]
		var cy: float = pose["cy"]
		var s: float = pose["s"]
		var width: float = f["width"]
		if not (cx - s / 2.0 > -1e-9 and cx + s / 2.0 < width + 1e-9):
			broken.append("not inside left and right at %s" % f["t"])
		if s <= 2.0:
			if not (cy - s / 2.0 > -1e-9 and cy + s / 2.0 < 2.0 + 1e-9):
				broken.append("not inside top and bottom at %s" % f["t"])
		elif not _near(cy, 1.0):
			broken.append("not centred on the world's height at %s" % f["t"])
	assert_eq(broken, [], "every frame stays on the world")
	assert_gt(sim.frames.size(), 900, "the frames were made")


# JS: a long move widens the view by about a page for each page it crosses, up to 8 rooms across
func test_a_long_move_widens_the_view_by_about_a_page_for_each_page_it_crosses_up_to_8_rooms_across() -> void:
	var sim := _run({
		"opened": _open(_names(40)),
		"inputs": [
			{ "t": 1.0, "click": "tab", "arena": "E" }, { "t": 3.0, "click": "tab", "arena": "M" }, { "t": 5.0, "click": "tab", "arena": "AN" },
			{ "t": 7.0, "key": "Tab" }, { "t": 9.0, "key": "Left" }, { "t": 11.0, "click": "page", "page": 6 },
		],
	})
	var peak := func(t0: float, t1: float) -> float:
		var best: float = -INF
		for f in sim.frames:
			var ft: float = f["t"]
			if ft >= t0 and ft <= t1:
				best = maxf(best, (f["pose"] as Dictionary)["s"])
		return best
	assert_true(_near(peak.call(1.0, 2.5), 2.0, 0.01), "A to E, the next page: the size of a page")
	assert_true(_near(peak.call(3.0, 4.5), 4.2, 0.02), "E to M, two pages on: two pages across")
	assert_true(_near(peak.call(5.0, 6.5), 8.0, 0.02), "M to AN, seven pages on: at most 8 rooms across")
	assert_eq(peak.call(9.0, 10.5), 2.0, "scrolling the overview by one page does not widen it")
	assert_true(_near(peak.call(11.0, 12.5), 4.2, 0.02), "scrolling by two pages does")
	assert_eq(sim.at(13.0)["page"], 6)


# ---------------------------------------------------------------- the camera

# JS: a new arena pulls the camera, after the hold
func test_a_new_arena_pulls_the_camera_after_the_hold() -> void:
	var sim := _run({ "opened": [{ "letter": "A", "t": 0.0 }, { "letter": "B", "t": 1.0 }], "events": [{ "t": 1.0, "arena": "B", "n": 5, "kind": "open" }] })
	assert_eq(_moves(sim), ["1.50 B pull:open"])
	assert_eq(sim.at(2.0)["arena"], "B")
	assert_eq((sim.at(2.1)["ribbon"] as Dictionary)["arena"], "B", "the ribbon of a new arena")
	assert_eq((sim.at(2.1)["focus"] as Dictionary)["B"], 5, "the focus goes to the agent that pulled the camera")


# JS: an approval pulls before a new arena, the oldest approval first, and each pull only once
func test_an_approval_pulls_before_a_new_arena_the_oldest_approval_first_and_each_pull_only_once() -> void:
	var sim := _run({
		"opened": ABC,
		"events": [
			{ "t": 0.5, "arena": "B", "n": 2, "kind": "open" },
			{ "t": 1.0, "arena": "C", "n": 3, "kind": "approval", "until": 20.0 },
			{ "t": 1.2, "arena": "B", "n": 4, "kind": "approval", "until": 20.0 },
		],
	})
	# all three wait for the hold after the start (1.5 s). C's approval is the oldest, so the camera goes
	# there first (a slide down, 0.5 s) and stays 4 s while it is read; then B, where the approval and the new
	# arena are served at once, so nothing pulls again
	assert_eq(_moves(sim), ["1.50 C pull:approval", "6.00 B pull:approval"])
	assert_eq((sim.at(7.0)["ribbon"] as Dictionary)["arena"], "B")


# JS: by default a failure elsewhere does not move the camera
func test_by_default_a_failure_elsewhere_does_not_move_the_camera() -> void:
	var busy_a: Array = []
	for i in 30:
		busy_a.append({ "t": float(i), "arena": "A", "n": 1, "kind": "activity" })
	var events: Array = busy_a.duplicate()
	events.append({ "t": 2.0, "arena": "B", "n": 5, "kind": "fail" })
	events.append({ "t": 2.5, "arena": "B", "n": 5, "kind": "activity" })
	var sim := _run({ "opened": AB, "events": events })
	assert_eq(_moves(sim), [])


# JS: ordinary activity moves the camera only after 3 s of quiet and 5 s on screen
func test_ordinary_activity_moves_the_camera_only_after_3_s_of_quiet_and_5_s_on_screen() -> void:
	var events: Array = [{ "t": 3.0, "arena": "A", "n": 1, "kind": "activity" }]
	for i in 20:
		events.append({ "t": 1.0 + float(i), "arena": "B", "n": 5, "kind": "activity" })
	var sim := _run({ "opened": AB, "events": events })
	assert_eq(_moves(sim), ["6.00 B activity"])


# JS: a pull for a finished turn expires after 10 s; an approval does not
func test_a_pull_for_a_finished_turn_expires_after_10_s_an_approval_does_not() -> void:
	var sim := _run({
		"opened": AB,
		"opts": { "mode": "MANUAL" },
		"events": [{ "t": 1.0, "arena": "B", "n": 5, "kind": "done" }, { "t": 1.0, "arena": "B", "n": 6, "kind": "approval", "until": 40.0 }],
		"inputs": [{ "t": 12.0, "key": "F" }],
	})
	assert_eq(sim.at(10.9)["pending"], ["done:B", "approval:B"])
	assert_eq(sim.at(11.0)["pending"], ["approval:B"])
	assert_eq(_moves(sim), ["12.00 B pull:approval"])


# JS: in MANUAL nothing moves the camera; choosing an arena switches to MANUAL, F back to AUTO
func test_in_manual_nothing_moves_the_camera_choosing_an_arena_switches_to_manual_f_back_to_auto() -> void:
	var sim := _run({
		"opened": ABC,
		"events": [{ "t": 5.0, "arena": "C", "n": 9, "kind": "approval", "until": 25.0 }],
		"inputs": [{ "t": 2.0, "click": "tab", "arena": "B" }, { "t": 10.0, "key": "F" }],
	})
	assert_eq(sim.at(2.0)["mode"], "MANUAL")
	assert_eq(sim.at(9.0)["arena"], "B")
	assert_eq(_moves(sim), ["2.00 B click", "10.00 C pull:approval"])


# JS: the overview: Tab zooms out to the page, a click on an arena zooms into it in MANUAL, nothing moves meanwhile
func test_the_overview_tab_zooms_out_to_the_page_a_click_on_an_arena_zooms_into_it_in_manual_nothing_moves_meanwhile() -> void:
	var sim := _run({
		"opened": ABC,
		"events": [{ "t": 3.0, "arena": "B", "n": 4, "kind": "approval", "until": 20.0 }],
		"inputs": [{ "t": 2.0, "key": "Tab" }, { "t": 6.0, "click": "cell", "arena": "C" }],
	})
	assert_eq(sim.at(4.0)["view"], "page")
	var pose: Dictionary = _pose(sim, 4.0)
	assert_eq([pose["cx"], pose["cy"], pose["s"]], [1.0, 1.0, 2.0], "the first page, whole")
	assert_eq(sim.at(6.1)["moving"], true, "zooming in")
	assert_eq(sim.at(6.4)["arena"], "C")
	assert_eq(sim.at(6.4)["mode"], "MANUAL")
	assert_eq(_moves(sim), ["2.00 page 1 tab", "6.00 C click"])


# JS: Esc leaves the overview for the arena that was on screen; Tab needs two arenas
func test_esc_leaves_the_overview_for_the_arena_that_was_on_screen_tab_needs_two_arenas() -> void:
	var one := _run({ "opened": [{ "letter": "A", "t": 0.0 }], "inputs": [{ "t": 1.0, "key": "Tab" }] })
	assert_eq(one.at(2.0)["view"], "arena")
	var sim := _run({ "opened": AB, "inputs": [{ "t": 1.0, "key": "Tab" }, { "t": 3.0, "key": "Esc" }] })
	assert_eq(sim.at(2.0)["view"], "page")
	assert_eq(sim.at(4.0)["arena"], "A")


# JS: the overview scrolls page by page with ← and →, or to a page chosen in the list; Esc flies back
func test_the_overview_scrolls_page_by_page_with_left_and_right_or_to_a_page_chosen_in_the_list_esc_flies_back() -> void:
	var sim := _run({
		"opened": _open("ABCDEFGHI"),
		"inputs": [
			{ "t": 1.0, "key": "Tab" }, { "t": 2.0, "key": "Right" }, { "t": 3.0, "key": "Right" }, { "t": 4.0, "key": "Right" }, { "t": 5.0, "key": "Left" },
			{ "t": 6.0, "click": "page", "page": 0 }, { "t": 7.0, "click": "page", "page": 2 }, { "t": 8.0, "key": "Esc" },
		],
	})
	assert_eq(
		_moves(sim),
		["1.00 page 1 tab", "2.00 page 2 key", "3.00 page 3 key", "5.00 page 2 key", "6.00 page 1 click", "7.00 page 3 click", "8.00 A esc"],
		"there is no fourth page",
	)
	assert_true(_near(_pose(sim, 3.6)["cx"], 5.2), "the third page")
	assert_eq(_pose(sim, 8.1)["s"] > 1.5, true, "flying back from the third page")
	assert_eq(sim.at(9.5)["arena"], "A")
	assert_eq(sim.at(9.5)["mode"], "AUTO", "scrolling the overview is not choosing an arena")


# JS: a click on a page in the list opens the overview there
func test_a_click_on_a_page_in_the_list_opens_the_overview_there() -> void:
	var sim := _run({ "opened": _open("ABCDEF"), "inputs": [{ "t": 1.0, "click": "page", "page": 1 }] })
	assert_eq(_moves(sim), ["1.00 page 2 click"])
	assert_eq(sim.at(3.0)["view"], "page")
	assert_true(_near(_pose(sim, 3.0)["cx"], 3.1))


# JS: N goes to the arena that needs you; ← and → step through the arenas, across pages too
func test_n_goes_to_the_arena_that_needs_you_left_and_right_step_through_the_arenas_across_pages_too() -> void:
	var sim := _run({
		"opened": _open("ABCDE"),
		"opts": { "mode": "MANUAL" },
		"events": [{ "t": 1.0, "arena": "B", "n": 4, "kind": "fail" }, { "t": 1.2, "arena": "C", "n": 9, "kind": "approval", "until": 9.0 }],
		"inputs": [
			{ "t": 2.0, "key": "N" }, { "t": 4.0, "key": "N" }, { "t": 6.0, "key": "Left" }, { "t": 8.0, "key": "Left" },
			{ "t": 10.0, "click": "tab", "arena": "D" }, { "t": 12.0, "key": "Right" },
		],
	})
	assert_eq(_moves(sim), ["2.00 C N", "4.00 B N", "6.00 A key", "10.00 D click", "12.00 E key"], "there is nothing left of A")
	assert_gt(_pose(sim, 12.35)["s"], 1.9, "D to E is a fly")


# JS: a move that is turned midway starts from where the camera is
func test_a_move_that_is_turned_midway_starts_from_where_the_camera_is() -> void:
	var sim := _run({ "opened": ABC, "inputs": [{ "t": 1.0, "click": "tab", "arena": "C" }, { "t": 1.3, "click": "tab", "arena": "B" }] })
	var mid: Dictionary = _pose(sim, 1.3)
	assert_true(mid["cy"] > 0.5 and mid["cy"] < 1.5)
	var next: Dictionary = _pose(sim, 1.3 + 1.0 / 30.0)
	assert_true(absf(next["cx"] - mid["cx"]) < 0.1 and absf(next["cy"] - mid["cy"]) < 0.1, "no jump")
	assert_eq([_pose(sim, 3.0)["cx"], _pose(sim, 3.0)["cy"]], [1.5, 0.5])


# JS: an arena that closes leaves a free place; a camera on it cuts to its left neighbour
func test_an_arena_that_closes_leaves_a_free_place_a_camera_on_it_cuts_to_its_left_neighbour() -> void:
	var sim := _run({
		"opened": ABC,
		"closed": [{ "letter": "B", "t": 6.0 }, { "letter": "A", "t": 12.0 }],
		"inputs": [{ "t": 2.0, "click": "tab", "arena": "B" }, { "t": 8.0, "click": "tab", "arena": "A" }],
	})
	assert_eq(sim.at(5.0)["letters"], ["A", "B", "C"])
	assert_eq(sim.at(6.0)["letters"], ["A", "C"])
	assert_eq(_moves(sim), ["2.00 B click", "6.00 A closed", "12.00 C closed"])
	assert_eq([_pose(sim, 7.0)["cx"], _pose(sim, 7.0)["cy"]], [0.5, 0.5])
	assert_eq([_pose(sim, 13.0)["cx"], _pose(sim, 13.0)["cy"]], [0.5, 1.5], "C keeps its place, below where A was")


# JS: an arena may open again under a letter that was closed
func test_an_arena_may_open_again_under_a_letter_that_was_closed() -> void:
	var opened: Array = AB.duplicate()
	opened.append({ "letter": "B", "t": 10.0 })
	var sim := _run({ "opened": opened, "closed": [{ "letter": "B", "t": 5.0 }] })
	assert_eq(sim.at(4.0)["letters"], ["A", "B"])
	assert_eq(sim.at(7.0)["letters"], ["A"])
	assert_eq(sim.at(11.0)["letters"], ["A", "B"])


# JS: the overview of a page whose arenas have all closed cuts to the nearest page
func test_the_overview_of_a_page_whose_arenas_have_all_closed_cuts_to_the_nearest_page() -> void:
	var sim := _run({ "opened": _open("ABCDE"), "closed": [{ "letter": "E", "t": 5.0 }], "inputs": [{ "t": 1.0, "click": "page", "page": 1 }] })
	assert_eq(_moves(sim), ["1.00 page 2 click", "5.00 page 1 closed"])
	assert_eq(_pose(sim, 6.0)["cx"], 1.0)
	assert_true(_near(sim.at(6.0)["width"], 2.0), "the world is one page wide again")


# ---------------------------------------------------------------- the follow switch

# JS: the follow switch: failures and new agents pull only when ticked, and are not ticked by default
func test_the_follow_switch_failures_and_new_agents_pull_only_when_ticked_and_are_not_ticked_by_default() -> void:
	var events: Array = []
	for i in 30:
		events.append({ "t": float(i), "arena": "A", "n": 1, "kind": "activity" })
	events.append({ "t": 2.0, "arena": "B", "n": 5, "kind": "fail" })
	events.append({ "t": 6.0, "arena": "C", "n": 9, "kind": "join" })
	assert_eq(_moves(_run({ "opened": ABC, "events": events })), [], "by default, neither moves the camera")
	var ticked := _run({ "opened": ABC, "events": events, "opts": { "follow": { "fail": true, "join": true, "activity": false } } })
	assert_eq(_moves(ticked), ["2.00 B pull:fail", "6.00 C pull:join"])
	assert_eq(DEFAULTS["follow"], { "approval": true, "fail": false, "open": true, "join": false, "done": true, "activity": true })


# JS: approvals only: a new arena, a failure, a finished turn or a new agent do not move the camera; an approval does
func test_approvals_only_a_new_arena_a_failure_a_finished_turn_or_a_new_agent_do_not_move_the_camera_an_approval_does() -> void:
	var follow: Dictionary = NOTHING.duplicate()
	follow["approval"] = true
	var sim := _run({
		"opened": _open("ABCD"),
		"opts": { "follow": follow },
		"events": [
			{ "t": 1.0, "arena": "D", "n": 13, "kind": "open" }, { "t": 2.0, "arena": "B", "n": 5, "kind": "fail" },
			{ "t": 3.0, "arena": "B", "n": 6, "kind": "done" }, { "t": 4.0, "arena": "C", "n": 9, "kind": "join" },
			{ "t": 5.0, "arena": "C", "n": 10, "kind": "approval", "until": 20.0 },
		],
	})
	assert_eq(_moves(sim), ["5.00 C pull:approval"])


# JS: the follow menu ticks and unticks kinds; manual only and F switch between MANUAL and AUTO, which keeps its ticks
func test_the_follow_menu_ticks_and_unticks_kinds_manual_only_and_f_switch_between_manual_and_auto_which_keeps_its_ticks() -> void:
	var sim := _run({
		"opened": ABC,
		"events": [{ "t": 2.0, "arena": "B", "n": 5, "kind": "approval", "until": 20.0 }, { "t": 6.0, "arena": "C", "n": 9, "kind": "approval", "until": 20.0 }],
		"inputs": [{ "t": 1.0, "toggle": "approval" }, { "t": 3.0, "toggle": "approval" }, { "t": 5.0, "manual": true }, { "t": 8.0, "key": "F" }],
	})
	assert_eq((sim.at(2.5)["follow"] as Dictionary)["approval"], false)
	assert_eq((sim.at(4.0)["follow"] as Dictionary)["approval"], true)
	assert_eq(sim.at(6.5)["mode"], "MANUAL")
	assert_eq(sim.at(8.0)["mode"], "AUTO")
	assert_eq(_moves(sim), ["3.00 B pull:approval", "8.00 C pull:approval"], "not while unticked, not in MANUAL")


# JS: nothing ticked: the camera only moves when the person moves it
func test_nothing_ticked_the_camera_only_moves_when_the_person_moves_it() -> void:
	var sim := _run({
		"opened": ABC,
		"opts": { "follow": NOTHING },
		"events": [{ "t": 1.0, "arena": "B", "n": 5, "kind": "approval", "until": 20.0 }, { "t": 2.0, "arena": "C", "n": 9, "kind": "open" }],
		"inputs": [{ "t": 4.0, "click": "tab", "arena": "C" }],
	})
	assert_eq(_moves(sim), ["4.00 C click"])


# JS: the pace: the camera moves by itself at most 3 times in any 10 s; the most urgent pull goes first when it may
func test_the_pace_the_camera_moves_by_itself_at_most_3_times_in_any_10_s_the_most_urgent_pull_goes_first_when_it_may() -> void:
	var sim := _run({
		"opened": _open("ABCD"),
		"opts": { "follow": { "approval": true, "fail": true, "open": true, "join": true, "done": true, "activity": false } },
		"events": [
			{ "t": 1.0, "arena": "B", "n": 5, "kind": "fail" }, { "t": 2.0, "arena": "C", "n": 9, "kind": "join" }, { "t": 3.0, "arena": "D", "n": 13, "kind": "done" },
			{ "t": 6.0, "arena": "A", "n": 1, "kind": "approval", "until": 30.0 }, { "t": 7.0, "arena": "B", "n": 6, "kind": "done" }, { "t": 8.0, "arena": "C", "n": 10, "kind": "fail" },
		],
	})
	# three moves 2 s apart (the hold after each; a finished turn before a new agent); then the approval, let past
	# the pace and counted as a move, and read for 4 s; then C's failure and B's finished turn wait until fewer
	# than three moves are younger than 10 s, and go in their order: the failure first
	assert_eq(_moves(sim), ["1.50 B pull:fail", "3.50 D pull:done", "5.50 C pull:join", "7.50 A pull:approval", "13.50 C pull:fail", "15.50 B pull:done"])
	assert_eq(sim.at(12.5)["held"], true, "held back by the pace")
	assert_eq(sim.at(4.0)["held"], false)


# JS: approvals are let past the pace; other pulls are not
func test_approvals_are_let_past_the_pace_other_pulls_are_not() -> void:
	var approvals: Array = [
		{ "t": 1.0, "arena": "B", "n": 5, "kind": "approval", "until": 3.0 },
		{ "t": 4.0, "arena": "C", "n": 9, "kind": "approval", "until": 6.0 },
		{ "t": 7.0, "arena": "D", "n": 13, "kind": "approval", "until": 20.0 },
	]
	assert_eq(_moves(_run({ "opened": _open("ABCD"), "events": approvals, "opts": { "pace": 0.1 } })), ["1.50 B pull:approval", "4.00 C pull:approval", "7.00 D pull:approval"])
	var dones: Array = []
	for e: Dictionary in approvals:
		var done: Dictionary = e.duplicate()
		done["kind"] = "done"
		dones.append(done)
	assert_eq(_moves(_run({ "opened": _open("ABCD"), "events": dones, "opts": { "pace": 0.1 } })), ["1.50 B pull:done", "11.50 C pull:done"], "one in any 10 s: C waits, D expires")


# JS: the pace can be changed or lifted, and it never limits the person
func test_the_pace_can_be_changed_or_lifted_and_it_never_limits_the_person() -> void:
	var dones: Array = [{ "t": 1.0, "arena": "B", "n": 5, "kind": "done" }, { "t": 4.0, "arena": "C", "n": 9, "kind": "done" }, { "t": 7.0, "arena": "D", "n": 13, "kind": "done" }]
	var lifted := _run({ "opened": _open("ABCD"), "events": dones, "opts": { "pace": 0.1 }, "inputs": [{ "t": 5.0, "pace": INF }] })
	assert_eq(_moves(lifted), ["1.50 B pull:done", "5.00 C pull:done", "7.00 D pull:done"])
	var clicks: Array = []
	var letters: String = "ABCDA"
	for i in 5:
		clicks.append({ "t": float(i + 2), "click": "tab", "arena": letters[i] })
	assert_eq(_moves(_run({ "opened": _open("ABCD"), "opts": { "pace": 0.1 }, "inputs": clicks })).size(), 4, "every click moves the camera")
	assert_eq(DEFAULTS["pace"], 0.3)
