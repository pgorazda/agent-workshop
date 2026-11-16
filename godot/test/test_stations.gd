extends GutTest
## The station table (phase G-3): nine stations, one for each category, with the stand points of the mockup (frozen below).

const Stations := preload("res://src/core/stations.gd")
const Event := preload("res://src/core/event.gd")
const Atlas := preload("res://art/atlas.gd")
const Data := preload("res://art/atlas_data.gd")
const RoomStageArt := preload("res://art/room_stage_art.gd")

## The metre table and the pixel points agree to this many pixels (see the README, "Phase G-3").
const PROJECTION_TOLERANCE := 45.0
## Two stand points of different places are at least this far apart, so that penguins do not overlap.
const MIN_DISTANCE := 16.0
const LINE_PLACES_IN_ROOM := 4
## The `PTS` table of the JavaScript mockup. The stand points
## in `stations.gd` must stay equal to it. A deliberate change to a point changes this table in the same step.
const MOCKUP_POINTS: Dictionary = {
	"map": Vector2i(96, 86), "shelf": Vector2i(66, 126), "benchL": Vector2i(222, 98), "benchR": Vector2i(258, 98),
	"forge": Vector2i(366, 93), "forge2": Vector2i(398, 114), "chairFront": Vector2i(90, 222), "seat": Vector2i(90, 201),
	"desk": Vector2i(350, 208), "sign": Vector2i(236, 216), "signQ": Vector2i(204, 219), "scope": Vector2i(422, 158),
	"helperPop": Vector2i(434, 214), "forgeQ": Vector2i(336, 100), "spotA": Vector2i(332, 152), "spotB": Vector2i(446, 198),
	"rug": Vector2i(240, 150), "stage": Vector2i(344, 168), "door": Vector2i(323, 222), "out": Vector2i(323, 280),
	"odd": Vector2i(74, 160),
}


func _all_places() -> Array[Dictionary]:
	var places: Array[Dictionary] = []
	for station in Stations.TABLE:
		for spot: Dictionary in station["spots"]:
			places.append({"name": "%s/%s" % [station["category"], spot["at"]], "point": Stations.point(spot["at"])})
		places.append({"name": "%s/queue" % station["category"], "point": Stations.point(station["queue"]["at"])})
	return places


# ---------------------------------------------------------------- the table

func test_there_is_one_station_for_each_category_in_the_order_of_the_schema() -> void:
	var categories: Array[String] = []
	for station in Stations.TABLE:
		categories.append(station["category"])
	assert_eq(categories, Event.CATEGORIES, "the stations follow the categories of event.gd (which the schema test checks)")
	assert_eq(Stations.TABLE.size(), 9)


func test_a_category_gives_its_station_and_an_unknown_one_gives_odd_jobs() -> void:
	for category: String in Event.CATEGORIES:
		assert_eq(Stations.for_category(category)["category"], category)
	assert_eq(Stations.for_category("something-new")["category"], "other")
	assert_eq(Stations.for_category("")["category"], "other")


func test_a_station_has_no_tool_name() -> void:
	# A station is chosen by category only (rule 2). The table carries no raw tool name.
	var allowed: Array[String] = ["category", "name", "prop", "spots", "queue"]
	for station in Stations.TABLE:
		assert_eq((station as Dictionary).keys().size(), allowed.size())
		for key: String in allowed:
			assert_true((station as Dictionary).has(key), "%s has %s" % [station["category"], key])


func test_every_prop_and_animation_exists_in_the_atlas() -> void:
	for station in Stations.TABLE:
		assert_true(Atlas.has(station["prop"]), "prop %s" % station["prop"])
		for spot: Dictionary in station["spots"]:
			assert_true(Data.ANIMATIONS.has(spot["anim"]), "animation %s" % spot["anim"])
			var frames: int = (Data.ANIMATIONS[spot["anim"]]["poses"] as Array).size()
			assert_lt(int(spot.get("frame", 0)), frames, "the first frame of %s is a real frame" % spot["anim"])
			for cord: String in Data.CORDS:
				var look: Dictionary = RoomStageArt.look_of(spot["anim"], int(spot.get("frame", 0)))
				assert_ne(RoomStageArt.penguin_picture(cord, look["dir"], look["pose"]), "", "a picture for %s of %s" % [spot["anim"], cord])


# ---------------------------------------------------------------- the points

func test_the_points_are_the_frozen_pts_of_the_mockup() -> void:
	assert_eq(MOCKUP_POINTS.size(), Stations.POINTS.size(), "same number of points")
	for point_name: String in MOCKUP_POINTS:
		assert_true(Stations.POINTS.has(point_name), "point %s" % point_name)
		assert_eq(Stations.POINTS.get(point_name), MOCKUP_POINTS[point_name], "value of %s" % point_name)
	assert_true(Stations.POINTS.has("forgeQ") and Stations.POINTS.has("signQ"), "the two queue points of the mockup")


func test_the_chosen_queue_points_are_the_ones_that_the_mockup_does_not_have() -> void:
	for point_name in Stations.CHOSEN_POINTS:
		assert_true(Stations.QUEUE_POINTS.has(point_name), "%s is a chosen point" % point_name)
		assert_false(MOCKUP_POINTS.has(point_name), "%s is not in the mockup" % point_name)
	assert_eq(Stations.QUEUE_POINTS.size(), Stations.CHOSEN_POINTS.size())
	# Seven chosen points and the two of the mockup give each of the nine stations its own queue point.
	var queue_names: Dictionary = { }
	for station in Stations.TABLE:
		queue_names[station["queue"]["at"]] = true
	assert_eq(queue_names.size(), 9, "each station has its own queue point")


func test_every_name_of_the_table_is_a_point() -> void:
	for station in Stations.TABLE:
		for spot: Dictionary in station["spots"]:
			assert_true(Stations.POINTS.has(spot["at"]), "spot %s" % spot["at"])
		var queue_at: String = station["queue"]["at"]
		assert_true(Stations.POINTS.has(queue_at) or Stations.QUEUE_POINTS.has(queue_at), "queue %s" % queue_at)


func test_spots_and_the_first_places_in_line_lie_in_the_room() -> void:
	var room := Rect2i(Vector2i.ZERO, Stations.ROOM_SIZE)
	for station in Stations.TABLE:
		for spot: Dictionary in station["spots"]:
			assert_true(room.has_point(Stations.point(spot["at"])), "%s spot %s in the room" % [station["category"], spot["at"]])
		for i in LINE_PLACES_IN_ROOM:
			assert_true(room.has_point(Stations.queue_place(station, i)), "%s line place %d in the room" % [station["category"], i])


func test_no_two_places_are_on_top_of_each_other() -> void:
	var places: Array[Dictionary] = _all_places()
	for i in places.size():
		for j in range(i + 1, places.size()):
			var distance: float = Vector2(places[i]["point"]).distance_to(Vector2(places[j]["point"]))
			assert_gte(distance, MIN_DISTANCE, "%s and %s are far enough apart" % [places[i]["name"], places[j]["name"]])


func test_the_line_runs_one_step_at_a_time() -> void:
	var forge: Dictionary = Stations.for_category("exec")
	assert_eq(Stations.queue_place(forge, 0), Stations.POINTS["forgeQ"])
	assert_eq(Stations.queue_place(forge, 1), Stations.POINTS["forgeQ"] + Vector2i(-Stations.QUEUE_STEP, 0))
	assert_eq(Stations.queue_place(forge, 3), Stations.POINTS["forgeQ"] + Vector2i(-3 * Stations.QUEUE_STEP, 0))


# ---------------------------------------------------------------- the metre table

func test_the_projection_has_the_numbers_of_the_2d_view_plan() -> void:
	assert_eq(Stations.project(Vector2.ZERO), Vector2(240, 138))
	assert_eq(Stations.project(Vector2(1, 0)), Vector2(268, 138))
	assert_eq(Stations.project(Vector2(0, 1)), Vector2(240, 127))
	assert_eq(Stations.project(Vector2(-7, 3)), Vector2(44, 105))


func test_the_metre_table_lands_in_the_room_and_near_the_pixel_points() -> void:
	var room := Rect2(Vector2.ZERO, Vector2(Stations.ROOM_SIZE))
	assert_eq(Stations.FLOOR_METRES.size(), 9)
	for station in Stations.TABLE:
		var screen: Vector2 = Stations.project(Stations.FLOOR_METRES[station["category"]])
		assert_true(room.has_point(screen), "%s projects into the room" % station["category"])
		var nearest: float = INF
		for spot: Dictionary in station["spots"]:
			nearest = minf(nearest, screen.distance_to(Vector2(Stations.point(spot["at"]))))
		assert_lte(nearest, PROJECTION_TOLERANCE, "%s: the metre table is near a pixel stand point (%.1f px)" % [station["category"], nearest])
		gut.p("%s: metres %s -> %s, nearest spot %.1f px" % [station["category"], Stations.FLOOR_METRES[station["category"]], screen, nearest])
