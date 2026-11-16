extends RefCounted
## The tour (phase G-8, `tour.js` of the mockup): a quick introduction to one arena. One Claude Code agent visits every station, and each
## time an event arrives or the penguin reaches a station the scene stops for a moment while a callout says what it is. Then three more
## agents join, to show what changes when an arena has several agents.
##
## There are two clocks. The **scene clock** is the simulation clock of the client. The **clip clock** is the time of the clip. A stop
## stands still on the scene clock and lets the clip clock run: so a stop of 6 seconds makes the clip 6 seconds longer and the scene no
## older. This class holds the stops and maps the clip time to the scene time. It has no state of the play and no drawing: the view
## keeps the clip time, and `art/tour_art.gd` draws a stop.
##
## A stop is a Dictionary of the scene file (`demo/tour.json`):
##   { at, kind: "event"|"thing"|"title", title, lines, dur, holes, heading?, centred?, box?, point? }
## `at` is the scene time, `dur` the length in clip seconds, `lines` the words (a line that starts with a quote mark and a space quotes the
## event), `holes` what stays lit. A hole is `{ rect }` or `{ ell }` (fixed places in the room or the bar), `{ agent: n }` (a penguin, with
## its chip or its label), `{ card: n }`, `{ helper: n }` (the helper of agent n) or `{ near: n, ell }` (an ellipse placed relative to the
## penguin n). `n` may be "focus": the agent that has the focus. `view/tour_holes.gd` works the places out from the live scene.

## The scene time at which the story ends (a little after the last stop).
var scene_end: float = 0.0
## The stops in order of `at`. Stops at the same time keep their order.
var stops: Array[Dictionary] = []


## Builds a tour from the "tour" part of a scene file. Returns null when it has no stops.
static func from_dictionary(data: Dictionary) -> RefCounted:
	if typeof(data.get("stops")) != TYPE_ARRAY or (data["stops"] as Array).is_empty():
		return null
	var tour: RefCounted = new()
	tour.scene_end = float(data.get("scene_end", 0.0))
	for item: Variant in data["stops"]:
		if typeof(item) == TYPE_DICTIONARY:
			tour.stops.append(item as Dictionary)
	# a stable sort: the position is the tie-break
	var indexed: Array = []
	for i: int in tour.stops.size():
		indexed.append([tour.stops[i], i])
	indexed.sort_custom(func(a: Array, b: Array) -> bool:
		var ta: float = float((a[0] as Dictionary)["at"])
		var tb: float = float((b[0] as Dictionary)["at"])
		return ta < tb or (ta == tb and int(a[1]) < int(b[1])))
	tour.stops.clear()
	for pair: Array in indexed:
		tour.stops.append(pair[0] as Dictionary)
	return tour


## The length of the clip: the story plus every stop.
func clip_duration() -> float:
	var total: float = scene_end
	for stop in stops:
		total += float(stop["dur"])
	return total


## What the clip shows at the clip time `clip`: { "t": the scene time, "stop": the stop or an empty Dictionary, "age": seconds since the
## stop began, "index": the position of the stop (0-based, -1 when there is none) }.
func at(clip: float) -> Dictionary:
	var offset: float = 0.0
	for i in stops.size():
		var stop: Dictionary = stops[i]
		var begins: float = float(stop["at"]) + offset
		if clip < begins:
			return { "t": clip - offset, "stop": { }, "age": 0.0, "index": -1 }
		if clip < begins + float(stop["dur"]):
			return { "t": float(stop["at"]), "stop": stop, "age": clip - begins, "index": i }
		offset += float(stop["dur"])
	return { "t": minf(clip - offset, scene_end), "stop": { }, "age": 0.0, "index": -1 }


## The clip time at which the scene time `s` is shown: `s` plus the length of every stop that comes before it.
func scene_to_clip(s: float) -> float:
	var total: float = s
	for stop in stops:
		if float(stop["at"]) < s:
			total += float(stop["dur"])
	return total

