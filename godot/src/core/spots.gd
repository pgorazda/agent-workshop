extends RefCounted
## Spots and the queue of each station (docs/2d-view-plan.md, "Several agents", item 3).
##
## Most stations have one or more spots. A penguin that arrives takes the first free spot. When every spot is taken,
## it waits in the line of the station. When a penguin leaves, its spot is free, and the first one in the line takes it.
## A spot belongs to one penguin at a time.
##
## This is live logic with no nodes and no clock. The caller tells it who arrives and who leaves. The 2D view uses its
## own spots: the actor of a later phase still works at the station while the picture shows the penguin in the line.
##
## An agent is any value that can be a Dictionary key and compares with `==`: a number or a string. Do not mix
## the number 5 and the float 5.0.
##
## A placement is a Dictionary:
##   "agent"     the agent
##   "category"  the category of the station
##   "station"   the name of the station
##   "queued"    true when the agent waits in the line
##   "spot"      the index of its spot in the table, or -1 when it waits
##   "line"      its place in the line (0 is the first), or -1 when it has a spot
##   "at"        the name of its point
##   "point"     the point, in room pixels
##   "anim"      the animation key of a penguin at a spot, or "queue" in the line
##   "frame"     the first frame of the animation
##   "shadow"    the radius of the shadow minus one

const Stations := preload("res://src/core/stations.gd")

## The look of a penguin that waits in the line.
const QUEUE_ANIM := "queue"
const DEFAULT_SHADOW := 7

# category -> Array of agents (or null for a free spot), one for each spot of the station
var _spots: Dictionary = { }
# category -> Array of agents in line, the first one first
var _lines: Dictionary = { }
# agent -> category
var _where: Dictionary = { }


func _init() -> void:
	for station in Stations.TABLE:
		var spots: Array = []
		spots.resize((station["spots"] as Array).size())
		_spots[station["category"]] = spots
		_lines[station["category"]] = []


## An agent arrives at the station of a category. It takes the first free spot, or it joins the line. The result is
## its placement. An agent that is already at that station keeps its place. An agent that is at another station leaves
## it first: the placements that this changes there are not returned (call `leave` first to get them).
func arrive(agent: Variant, category: String) -> Dictionary:
	var station: Dictionary = Stations.for_category(category)
	var key: String = station["category"]
	if _where.has(agent):
		if _where[agent] == key:
			return placement_of(agent)
		leave(agent)
	_where[agent] = key
	var spots: Array = _spots[key]
	for i in spots.size():
		if spots[i] == null:
			spots[i] = agent
			return placement_of(agent)
	(_lines[key] as Array).append(agent)
	return placement_of(agent)


## An agent leaves the room, or leaves its station. Its spot is free, and the first one in the line takes it. The
## result is a list of the placements that changed: the agent that took the spot, then the agents in the line behind it,
## who each moved up one place. The list is empty when nothing else changes (also for an agent that is not here).
func leave(agent: Variant) -> Array[Dictionary]:
	var changed: Array[Dictionary] = []
	if not _where.has(agent):
		return changed
	var key: String = _where[agent]
	_where.erase(agent)
	var spots: Array = _spots[key]
	var line: Array = _lines[key]
	var line_index: int = line.find(agent)
	if line_index >= 0:
		line.remove_at(line_index)
		for i in range(line_index, line.size()):
			changed.append(placement_of(line[i]))
		return changed
	var freed: int = spots.find(agent)
	spots[freed] = null
	if line.is_empty():
		return changed
	var next: Variant = line.pop_front()
	spots[freed] = next
	changed.append(placement_of(next))
	for waiting: Variant in line:
		changed.append(placement_of(waiting))
	return changed


## True when the agent is at a station, at a spot or in a line.
func has(agent: Variant) -> bool:
	return _where.has(agent)


## The placement of an agent, or an empty Dictionary when it is not at a station.
func placement_of(agent: Variant) -> Dictionary:
	if not _where.has(agent):
		return { }
	var key: String = _where[agent]
	var station: Dictionary = Stations.for_category(key)
	var spot_index: int = (_spots[key] as Array).find(agent)
	if spot_index >= 0:
		var spot: Dictionary = (station["spots"] as Array)[spot_index]
		return {
			"agent": agent, "category": key, "station": station["name"], "queued": false,
			"spot": spot_index, "line": -1, "at": spot["at"], "point": Stations.point(spot["at"]),
			"anim": spot["anim"], "frame": int(spot.get("frame", 0)), "shadow": int(spot.get("shadow", DEFAULT_SHADOW)),
		}
	var line_index: int = (_lines[key] as Array).find(agent)
	return {
		"agent": agent, "category": key, "station": station["name"], "queued": true,
		"spot": -1, "line": line_index, "at": (station["queue"] as Dictionary)["at"],
		"point": Stations.queue_place(station, line_index),
		"anim": QUEUE_ANIM, "frame": 0, "shadow": DEFAULT_SHADOW,
	}


## The agent on a spot of a station, or `null` when the spot is free.
func holder(category: String, spot_index: int) -> Variant:
	return (_spots[Stations.for_category(category)["category"]] as Array)[spot_index]


## The agents in the line of a station, the first one first.
func line_of(category: String) -> Array:
	return (_lines[Stations.for_category(category)["category"]] as Array).duplicate()


## The number of free spots of a station.
func free_count(category: String) -> int:
	var count: int = 0
	for holder_of_spot: Variant in _spots[Stations.for_category(category)["category"]]:
		if holder_of_spot == null:
			count += 1
	return count


## True when no spot of the station is free.
func is_full(category: String) -> bool:
	return free_count(category) == 0
