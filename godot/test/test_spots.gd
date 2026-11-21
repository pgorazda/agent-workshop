extends GutTest
## Spots and the queue, the three rules:
## a penguin takes the first free spot, a full station gives a queue, and a spot is freed when its penguin leaves.

const Spots := preload("res://src/core/spots.gd")
const Stations := preload("res://src/core/stations.gd")
const Event := preload("res://src/core/event.gd")
const Rng := preload("res://src/core/rng.gd")

var spots: RefCounted


func before_each() -> void:
	spots = Spots.new()


# ---------------------------------------------------------------- rule 1: the first free spot

func test_the_first_agent_takes_the_first_spot_and_the_next_one_the_next_spot() -> void:
	var first: Dictionary = spots.arrive("a", "write")
	var second: Dictionary = spots.arrive("b", "write")
	assert_eq(first["spot"], 0)
	assert_eq(first["at"], "benchL")
	assert_eq(first["point"], Stations.POINTS["benchL"])
	assert_false(first["queued"])
	assert_eq(second["spot"], 1)
	assert_eq(second["at"], "benchR")
	assert_eq(second["point"], Stations.POINTS["benchR"])


func test_a_free_spot_before_a_busy_one_is_taken_first() -> void:
	spots.arrive("a", "exec")
	spots.arrive("b", "exec")
	spots.leave("a")
	assert_eq(spots.holder("exec", 0), null, "the first spot of the forge is free")
	spots.arrive("c", "exec")
	assert_eq(spots.holder("exec", 0), "c", "the new penguin takes the first free spot, not the one after the busy one")
	assert_eq(spots.holder("exec", 1), "b")


func test_stations_do_not_share_spots() -> void:
	for category: String in Event.CATEGORIES:
		var placement: Dictionary = spots.arrive("agent-%s" % category, category)
		assert_eq(placement["spot"], 0, "%s: its own first spot" % category)
		assert_eq(placement["category"], category)
		assert_eq(placement["point"], Stations.point(Stations.for_category(category)["spots"][0]["at"]))
	assert_eq(spots.line_of("write"), [])


func test_the_armchair_seats_one_and_the_other_thinkers_stand_on_the_spots_of_the_floor() -> void:
	var seat: Dictionary = spots.arrive(1, "think")
	var second: Dictionary = spots.arrive(2, "think")
	var third: Dictionary = spots.arrive(3, "think")
	assert_eq(seat["at"], "seat")
	assert_eq(seat["shadow"], 0, "a penguin in the chair has no shadow")
	assert_eq(second["at"], "spotA")
	assert_eq(third["at"], "spotB")
	assert_eq(second["shadow"], 7)
	assert_true(spots.arrive(4, "think")["queued"], "a fourth thinker waits")


func test_the_telescope_and_the_helper_desk_keep_one_spot() -> void:
	for category: String in ["web", "delegate"]:
		assert_eq((Stations.for_category(category)["spots"] as Array).size(), 1, "%s has one spot" % category)
		assert_false(spots.arrive("first-%s" % category, category)["queued"])
		assert_true(spots.arrive("second-%s" % category, category)["queued"], "the second one waits")


func test_the_second_bench_spot_starts_on_the_other_frame() -> void:
	assert_eq(spots.arrive("a", "write")["frame"], 0)
	assert_eq(spots.arrive("b", "write")["frame"], 1, "the two hammers do not move together")


func test_an_unknown_category_goes_to_the_odd_jobs() -> void:
	var placement: Dictionary = spots.arrive("a", "no-such-category")
	assert_eq(placement["category"], "other")
	assert_eq(placement["at"], "odd")


# ---------------------------------------------------------------- rule 2: a full station gives a queue

func test_a_full_station_gives_a_queue() -> void:
	spots.arrive("a", "exec")
	spots.arrive("b", "exec")
	assert_true(spots.is_full("exec"))
	var third: Dictionary = spots.arrive("c", "exec")
	var fourth: Dictionary = spots.arrive("d", "exec")
	assert_true(third["queued"])
	assert_eq(third["spot"], -1)
	assert_eq(third["line"], 0)
	assert_eq(third["at"], "forgeQ")
	assert_eq(third["point"], Stations.POINTS["forgeQ"], "the first one waits at the queue point of the mockup")
	assert_eq(third["anim"], "queue")
	assert_eq(fourth["line"], 1)
	assert_eq(fourth["point"], Stations.POINTS["forgeQ"] + Vector2i(-Stations.QUEUE_STEP, 0), "the next one waits one step further")
	assert_eq(spots.line_of("exec"), ["c", "d"])


func test_the_sign_post_has_one_spot_and_a_line() -> void:
	assert_eq(spots.arrive("a", "ask_permission")["point"], Stations.POINTS["sign"])
	var waiting: Dictionary = spots.arrive("b", "ask_permission")
	assert_true(waiting["queued"])
	assert_eq(waiting["point"], Stations.POINTS["signQ"])


func test_every_station_gives_a_queue_when_it_is_full() -> void:
	for station in Stations.TABLE:
		var category: String = station["category"]
		var spot_count: int = (station["spots"] as Array).size()
		for i in spot_count:
			assert_false(spots.arrive("%s-%d" % [category, i], category)["queued"])
		var waiting: Dictionary = spots.arrive("%s-waits" % category, category)
		assert_true(waiting["queued"], "%s: the %dth penguin waits" % [category, spot_count + 1])
		assert_eq(waiting["point"], Stations.queue_place(station, 0))


func test_a_queued_agent_keeps_its_place_when_it_arrives_again() -> void:
	spots.arrive("a", "web")
	spots.arrive("b", "web")
	spots.arrive("c", "web")
	var again: Dictionary = spots.arrive("c", "web")
	assert_eq(again["line"], 1)
	assert_eq(spots.line_of("web"), ["b", "c"], "no double entry")


# ---------------------------------------------------------------- rule 3: a spot is freed when its penguin leaves

func test_a_spot_is_free_when_its_penguin_leaves() -> void:
	spots.arrive("a", "web")
	assert_true(spots.is_full("web"))
	var changed: Array[Dictionary] = spots.leave("a")
	assert_eq(changed, [], "nobody was waiting")
	assert_eq(spots.holder("web", 0), null)
	assert_eq(spots.free_count("web"), 1)
	assert_false(spots.has("a"))
	assert_eq(spots.placement_of("a"), { })
	var next: Dictionary = spots.arrive("b", "web")
	assert_false(next["queued"], "the freed spot is given out again")
	assert_eq(next["point"], Stations.POINTS["scope"])


func test_the_first_in_line_takes_a_spot_that_is_freed() -> void:
	spots.arrive("a", "web")
	spots.arrive("b", "web")
	spots.arrive("c", "web")
	var changed: Array[Dictionary] = spots.leave("a")
	assert_eq(changed.size(), 2, "b takes the spot and c moves up")
	assert_eq(changed[0]["agent"], "b")
	assert_false(changed[0]["queued"])
	assert_eq(changed[0]["point"], Stations.POINTS["scope"])
	assert_eq(changed[1]["agent"], "c")
	assert_eq(changed[1]["line"], 0)
	assert_eq(changed[1]["point"], Stations.QUEUE_POINTS["scopeQ"])
	assert_eq(spots.holder("web", 0), "b")
	assert_eq(spots.line_of("web"), ["c"])


func test_the_freed_spot_goes_to_the_one_in_line_even_when_it_is_not_the_first_spot() -> void:
	spots.arrive("a", "write")
	spots.arrive("b", "write")
	spots.arrive("c", "write")
	spots.leave("b")
	assert_eq(spots.holder("write", 1), "c", "c took the spot of b")
	assert_eq(spots.holder("write", 0), "a")


func test_an_agent_that_waits_can_leave_and_the_ones_behind_move_up() -> void:
	spots.arrive("a", "web")
	spots.arrive("b", "web")
	spots.arrive("c", "web")
	spots.arrive("d", "web")
	var changed: Array[Dictionary] = spots.leave("b")
	assert_eq(changed.size(), 2)
	assert_eq(changed[0]["agent"], "c")
	assert_eq(changed[0]["line"], 0)
	assert_eq(changed[1]["agent"], "d")
	assert_eq(changed[1]["line"], 1)
	assert_eq(spots.holder("web", 0), "a", "the one at work stays")


func test_leaving_when_not_present_changes_nothing() -> void:
	assert_eq(spots.leave("nobody"), [])
	spots.arrive("a", "read")
	assert_eq(spots.leave("nobody"), [])
	assert_true(spots.has("a"))


func test_an_agent_that_goes_to_another_station_frees_its_spot() -> void:
	spots.arrive("a", "read")
	spots.arrive("b", "read")
	var moved: Dictionary = spots.arrive("a", "search")
	assert_eq(moved["category"], "search")
	assert_eq(spots.holder("read", 0), "b", "b took the spot of a at the shelf when a left")
	assert_eq(spots.line_of("read"), [])
	var back: Dictionary = spots.arrive("a", "read")
	assert_true(back["queued"], "the shelf is full again")
	spots.arrive("a", "write")
	assert_eq(spots.line_of("read"), [], "a left the line of the shelf when it went to the bench")


# ---------------------------------------------------------------- the rules together

func test_numbers_and_strings_work_as_agents() -> void:
	spots.arrive(7, "exec")
	spots.arrive("seven", "exec")
	assert_eq(spots.holder("exec", 0), 7)
	assert_eq(spots.holder("exec", 1), "seven")
	assert_true(spots.has(7))
	assert_true(spots.has("seven"))


func test_a_long_random_run_never_puts_two_agents_on_one_spot() -> void:
	var rng: RefCounted = Rng.mulberry32(11)
	var present: Array = []
	for step in 600:
		var roll: float = rng.next()
		if roll < 0.55 or present.is_empty():
			var agent: int = int(rng.next() * 12)
			var category: String = Event.CATEGORIES[int(rng.next() * Event.CATEGORIES.size())]
			spots.arrive(agent, category)
			if not present.has(agent):
				present.append(agent)
		else:
			var gone: int = present.pop_at(int(rng.next() * present.size()))
			spots.leave(gone)
		_check_invariants(present)


func _check_invariants(present: Array) -> void:
	var seen_points: Dictionary = { }
	for agent: Variant in present:
		var placement: Dictionary = spots.placement_of(agent)
		assert_false(placement.is_empty(), "agent %s has a placement" % agent)
		var key: String = "%s/%s" % [placement["category"], placement["at"]]
		if not placement["queued"]:
			assert_false(seen_points.has(key), "no two agents on the spot %s" % key)
			seen_points[key] = agent
	for station in Stations.TABLE:
		var category: String = station["category"]
		var line: Array = spots.line_of(category)
		if not line.is_empty():
			assert_eq(spots.free_count(category), 0, "%s: nobody waits while a spot is free" % category)
		for i in line.size():
			assert_eq(spots.placement_of(line[i])["line"], i, "%s: line places are 0, 1, 2, ..." % category)
