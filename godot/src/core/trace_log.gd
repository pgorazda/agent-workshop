extends RefCounted
## The trace of what the penguins do: for each actor the labels of the stations that it visits, in order. The labels are the
## ones of `test/fixtures/expected-trace.json`, so that a run of the real client (`--trace`, see `src/view/live_view.gd`) and a unit test
## can be compared with the same file. The labels: the name of a station (`stations.gd`), "flop", "celebration", "thinking in place", and
## "queue at <station>". It reads actors and writes lines; it has no clock and no node.

const Stations := preload("res://src/core/stations.gd")

var _last: Dictionary = { }


## The label of what an actor does now, or "" when it is not at a station.
static func label_of(actor: RefCounted) -> String:
	match actor.activity:
		"work", "wait":
			if actor.station == "":
				return ""
			return str(Stations.for_category(actor.station)["name"])
		"sit":
			return str(Stations.for_category("think")["name"])
		"think":
			return "thinking in place"
		"flop":
			return "flop"
		"cheer":
			return "celebration"
		"queue":
			return "queue at %s" % str(Stations.for_category(actor.station)["name"])
	return ""


## The name of an actor in a trace: "agent 3" for a penguin and "helper 3" for the helper of penguin 3.
static func who_of(actor: RefCounted) -> String:
	return ("helper %d" if actor.is_helper else "agent %d") % actor.number


## The visits that began since the last call, as lines "<who>: <label>". Call it after each step of the director. A label counts once for as
## long as it lasts.
func changes(actors: Array[RefCounted]) -> Array[String]:
	var lines: Array[String] = []
	for actor in actors:
		var label: String = label_of(actor)
		if label != "" and str(_last.get(actor.key, "")) != label:
			lines.append("%s: %s" % [who_of(actor), label])
			_last[actor.key] = label
		elif label == "":
			_last[actor.key] = ""
	return lines
