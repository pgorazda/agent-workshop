extends Node
## The room view of phase G-3: one arena with the baked room, its props and one penguin standing at each station.
##
## It shows pictures only. The penguins do not move, and no event changes anything: that is phase G-4. The art
## code draws everything (`art/room_stage_art.gd`). This file chooses who stands where, through the spot logic
## of `src/core/spots.gd`, and gives the result to the art node.
##
## Run it with: godot --path godot res://src/room.tscn
## The option `-- --rug=cobalt` sets the colour of the rug (red, cobalt, emerald, yellow, teal). `-- --arena=B` shows the
## sign of an arena with that letter. Without it the sign says AGENT WORKSHOP, as for one arena. `-- --no-penguins` shows the empty room.

const Stations := preload("res://src/core/stations.gd")
const Spots := preload("res://src/core/spots.gd")
const Atlas := preload("res://art/atlas.gd")
const RoomStageArt := preload("res://art/room_stage_art.gd")

## The colour behind the viewport where the room does not reach: the background of the log.
const BACKGROUND := Color("#1b2236")
## The framework whose cap cord every penguin of this view wears.
const CORD := "claude-code"

var stage: Node2D


func _ready() -> void:
	RenderingServer.set_default_clear_color(BACKGROUND)
	Atlas.load_all()
	stage = RoomStageArt.new()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rug="):
			stage.rug = arg.trim_prefix("--rug=")
		elif arg.begins_with("--arena="):
			stage.letter = arg.trim_prefix("--arena=")
	var crowd: Array[Dictionary] = []
	if not OS.get_cmdline_user_args().has("--no-penguins"):
		crowd = standing_penguins(CORD)
	stage.set_penguins(crowd)
	add_child(stage)


## One penguin at the first spot of each station, in the order of the schema's categories. Each entry is a penguin for
## `RoomStageArt` (see the top of that file). The spot logic gives the spot, and the animation of the spot gives the
## picture.
static func standing_penguins(cord: String) -> Array[Dictionary]:
	var spots: RefCounted = Spots.new()
	var crowd: Array[Dictionary] = []
	for station in Stations.TABLE:
		var placement: Dictionary = spots.arrive(station["category"], station["category"])
		var look: Dictionary = RoomStageArt.look_of(placement["anim"], placement["frame"])
		var point: Vector2i = placement["point"]
		crowd.append({
			"x": point.x, "y": point.y, "cord": cord,
			"dir": look["dir"], "pose": look["pose"], "flip": look["flip"],
			"shadow": placement["shadow"],
		})
	return crowd
