extends GutTest
## The porting traps of `docs/godot-client-plan.md`, each with a test. A trap that a golden fixture cannot
## show (it needs a negative half, or a language rule) has its test here.

const ArenaRules := preload("res://src/core/arena_rules.gd")


func test_js_round_is_math_round() -> void:
	# Math.round(-1.5) is -1, Math.round(-0.5) is -0, Math.round(0.5) is 1, Math.round(2.5) is 3
	assert_eq(ArenaRules.js_round(-1.5), -1.0)
	assert_eq(ArenaRules.js_round(-0.5), 0.0, "round(-0.5) in GDScript is -1: this is the trap")
	assert_eq(ArenaRules.js_round(0.5), 1.0)
	assert_eq(ArenaRules.js_round(1.5), 2.0)
	assert_eq(ArenaRules.js_round(2.5), 3.0)
	assert_eq(ArenaRules.js_round(-2.5), -2.0)
	assert_eq(ArenaRules.js_round(0.49999999999999994), 0.0, "floor(x + 0.5) would give 1 here")
	assert_eq(ArenaRules.js_round(INF), INF)
	assert_eq(round(-0.5), -1.0, "the built-in rounds a negative half away from zero")


func test_a_lambda_copies_the_local_variables_it_uses() -> void:
	# Why the camera keeps its state in member fields: a lambda that changes a local number changes its copy.
	var counter: int = 0
	var list: Array = []
	var change: Callable = func() -> void:
		@warning_ignore("confusable_capture_reassignment")
		counter += 1
		list.append(1)
	change.call()
	assert_eq(counter, 0, "the number is copied")
	assert_eq(list, [1], "an array is shared: only the variable is copied")


func test_equal_times_keep_their_order() -> void:
	# JavaScript sorts are stable. A GDScript sort is not. `sorted_by_t` adds the position as a tie-break.
	var list: Array = []
	for i in 200:
		list.append({ "t": float(i % 3), "id": i })
	var sorted: Array = ArenaRules.CameraSim.sorted_by_t(list)
	var previous: Dictionary = sorted[0]
	var wrong: Array = []
	for item: Dictionary in sorted.slice(1):
		var in_order: bool = float(item["t"]) > float(previous["t"]) or (float(item["t"]) == float(previous["t"]) and int(item["id"]) > int(previous["id"]))
		if not in_order:
			wrong.append([previous["id"], item["id"]])
		previous = item
	assert_eq(wrong, [])


func test_two_arenas_with_the_same_newest_activity_go_to_the_first_in_letter_order() -> void:
	# `sort` in JavaScript keeps B before C. The port scans and keeps the first.
	var sim: ArenaRules.CameraResult = ArenaRules.simulate_camera({
		"duration": 30.0,
		"opened": [{ "letter": "A", "t": 0.0 }, { "letter": "B", "t": 0.0 }, { "letter": "C", "t": 0.0 }],
		"events": [
			{ "t": 0.5, "arena": "A", "n": 1, "kind": "activity" },
			{ "t": 7.0, "arena": "C", "n": 3, "kind": "activity" },
			{ "t": 7.0, "arena": "B", "n": 2, "kind": "activity" },
		],
	})
	assert_eq(sim.log.size(), 1)
	assert_eq(sim.log[0]["to"], "B")
	assert_eq(sim.log[0]["why"], "activity")


func test_an_approval_with_no_answer_time_stays_open_for_ever() -> void:
	# JavaScript: `e.until ?? Infinity`.
	var sim: ArenaRules.CameraResult = ArenaRules.simulate_camera({
		"duration": 30.0,
		"opened": [{ "letter": "A", "t": 0.0 }, { "letter": "B", "t": 0.0 }],
		"opts": { "mode": "MANUAL" },
		"events": [{ "t": 2.0, "arena": "B", "n": 2, "kind": "approval" }],
	})
	assert_eq(sim.at(1.0)["pending"], [])
	assert_eq(sim.at(29.9)["pending"], ["approval:B"])


func test_no_limit_is_infinity_and_no_room_is_null() -> void:
	assert_eq(ArenaRules.DEFAULTS["max_arenas"], INF)
	var model := ArenaRules.create_arenas({ "arena_size": 1, "max_arenas": 2 })
	assert_eq(model.place(1, 0.0), "A")
	assert_eq(model.place(2, 0.0), "B")
	assert_null(model.place(3, 0.0), "every arena is full and no more may open")
	assert_null(model.arena_of(3), "an agent that is not placed has no arena")
	assert_eq(model.arena_of(2), "B")


func test_frames_have_null_where_the_javascript_has_null() -> void:
	var sim: ArenaRules.CameraResult = ArenaRules.simulate_camera({
		"duration": 5.0,
		"opened": [{ "letter": "A", "t": 0.0 }, { "letter": "B", "t": 0.0 }],
		"inputs": [{ "t": 1.0, "key": "Tab" }],
	})
	var in_arena: Dictionary = sim.at(0.5)
	assert_eq(in_arena["arena"], "A")
	assert_null(in_arena["from"])
	assert_null(in_arena["ribbon"])
	var in_page: Dictionary = sim.at(3.0)
	assert_null(in_page["arena"])
	assert_eq(in_page["from"], "A")
	assert_eq(in_page["arena_from"], "A", "the move to the overview started at arena A")


func test_names_do_not_use_integer_division_wrongly() -> void:
	# nameOf divides by 26 and rounds down at every step.
	assert_eq(ArenaRules.name_of(701), "ZZ")
	assert_eq(ArenaRules.name_of(702), "AAA")
	assert_eq(ArenaRules.name_of(18277), "ZZZ")
	assert_eq(ArenaRules.name_of(18278), "AAAA")
	assert_eq(ArenaRules.index_of("ZZZ"), 18277)
