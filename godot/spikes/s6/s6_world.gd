extends Node2D
## Spike S-6: N rooms in a grid, shown in one of two ways, at a scale that the caller changes.
##
## Way A, "A-always" and "A-visible": each room is a SubViewport of 480x232. A sprite shows its texture with linear
##   filtering. The two names differ in the update mode of the SubViewport (always, or only when it is visible).
## Way B: one shared world. Each room is the baked room picture plus separate sprites. The names tell the filter:
##   "B-mips": the room texture has mipmaps and uses trilinear filtering. The sprite sheets use linear filtering.
##   "B-linear": linear filtering for everything, no mipmaps.
##   "B-nearest": nearest filtering for everything (the plain way, shown for the cost and as a picture of the problem).
##   "B-allmips": mipmaps and trilinear filtering for the room and for the sprite sheets.
## The scale is the scale of this node. All rooms are children of it, so scaling it is the camera.

const Room := preload("res://spikes/s6/s6_room.gd")
const Stats := preload("res://spikes/s6/s6_stats.gd")

const METHODS: Array[String] = ["A-always", "A-visible", "B-mips", "B-linear", "B-nearest", "B-allmips"]
const ROOM_SIZE := Vector2(480, 232)
const GUTTER := 16.0
const VIEW := Vector2(480, 270)

var method: String = "B-nearest"
var count: int = 1
var columns: int = 1
var rows: int = 1
var _rooms: Array[Node2D] = []
var _viewports: Array[SubViewport] = []


## Builds `n` rooms in the way `way`.
func build(way: String, n: int) -> void:
	method = way
	count = n
	columns = Stats.grid_columns(n)
	rows = ceili(float(n) / float(columns))
	for i in n:
		var origin: Vector2 = Vector2(float(i % columns) * (ROOM_SIZE.x + GUTTER), float(floori(float(i) / float(columns))) * (ROOM_SIZE.y + GUTTER))
		var letter: String = "" if n == 1 else String.chr(65 + i % 26)
		var room: Node2D = Room.new()
		if way.begins_with("A-"):
			var viewport: SubViewport = SubViewport.new()
			viewport.size = Vector2i(ROOM_SIZE)
			viewport.disable_3d = true
			viewport.transparent_bg = false
			viewport.gui_disable_input = true
			viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if way == "A-always" else SubViewport.UPDATE_WHEN_VISIBLE
			add_child(viewport)
			room.setup(i, letter, CanvasItem.TEXTURE_FILTER_NEAREST, CanvasItem.TEXTURE_FILTER_NEAREST, false, false)
			viewport.add_child(room)
			var shown: Sprite2D = Sprite2D.new()
			shown.centered = false
			shown.texture = viewport.get_texture()
			shown.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			shown.position = origin
			add_child(shown)
			_viewports.append(viewport)
		else:
			var room_filter: CanvasItem.TextureFilter = CanvasItem.TEXTURE_FILTER_NEAREST
			var actor_filter: CanvasItem.TextureFilter = CanvasItem.TEXTURE_FILTER_NEAREST
			var room_mips: bool = false
			var sheet_mips: bool = false
			match way:
				"B-mips":
					room_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
					actor_filter = CanvasItem.TEXTURE_FILTER_LINEAR
					room_mips = true
				"B-linear":
					room_filter = CanvasItem.TEXTURE_FILTER_LINEAR
					actor_filter = CanvasItem.TEXTURE_FILTER_LINEAR
				"B-allmips":
					room_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
					actor_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
					room_mips = true
					sheet_mips = true
			room.setup(i, letter, room_filter, actor_filter, room_mips, sheet_mips)
			room.position = origin
			add_child(room)
		_rooms.append(room)


## The size of the whole grid in world pixels.
func grid_size() -> Vector2:
	return Vector2(float(columns) * ROOM_SIZE.x + float(columns - 1) * GUTTER, float(rows) * ROOM_SIZE.y + float(rows - 1) * GUTTER)


## The scale at which the whole grid fits in the view (never above 1).
func fit_scale() -> float:
	return Stats.fit_scale(count, ROOM_SIZE, GUTTER, VIEW)


## Sets the scale. The grid is centred in the view, unless `anchor` (the top left corner of the grid on screen) is
## given. The position is rounded to whole pixels.
func set_view_scale(s: float, anchor: Variant = null) -> void:
	scale = Vector2(s, s)
	if anchor == null:
		var top_left: Vector2 = VIEW / 2.0 - grid_size() * s / 2.0
		position = Vector2(floorf(top_left.x + 0.5), floorf(top_left.y + 0.5))
	else:
		position = anchor as Vector2


## How many rooms touch the view at the current scale and position.
func visible_rooms() -> int:
	var seen: int = 0
	for i in count:
		var origin: Vector2 = position + Vector2(float(i % columns) * (ROOM_SIZE.x + GUTTER), float(floori(float(i) / float(columns))) * (ROOM_SIZE.y + GUTTER)) * scale.x
		var box: Rect2 = Rect2(origin, ROOM_SIZE * scale.x)
		if box.intersects(Rect2(Vector2.ZERO, VIEW)):
			seen += 1
	return seen


## Advances all rooms.
func tick(delta: float) -> void:
	for room in _rooms:
		room.tick(delta)
