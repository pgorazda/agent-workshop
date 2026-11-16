extends GutTest
## The step from an actor to the dictionary of the room stage.

const PenguinView := preload("res://src/view/penguin_view.gd")
const PenguinActor := preload("res://src/core/penguin_actor.gd")
const Director := preload("res://src/core/director.gd")
const Clock := preload("res://src/core/clock.gd")
const RoomStageArt := preload("res://art/room_stage_art.gd")
const Atlas := preload("res://art/atlas.gd")
const Trace := preload("res://test/support/trace.gd")


func _actor(facing: String, pose: String) -> RefCounted:
	var actor: RefCounted = PenguinActor.new()
	actor.facing = facing
	actor.pose = pose
	actor.position = Vector2(100, 120)
	actor.cord = "pi"
	return actor


func test_the_left_view_is_the_side_picture_mirrored() -> void:
	var left: Dictionary = PenguinView.penguin_of(_actor("left", "walk"))
	assert_eq([left["dir"], left["flip"]], ["side", true])
	var right: Dictionary = PenguinView.penguin_of(_actor("right", "walk"))
	assert_eq([right["dir"], right["flip"]], ["side", false])
	assert_eq(PenguinView.penguin_of(_actor("front", "idle"))["dir"], "front")
	assert_eq(PenguinView.penguin_of(_actor("back", "hammer"))["dir"], "back")


func test_a_hidden_actor_gives_nothing() -> void:
	var actor: RefCounted = _actor("front", "idle")
	actor.hidden = true
	assert_true(PenguinView.penguin_of(actor).is_empty())
	assert_eq(PenguinView.crowd_of([actor] as Array[RefCounted]).size(), 0)


func test_a_helper_is_small_with_a_flatter_shadow() -> void:
	var actor: RefCounted = _actor("front", "wave")
	actor.is_helper = true
	var penguin: Dictionary = PenguinView.penguin_of(actor)
	assert_true(penguin["small"])
	assert_eq(penguin["shadow_ry"], PenguinView.HELPER_SHADOW_HEIGHT)


func test_every_picture_of_a_whole_story_exists() -> void:
	# Play the made-up session and the multi-agent scene, and look up the picture of each penguin at each step.
	var TimelinePlayer: GDScript = load("res://src/net/timeline_player.gd")
	for scene: String in ["session", "multi"]:
		var player: RefCounted = TimelinePlayer.load_file("res://demo/%s.json" % scene)
		var director: RefCounted = Director.new()
		var clock: RefCounted = Clock.new()
		var missing: Dictionary = { }
		while clock.now < 34.0:
			for event: RefCounted in player.due_events(clock.now):
				director.handle_event(event)
			clock.tick()
			director.step(clock.now)
			if int(clock.now * 60.0) % 6 != 0:
				continue
			var actors: Array[RefCounted] = director.penguins()
			actors.append_array(director.helpers())
			for penguin in PenguinView.crowd_of(actors):
				if float(penguin["flop"]) >= 0.0:
					continue
				var picture: String = RoomStageArt.penguin_picture(str(penguin["cord"]), str(penguin["dir"]), str(penguin["pose"]), bool(penguin["blink"]), bool(penguin.get("small", false)))
				if picture == "" or not Atlas.has(picture):
					missing["%s/%s/%s" % [penguin["cord"], penguin["dir"], penguin["pose"]]] = true
		assert_eq(missing.keys(), [], "%s: a picture for each pose" % scene)
