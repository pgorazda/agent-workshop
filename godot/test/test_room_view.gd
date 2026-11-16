extends GutTest
## The room view (phase G-3): one penguin at each station, props and penguins in the order of their depth.

const RoomView := preload("res://src/view/room_view.gd")
const RoomStageArt := preload("res://art/room_stage_art.gd")
const Stations := preload("res://src/core/stations.gd")
const Event := preload("res://src/core/event.gd")
const Atlas := preload("res://art/atlas.gd")
const Data := preload("res://art/atlas_data.gd")


func test_there_is_one_penguin_at_the_first_spot_of_each_station() -> void:
	var crowd: Array[Dictionary] = RoomView.standing_penguins("claude-code")
	assert_eq(crowd.size(), Event.CATEGORIES.size())
	for i in crowd.size():
		var station: Dictionary = Stations.TABLE[i]
		var point: Vector2i = Stations.point(station["spots"][0]["at"])
		assert_eq(Vector2i(crowd[i]["x"], crowd[i]["y"]), point, "%s: the penguin stands on the first spot" % station["category"])


func test_every_penguin_has_a_picture_in_the_atlas() -> void:
	for penguin in RoomView.standing_penguins("claude-code"):
		var picture: String = RoomStageArt.penguin_picture(penguin["cord"], penguin["dir"], penguin["pose"])
		assert_ne(picture, "", "a picture for %s" % penguin)
		assert_true(Atlas.has(picture))


func test_the_pose_and_direction_of_each_station() -> void:
	var by_station: Dictionary = { }
	var crowd: Array[Dictionary] = RoomView.standing_penguins("claude-code")
	for i in crowd.size():
		by_station[Stations.TABLE[i]["category"]] = crowd[i]
	# the poses of the mockup (`act` of the JavaScript mockup, removed): the first frame of each activity
	assert_eq([by_station["read"]["dir"], by_station["read"]["pose"], by_station["read"]["flip"]], ["side", "read", true])
	assert_eq([by_station["search"]["dir"], by_station["search"]["pose"], by_station["search"]["flip"]], ["side", "browse", false])
	assert_eq([by_station["write"]["dir"], by_station["write"]["pose"]], ["back", "hammer"])
	assert_eq([by_station["exec"]["dir"], by_station["exec"]["pose"]], ["side", "shovel2"])
	assert_eq([by_station["web"]["dir"], by_station["web"]["pose"]], ["side", "peer"])
	assert_eq([by_station["delegate"]["dir"], by_station["delegate"]["pose"]], ["side", "tap"])
	assert_eq([by_station["think"]["dir"], by_station["think"]["pose"]], ["front", "think"])
	assert_eq([by_station["ask_permission"]["dir"], by_station["ask_permission"]["pose"]], ["front", "waveL"])
	assert_eq([by_station["other"]["dir"], by_station["other"]["pose"], by_station["other"]["flip"]], ["side", "hammer", true])
	assert_eq(by_station["think"]["shadow"], 0, "the penguin in the chair has no shadow")


func test_penguin_picture_falls_back_to_the_grey_cord_and_finds_nothing_for_a_missing_pose() -> void:
	assert_eq(RoomStageArt.penguin_picture("no-such-framework", "front", "idle"), "penguin/default/front/idle")
	assert_eq(RoomStageArt.penguin_picture("pi", "front", "no-such-pose"), "")
	assert_eq(RoomStageArt.penguin_picture("pi", "front", "idle", true), "penguin/pi/front/idle/blink")


func test_look_of_counts_frames_round_and_has_a_default() -> void:
	assert_eq(RoomStageArt.look_of("read", 2)["pose"], "read2")
	assert_eq(RoomStageArt.look_of("read", 3)["pose"], "read", "the frame counts round")
	assert_eq(RoomStageArt.look_of("write", 1)["pose"], "hammer2")
	assert_eq(RoomStageArt.look_of("no-such-activity"), {"dir": "front", "pose": "idle", "flip": false})


func test_props_and_penguins_are_drawn_in_the_order_of_their_depth() -> void:
	var items: Array[Dictionary] = RoomStageArt.build_items(Data.PROP_PLACES, RoomView.standing_penguins("claude-code"))
	assert_eq(items.size(), Data.PROP_PLACES.size() + 9)
	for i in range(1, items.size()):
		assert_lte(items[i - 1]["depth"], items[i]["depth"], "depth does not go back at item %d" % i)
	var chair_back: int = -1
	var chair_front: int = -1
	var sitter: int = -1
	for i in items.size():
		if items[i]["kind"] == "prop":
			if items[i]["place"]["name"] == "prop/chair-back":
				chair_back = i
			elif items[i]["place"]["name"] == "prop/chair-front":
				chair_front = i
		elif items[i]["penguin"]["pose"] == "think":
			sitter = i
	assert_true(chair_back >= 0 and chair_front >= 0 and sitter >= 0)
	assert_true(chair_back < sitter and sitter < chair_front, "the penguin in the chair sits between the back and the front of the chair")


func test_equal_depths_keep_the_order_of_adding_and_props_come_first() -> void:
	var places: Array[Dictionary] = [
		{"name": "prop/a", "depth": 50, "x": 0, "by": 50},
		{"name": "prop/b", "depth": 10, "x": 0, "by": 10},
		{"name": "prop/c", "depth": 50, "x": 0, "by": 50},
	]
	var crowd: Array[Dictionary] = [
		{"x": 0, "y": 50, "cord": "pi", "dir": "front", "pose": "idle"},
		{"x": 0, "y": 10, "cord": "pi", "dir": "front", "pose": "walk"},
	]
	var items: Array[Dictionary] = RoomStageArt.build_items(places, crowd)
	var order: Array[String] = []
	for item in items:
		order.append(item["place"]["name"] if item["kind"] == "prop" else "penguin:%s" % item["penguin"]["pose"])
	assert_eq(order, ["prop/b", "penguin:walk", "prop/a", "prop/c", "penguin:idle"])


func test_the_stage_node_draws_the_room_without_errors() -> void:
	var stage: Node2D = RoomStageArt.new()
	stage.set_penguins(RoomView.standing_penguins("claude-code"))
	add_child_autofree(stage)
	await wait_process_frames(2)
	assert_eq(stage.penguins.size(), 9)


func test_the_room_scene_shows_nine_penguins_and_the_sign_of_one_arena() -> void:
	var scene: PackedScene = load("res://src/room.tscn")
	var view: Node = scene.instantiate()
	add_child_autofree(view)
	await wait_process_frames(2)
	assert_eq(view.stage.penguins.size(), 9)
	assert_eq(view.stage.letter, "", "an empty letter is the sign AGENT WORKSHOP")
