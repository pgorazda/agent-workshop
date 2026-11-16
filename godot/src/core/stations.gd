extends RefCounted
## The station table: nine stations, one for each tool category of the schema.
##
## A station is chosen by `category` only, never by tool name (CLAUDE.md, rule 2). A category that is not in the
## table gives the station "other", as an unknown category does in `event.gd`.
##
## Where a penguin stands is a pixel point in the room picture (480x232 pixels). The points are the `PTS` of the
## JavaScript mockup (removed, see the git history) and they are the reference for the look. The station table of the client plan
## gives the same places in metres. `project()` turns metres into room pixels, and a test shows how far it is from the
## pixel points. The points win: no code derives a stand point from the metres. See `godot/README.md`, "Phase G-3".
##
## No nodes and no drawing here. `spots.gd` uses this table to give out spots and queue places.

## The size of the room picture in pixels. The bar of the interface lies below it, in the 480x270 viewport.
const ROOM_SIZE := Vector2i(480, 232)

## Floor position (x to the right, z to the back wall, in metres) to room pixels, as the 2D view plan says:
## screen x = 240 + 28 * x, screen y = 138 - 11 * z.
const PROJECTION_ORIGIN := Vector2(240.0, 138.0)
const PROJECTION_SCALE := Vector2(28.0, 11.0)

## The stand points, in room pixels. The names and values are those of `PTS` of the JavaScript mockup (removed). A test keeps them.
## `door` and `out` are the way out of the room. `helperPop` is where a helper appears. `rug` and `stage` are in
## the open floor: `stage` is where a penguin celebrates.
const POINTS: Dictionary = {
	"map": Vector2i(96, 86),
	"shelf": Vector2i(66, 126),
	"benchL": Vector2i(222, 98),
	"benchR": Vector2i(258, 98),
	"forge": Vector2i(366, 93),
	"forge2": Vector2i(398, 114),
	"chairFront": Vector2i(90, 222),
	"seat": Vector2i(90, 201),
	"desk": Vector2i(350, 208),
	"sign": Vector2i(236, 216),
	"signQ": Vector2i(204, 219),
	"scope": Vector2i(422, 158),
	"helperPop": Vector2i(434, 214),
	"forgeQ": Vector2i(336, 100),
	"spotA": Vector2i(332, 152),
	"spotB": Vector2i(446, 198),
	"rug": Vector2i(240, 150),
	"stage": Vector2i(344, 168),
	"door": Vector2i(323, 222),
	"out": Vector2i(323, 280),
	"odd": Vector2i(74, 160),
}

## Waiting places that the mockup does not have. It has a queue only at the forge (`forgeQ`) and at the sign post
## (`signQ`). These seven are a choice of phase G-3: each lies on free floor beside its station. A later phase
## may move them. `CHOSEN_POINTS` lists their names, so that the README and the tests can say which they are.
const QUEUE_POINTS: Dictionary = {
	"readQ": Vector2i(98, 128),
	"mapQ": Vector2i(126, 100),
	"benchQ": Vector2i(190, 100),
	"scopeQ": Vector2i(396, 166),
	"deskQ": Vector2i(318, 212),
	"thinkQ": Vector2i(140, 224),
	"oddQ": Vector2i(108, 166),
}
const CHOSEN_POINTS: Array[String] = ["readQ", "mapQ", "benchQ", "scopeQ", "deskQ", "thinkQ", "oddQ"]

## The distance between two neighbours in a queue, in pixels. The second penguin waits this far from the first one.
const QUEUE_STEP := 16

## The stations, in the order of the schema's categories. Each entry:
##   "category"  the schema category
##   "name"      the name of the station for people
##   "prop"      the picture of its prop in the atlas
##   "spots"     the places where a penguin works, in the order in which they are given out. Each spot has
##               "at" (a name in POINTS), "anim" (a key of ANIMATIONS in atlas_data.gd), "frame" (the first frame of
##               the animation, 0 when missing) and "shadow" (the radius of the shadow minus one: 7 when missing,
##               0 for no shadow)
##   "queue"     where penguins wait when every spot is taken: "at" (a name in POINTS or QUEUE_POINTS) and
##               "step" (the offset of each next place in the line)
const TABLE: Array[Dictionary] = [
	{
		"category": "read", "name": "Bookshelf", "prop": "prop/shelf",
		"spots": [{"at": "shelf", "anim": "read"}],
		"queue": {"at": "readQ", "step": Vector2i(QUEUE_STEP, 0)},
	},
	{
		"category": "search", "name": "Map table", "prop": "prop/map-table",
		"spots": [{"at": "map", "anim": "search"}],
		"queue": {"at": "mapQ", "step": Vector2i(QUEUE_STEP, 0)},
	},
	{
		"category": "write", "name": "Workbench", "prop": "prop/workbench",
		"spots": [{"at": "benchL", "anim": "write"}, {"at": "benchR", "anim": "write", "frame": 1}],
		"queue": {"at": "benchQ", "step": Vector2i(-QUEUE_STEP, 0)},
	},
	{
		"category": "exec", "name": "Forge", "prop": "prop/forge",
		"spots": [{"at": "forge", "anim": "exec"}, {"at": "forge2", "anim": "build"}],
		"queue": {"at": "forgeQ", "step": Vector2i(-QUEUE_STEP, 0)},
	},
	{
		"category": "web", "name": "Telescope", "prop": "prop/telescope",
		"spots": [{"at": "scope", "anim": "web"}],
		"queue": {"at": "scopeQ", "step": Vector2i(-QUEUE_STEP, 0)},
	},
	{
		"category": "delegate", "name": "Helper desk", "prop": "prop/helper-desk",
		"spots": [{"at": "desk", "anim": "delegate"}],
		"queue": {"at": "deskQ", "step": Vector2i(-QUEUE_STEP, 0)},
	},
	{
		"category": "think", "name": "Thinking chair", "prop": "prop/chair-front",
		"spots": [
			{"at": "seat", "anim": "think", "shadow": 0},
			{"at": "spotA", "anim": "think"},
			{"at": "spotB", "anim": "think"},
		],
		"queue": {"at": "thinkQ", "step": Vector2i(QUEUE_STEP, 0)},
	},
	{
		"category": "ask_permission", "name": "Sign post", "prop": "prop/sign-post",
		"spots": [{"at": "sign", "anim": "wait"}],
		"queue": {"at": "signQ", "step": Vector2i(-QUEUE_STEP, 0)},
	},
	{
		"category": "other", "name": "Odd jobs", "prop": "prop/odd-jobs",
		"spots": [{"at": "odd", "anim": "other"}],
		"queue": {"at": "oddQ", "step": Vector2i(QUEUE_STEP, 0)},
	},
]

## The floor position of the station table of the client plan, in metres (x, z): where a penguin stands.
const FLOOR_METRES: Dictionary = {
	"read": Vector2(-7.0, 3.0),
	"search": Vector2(-4.0, 6.0),
	"write": Vector2(0.0, 7.0),
	"exec": Vector2(5.0, 5.0),
	"web": Vector2(7.0, 0.0),
	"delegate": Vector2(5.0, -5.0),
	"think": Vector2(-5.0, -5.0),
	"ask_permission": Vector2(0.0, -7.0),
	"other": Vector2(-7.0, -2.0),
}


## Floor position in metres (x, z) to a point in room pixels.
static func project(floor_metres: Vector2) -> Vector2:
	return Vector2(PROJECTION_ORIGIN.x + PROJECTION_SCALE.x * floor_metres.x, PROJECTION_ORIGIN.y - PROJECTION_SCALE.y * floor_metres.y)


## The station of a category. An unknown category gives the station "other".
static func for_category(category: String) -> Dictionary:
	for station in TABLE:
		if station["category"] == category:
			return station
	return TABLE[TABLE.size() - 1]


## The point of a name, in room pixels. The name is in POINTS or in QUEUE_POINTS.
static func point(point_name: String) -> Vector2i:
	if POINTS.has(point_name):
		return POINTS[point_name]
	return QUEUE_POINTS[point_name]


## The place of the `index`-th penguin in the line of a station (0 is the first one).
static func queue_place(station: Dictionary, index: int) -> Vector2i:
	var queue: Dictionary = station["queue"]
	var step: Vector2i = queue["step"]
	return point(queue["at"]) + step * index
