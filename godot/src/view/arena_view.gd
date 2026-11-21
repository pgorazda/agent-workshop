extends Node2D
## The camera view: the rooms of all arenas in one shared world, seen through the camera.
##
## The world is a node that is moved and scaled by the camera's pose. Each arena is a room node (`art/room_stage_art.gd`) at its
## place on its page. The camera gives the centre `(cx, cy)` in rooms and how many rooms across it spans (`s`). So the scale of the
## world is 1/s: one arena fills the view at 1 (on whole pixels, with the nearest filter), a page fills it at 0.5, and a long move
## widens the view to 8 rooms across (0.125).
##
## Smooth scaling comes from the room textures: they have mipmaps and the room node uses trilinear filtering when the scale is not 1
## (spike S-6). The project does not snap vertices to whole pixels, so a scaled room does not jump. A room that is not in view is
## hidden: it does not draw, and the view does not even give it its penguins.
##
## This node has no drawing call. The free places, the page numbers and the rooms are drawn by the art nodes.

const ArenaRules := preload("res://src/core/arena_rules.gd")
const Camera := preload("res://src/core/camera.gd")
const PenguinView := preload("res://src/view/penguin_view.gd")
const RoomStageArt := preload("res://art/room_stage_art.gd")
const RoomArt := preload("res://art/room_art.gd")
const WorldArt := preload("res://art/world_art.gd")
const RibbonArt := preload("res://art/ribbon_art.gd")

const ROOM_WIDTH := 480.0
const ROOM_HEIGHT := 232.0
## The centre of the room area of the viewport.
const VIEW_CENTRE := Vector2(240.0, 116.0)
const VIEW_RECT := Rect2(0.0, 0.0, 480.0, 232.0)
## A scale this close to 1 is the scale of one arena: whole pixels and the nearest filter.
const ONE_ARENA_EPSILON := 1e-9
## A room drawn at a scale below 1 / FAR_FROM is "far": it has no glow, no effects and no shadows (see `RoomStageArt.far`).
const FAR_FROM := 2.5
## The page numbers show when the view is wider than this many rooms, and are fully clear 1.5 rooms later.
const PAGE_NUMBERS_FROM := 3.0
const PAGE_NUMBERS_RAMP := 1.5

var backdrop: Node2D
var world: Node2D
var overlay: Node2D
## letter -> room node (`RoomStageArt`).
var stages: Dictionary = { }
## The letters of the rooms that were drawn in the last update. Tests read this.
var visible_letters: Array[String] = []
## True when the last update used the filter of the scaled world.
var smooth: bool = false
## The number of times the room nodes were given their data. The benchmark and the tests read this.
var rooms_updated: int = 0
## The pose that the last update drew (after the cross-fade of reduced motion).
var drawn_pose: ArenaRules.Pose = ArenaRules.Pose.new()
var drawn_alpha: float = 1.0
## A room with one agent shows the chip and the label of the focus, as a room with several agents does (the scene `tour`).
var force_cards: bool = false

var _filter_smooth: bool = false


func _init() -> void:
	backdrop = WorldArt.new()
	backdrop.layer = "backdrop"
	world = Node2D.new()
	overlay = WorldArt.new()
	overlay.layer = "overlay"
	add_child(backdrop)
	add_child(world)
	add_child(overlay)


## The room node of an arena. It is made the first time that it is asked for.
func stage_of(letter: String) -> RoomStageArt:
	if not stages.has(letter):
		var stage: RoomStageArt = RoomStageArt.new()
		stage.visible = false
		stage.texture_filter = _filter()
		world.add_child(stage)
		stages[letter] = stage
	return stages[letter]


## Forgets every room. A new session starts with no rooms.
func clear() -> void:
	for stage: Node in stages.values():
		stage.queue_free()
	stages.clear()
	visible_letters.clear()


## The screen position of the top left corner of a room, and its scale, for a pose. The world is `origin + room * factor`.
static func transform_of(pose: ArenaRules.Pose) -> Dictionary:
	var factor: float = 1.0 / pose.s
	var origin: Vector2 = Vector2(VIEW_CENTRE.x - pose.cx * ROOM_WIDTH * factor, VIEW_CENTRE.y - pose.cy * ROOM_HEIGHT * factor)
	if absf(pose.s - 1.0) < ONE_ARENA_EPSILON:
		origin = Vector2(floorf(origin.x + 0.5), floorf(origin.y + 0.5))
	return { "origin": origin, "scale": factor }


## The rectangle of an arena's room on the screen for a pose.
static func screen_rect(letter: String, pose: ArenaRules.Pose) -> Rect2:
	var place: Dictionary = ArenaRules.place_of(letter)
	var t: Dictionary = transform_of(pose)
	var factor: float = t["scale"]
	var top_left: Vector2 = (t["origin"] as Vector2) + Vector2(float(place["x"]) * ROOM_WIDTH, float(place["y"]) * ROOM_HEIGHT) * factor
	return Rect2(top_left, Vector2(ROOM_WIDTH, ROOM_HEIGHT) * factor)


## The arena whose room is under a point of the screen, or "".
func arena_at(point: Vector2, camera: Camera, now: float) -> String:
	var pose: ArenaRules.Pose = camera.pose_at_time(now)
	for letter in camera.letters:
		if screen_rect(letter, pose).has_point(point):
			return letter
	return ""


## Gives the rooms in view their data and moves the world to the camera's pose. Call it once in each frame that draws.
func update_view(director: RefCounted, camera: Camera, now: float) -> void:
	var pose: ArenaRules.Pose = camera.pose_at_time(now)
	drawn_alpha = 1.0
	if bool(camera.o.get("reduced_motion", false)) and pose.k < 1.0:
		# reduced motion: a short cut. What was on screen fades out and what comes fades in.
		pose = ArenaRules.Pose.new(camera.move.from_pose.cx, camera.move.from_pose.cy, camera.move.from_pose.s) if pose.k < 0.5 else ArenaRules.Pose.new(camera.move.to_pose.cx, camera.move.to_pose.cy, camera.move.to_pose.s)
		drawn_alpha = absf(1.0 - 2.0 * camera.pose_at_time(now).k)
	drawn_pose = pose
	world.modulate.a = drawn_alpha
	var t: Dictionary = transform_of(pose)
	var factor: float = t["scale"]
	var origin: Vector2 = t["origin"]
	world.position = origin
	world.scale = Vector2(factor, factor)
	var one_arena: bool = absf(pose.s - 1.0) < ONE_ARENA_EPSILON
	smooth = not one_arena
	if smooth != _filter_smooth:
		_filter_smooth = smooth
		for stage: RoomStageArt in stages.values():
			stage.texture_filter = _filter()
	var letters: Array[String] = camera.letters
	if letters.is_empty():
		# before the first agent arrives the first arena is already there, empty (the mockup opens arena A at 0)
		letters = [ArenaRules.name_of(0)]
	var solo: bool = letters.size() == 1
	visible_letters.clear()
	var open: Dictionary = { }
	for letter in letters:
		open[letter] = true
		var rect: Rect2 = screen_rect(letter, pose)
		var stage: RoomStageArt = stage_of(letter)
		if not rect.intersects(VIEW_RECT):
			stage.visible = false
			continue
		visible_letters.append(letter)
		_update_room(stage, letter, solo, director, camera, now, one_arena)
	for letter: String in stages.keys():
		if not open.has(letter):
			(stages[letter] as Node).queue_free()
			stages.erase(letter)
	_update_backdrop(camera, pose, now)


func _filter() -> CanvasItem.TextureFilter:
	return CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if _filter_smooth else CanvasItem.TEXTURE_FILTER_NEAREST


func _update_room(stage: RoomStageArt, letter: String, solo: bool, director: RefCounted, camera: Camera, now: float, one_arena: bool) -> void:
	var place: Dictionary = ArenaRules.place_of(letter)
	var room: RefCounted = director.world_of(letter)
	var shake: float = float(room.effects.shake_offset(now)) if one_arena else 0.0
	stage.position = Vector2(float(place["x"]) * ROOM_WIDTH + shake, float(place["y"]) * ROOM_HEIGHT)
	stage.rug = str(RoomArt.rug_of_arena(ArenaRules.index_of(letter))["name"])
	stage.far = drawn_pose.s > FAR_FROM
	stage.letter = "" if solo else letter
	stage.time = now
	stage.cues = room.effects.active()
	var ribbon: Variant = camera.ribbon
	var age: float = -1.0
	if ribbon != null and (ribbon as Dictionary)["arena"] == letter:
		age = now - float((ribbon as Dictionary)["t"])
		if age > RibbonArt.LIFE:
			age = -1.0
	stage.ribbon_age = age
	stage.visible = true
	var actors: Array[RefCounted] = director.actors_in(letter)
	var focus_number: Variant = camera.focus_of(letter)
	stage.solo = solo and not force_cards and director.activity_log.agent_count(letter) <= 1
	if stage.far:
		stage.notices = []
		stage.focus_label = { }
	else:
		stage.notices = PenguinView.notices_of(actors, director.activity_log, letter)
		var focused: RefCounted = PenguinView.actor_with_number(actors, int(focus_number)) if focus_number != null else null
		if stage.solo:
			focused = PenguinView.main_actor(actors)
		stage.focus_label = director.activity_log.focus_label(focused.key) if focused != null else { }
	stage.set_penguins(PenguinView.crowd_of(actors, focus_number))
	rooms_updated += 1


## The free places of the pages in view, and the page numbers of a wide view.
func _update_backdrop(camera: Camera, pose: ArenaRules.Pose, _now: float) -> void:
	var t: Dictionary = transform_of(pose)
	var factor: float = t["scale"]
	var origin: Vector2 = t["origin"]
	var gap: float = 1.0 if pose.s > 1.5 else 0.0
	var cells: Array[Rect2] = []
	for page in camera.pages:
		for slot in 4:
			var letter: String = ArenaRules.name_of(page * 4 + slot)
			if camera.letters.has(letter):
				continue
			var rect: Rect2 = screen_rect(letter, pose)
			var x0: float = floorf(rect.position.x + 0.5)
			var y0: float = floorf(rect.position.y + 0.5)
			var x1: float = floorf(rect.end.x + 0.5)
			var y1: float = floorf(rect.end.y + 0.5)
			if x1 <= 0.0 or x0 >= ROOM_WIDTH or y1 <= 0.0 or y0 >= ROOM_HEIGHT:
				continue
			cells.append(Rect2(x0 + gap, y0 + gap, x1 - x0 - 2.0 * gap, y1 - y0 - 2.0 * gap))
	backdrop.set_cells(cells)
	var labels: Array[Dictionary] = []
	var alpha: float = 0.0
	if pose.s > PAGE_NUMBERS_FROM:
		alpha = minf(1.0, (pose.s - PAGE_NUMBERS_FROM) / PAGE_NUMBERS_RAMP)
		var gutter: float = float(ArenaRules.DEFAULTS["gutter"])
		var shown_page: int = camera.page_shown()
		for page in camera.pages:
			var cx: float = origin.x + (float(page) * (2.0 + gutter) + 1.0) * ROOM_WIDTH * factor
			var y: float = origin.y + 2.0 * ROOM_HEIGHT * factor + 5.0
			if cx < -20.0 or cx > 500.0:
				continue
			labels.append({ "text": str(page + 1), "x": cx, "y": floorf(y + 0.5), "gold": page == shown_page })
	overlay.set_labels(labels, alpha)
