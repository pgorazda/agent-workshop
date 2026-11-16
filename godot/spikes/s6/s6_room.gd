extends Node2D
## Spike S-6: one room with its content, made of sprites only. The room picture and the sign come from art/.
## The room has: the baked room and its sign, the 12 props, four penguins that walk, two flames, four sparks and one
## icon bubble. Every frame changes some positions and some frame regions, as a real room would.
## The same script builds the room for both ways (a SubViewport per room, and the shared world).

const Atlas := preload("res://art/atlas.gd")
const Data := preload("res://art/atlas_data.gd")
const RoomArt := preload("res://art/room_art.gd")
const Support := preload("res://art/s6_support.gd")

const ROOM_SIZE := Vector2(480, 232)
const CORDS: Array[String] = ["claude-code", "opencode", "pi", "hermes"]
const ICONS: Array[String] = ["icon/read", "icon/search", "icon/write", "icon/exec"]
## The part of the room where penguins walk.
const WALK_X := Vector2(40, 440)
const WALK_Y := Vector2(110, 215)
const SPEED := 38.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _time: float = 0.0
var _sheet_mips: bool = false
var _penguins: Array[Dictionary] = []
var _flames: Array[Sprite2D] = []
var _sparks: Array[Dictionary] = []
var _icon: Sprite2D
var _actors: Node2D


## Builds the room. `index` decides the rug, the letter and the random numbers. `letter` is the sign letter ("" for
## the single room). `room_filter` and `actor_filter` are the texture filters of the room picture and of the sprites.
## `room_mips` draws the room from a copy of its texture with mipmaps. `sheet_mips` does the same for the sprite sheets.
func setup(index: int, letter: String, room_filter: CanvasItem.TextureFilter, actor_filter: CanvasItem.TextureFilter, room_mips: bool, sheet_mips: bool) -> void:
	_rng.seed = 1000 + index
	_sheet_mips = sheet_mips
	var room: Support = Support.new()
	room.rug = RoomArt.rug_of_arena(index)["name"]
	room.letter = letter
	room.use_mipmaps = room_mips
	room.texture_filter = room_filter
	add_child(room)
	_actors = Node2D.new()
	_actors.y_sort_enabled = true
	_actors.texture_filter = actor_filter
	add_child(_actors)
	for place in Data.PROP_PLACES:
		var sprite: Sprite2D = _make_sprite(place["name"], float(place["x"]), float(place["depth"]), float(place["by"]) - float(place["depth"]))
		_actors.add_child(sprite)
	for i in CORDS.size():
		_add_penguin(CORDS[i])
	for i in 2:
		var flame: Sprite2D = _make_sprite("flame/0", 388.0 + 14.0 * float(i), 90.0, -16.0)
		_actors.add_child(flame)
		_flames.append(flame)
	for i in 4:
		var spark: Sprite2D = _make_sprite("spark/1", 0.0, 0.0, 0.0)
		spark.visible = false
		_actors.add_child(spark)
		_sparks.append({"sprite": spark, "life": 0.0, "vy": 0.0})
	_icon = _make_sprite(ICONS[0], 0.0, 0.0, 0.0)
	_actors.add_child(_icon)


## Advances the room by `delta` seconds.
func tick(delta: float) -> void:
	_time += delta
	for state in _penguins:
		_tick_penguin(state, delta)
	var flame_frame: int = int(_time / 0.1) % 4
	for flame in _flames:
		_set_picture(flame, "flame/%d" % flame_frame, false)
	for state in _sparks:
		_tick_spark(state, delta)
	var first: Sprite2D = _penguins[0]["sprite"]
	_icon.position = first.position + Vector2(0, -52)
	_set_picture(_icon, ICONS[int(_time) % ICONS.size()], false)


func _make_sprite(picture: String, x: float, y: float, foot_shift: float) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.centered = false
	sprite.region_enabled = true
	sprite.texture = Support.sheet_texture(Atlas.sheet_of(picture), _sheet_mips)
	var size: Vector2i = Atlas.size_of(picture)
	sprite.offset = Vector2(-floorf(size.x / 2.0), -float(size.y) + foot_shift)
	sprite.region_rect = Rect2(Atlas.rect_of(picture))
	sprite.position = Vector2(x, y)
	return sprite


## Sets the picture of a sprite. The sprite keeps its sheet, so the new picture must be in the same sheet.
func _set_picture(sprite: Sprite2D, picture: String, flip: bool) -> void:
	var rect: Rect2i = Atlas.rect_of(picture)
	sprite.region_rect = Rect2(rect)
	sprite.flip_h = flip


func _add_penguin(cord: String) -> void:
	var sprite: Sprite2D = _make_sprite("penguin/%s/side/idle" % cord, 0.0, 0.0, 0.0)
	var start: Vector2 = Vector2(_rng.randf_range(WALK_X.x, WALK_X.y), _rng.randf_range(WALK_Y.x, WALK_Y.y))
	sprite.position = start
	_actors.add_child(sprite)
	_penguins.append({"sprite": sprite, "cord": cord, "target": start, "wait": _rng.randf_range(0.2, 1.5), "pos": start, "frame": ""})


func _tick_penguin(state: Dictionary, delta: float) -> void:
	var sprite: Sprite2D = state["sprite"]
	var pos: Vector2 = state["pos"]
	var target: Vector2 = state["target"]
	var cord: String = state["cord"]
	var pose: String
	var flip: bool = sprite.flip_h
	var to_target: Vector2 = target - pos
	if to_target.length() < 2.0:
		var wait: float = float(state["wait"]) - delta
		state["wait"] = wait
		pose = "idle"
		if wait <= 0.0:
			state["target"] = Vector2(_rng.randf_range(WALK_X.x, WALK_X.y), _rng.randf_range(WALK_Y.x, WALK_Y.y))
			state["wait"] = _rng.randf_range(0.2, 1.5)
	else:
		pos += to_target.normalized() * minf(SPEED * delta, to_target.length())
		state["pos"] = pos
		flip = to_target.x < 0.0
		pose = "walk" if int(_time / 0.13) % 2 == 0 else "walk2"
	# Whole pixels, as the real room draws them.
	sprite.position = Vector2(floorf(pos.x + 0.5), floorf(pos.y + 0.5))
	var picture: String = "penguin/%s/side/%s" % [cord, pose]
	if picture != state["frame"]:
		state["frame"] = picture
		_set_picture(sprite, picture, flip)
	elif sprite.flip_h != flip:
		sprite.flip_h = flip


func _tick_spark(state: Dictionary, delta: float) -> void:
	var sprite: Sprite2D = state["sprite"]
	var life: float = float(state["life"]) - delta
	if life <= 0.0:
		life = _rng.randf_range(0.25, 0.6)
		sprite.position = Vector2(_rng.randf_range(380.0, 420.0), _rng.randf_range(78.0, 90.0))
		state["vy"] = _rng.randf_range(-40.0, -15.0)
		_set_picture(sprite, "spark/%d" % _rng.randi_range(1, 3), false)
		sprite.visible = true
	else:
		sprite.position = Vector2(sprite.position.x, floorf(sprite.position.y + float(state["vy"]) * delta + 0.5))
	state["life"] = life
