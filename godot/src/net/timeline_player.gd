extends RefCounted
## Demo mode: plays a timeline file instead of reading the bridge (docs/demo-mode-plan.md).
##
## A timeline holds a list of `{t, event}` and the inputs of a person (`{t, key}` or `{t, click}`). The player hands each
## item on once the simulation clock has reached its time. It has no clock of its own: pause and speed belong to
## `core/clock.gd`, so a demo runs on the same clock as everything else, and a recording can drive it with fixed steps.
## Both sources (the bridge and a timeline) give canonical schema v1 events to the director.
##
## The file format (JSON):
##   { "title": "...", "duration": 30.5,
##     "options": { "arena_size": 12 },
##     "events": [ { "t": 3.4, "event": { "v": 1, "framework": "...", ... } } ],
##     "inputs": [ { "t": 22.6, "key": "F" }, { "t": 23.4, "click": { "number": 4 } } ] }
## `options` is optional: the settings that the scene needs (`arena_size`, `follow`, `pace`, and `bar`: "cards" shows the top line and the
## cards also for one agent). An event may have a time below 0:
## the agents that were there before the scene starts. The clock starts at the first of them (see `start_time`).
## An input is `{t, key}` (F, Tab, Esc, Left, Right, N), `{t, click: {number}}` (a penguin), `{t, click: "tab"|"cell", arena}`,
## `{t, click: "page", page}`, `{t, toggle: kind}`, `{t, manual: true}` or `{t, pace: n}` (the follow menu).
## `events` must be in time order. An item that is not a valid event is skipped and counted in `rejected`.
## Phase G-8 adds what the mockup draws for the scripted demonstrations of a person. They carry no events and are drawn only in recording
## mode and in demo mode: `paths` (`[{ path: [[t, x, y], ...], clicks: [t, ...] }]`, the mouse pointer), `keys` (`[{ t, label }]`, the
## key caps) and `menus` (`[{ open, close }]`, the windows of time in which the follow menu is open). The scene `tour` also has `tour`
## (`{ scene_end, stops: [...] }`, see `core/tour.gd`).
## The files are in `res://demo/`. They are made up: no real repository, prompt or output.

const Event := preload("res://src/core/event.gd")

## The folder of the scene files.
const SCENE_FOLDER := "res://demo"

var title: String = ""
## The length of the story in seconds. It is the time of the last event or input, or more when the file says so.
var duration: float = 0.0
## [{"t": float, "event": Event}], in time order.
var events: Array[Dictionary] = []
## [{"t": float, ...}]: the dictionaries of the file, with "t" as a float.
var inputs: Array[Dictionary] = []
## The number of items of the file that were not valid events.
var rejected: int = 0
## The file that it was read from, or "".
var source: String = ""
## The settings of the scene (see the top of the file). Empty when the file has none.
var options: Dictionary = { }
## The scripted pointer, key caps and open windows of the follow menu (see the top of the file). Empty when the file has none.
var paths: Array[Dictionary] = []
var keys: Array[Dictionary] = []
var menus: Array[Dictionary] = []
## The tour of the scene `tour` (see `core/tour.gd`), or an empty Dictionary.
var tour: Dictionary = { }

var _next_event: int = 0
var _next_input: int = 0


## Reads a timeline file. Returns `null` when the file is missing or is not a timeline.
static func load_file(path: String) -> RefCounted:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var data: Variant = Event.decode(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var player: RefCounted = from_dictionary(data as Dictionary)
	if player != null:
		player.source = path
	return player


## Builds a player from a decoded file. Returns `null` when "events" is not a list.
static func from_dictionary(data: Dictionary) -> RefCounted:
	if typeof(data.get("events")) != TYPE_ARRAY:
		return null
	var player: RefCounted = new()
	player.title = str(data.get("title", ""))
	if typeof(data.get("options")) == TYPE_DICTIONARY:
		player.options = (data["options"] as Dictionary).duplicate()
	var last: float = 0.0
	for item: Variant in data["events"]:
		if typeof(item) != TYPE_DICTIONARY or typeof((item as Dictionary).get("event")) != TYPE_DICTIONARY:
			player.rejected += 1
			continue
		var event: RefCounted = Event.from_dictionary((item as Dictionary)["event"])
		if event == null:
			player.rejected += 1
			continue
		var t: float = float((item as Dictionary).get("t", 0.0))
		player.events.append({"t": t, "event": event})
		last = maxf(last, t)
	if typeof(data.get("inputs")) == TYPE_ARRAY:
		for item: Variant in data["inputs"]:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = (item as Dictionary).duplicate()
			entry["t"] = float(entry.get("t", 0.0))
			player.inputs.append(entry)
			last = maxf(last, float(entry["t"]))
	player.duration = maxf(float(data.get("duration", 0.0)), last)
	for item: Variant in _list(data.get("paths")):
		if typeof(item) == TYPE_DICTIONARY and typeof((item as Dictionary).get("path")) == TYPE_ARRAY and not ((item as Dictionary)["path"] as Array).is_empty():
			player.paths.append(item as Dictionary)
	for item: Variant in _list(data.get("keys")):
		if typeof(item) == TYPE_DICTIONARY:
			player.keys.append(item as Dictionary)
	for item: Variant in _list(data.get("menus")):
		if typeof(item) == TYPE_DICTIONARY:
			player.menus.append(item as Dictionary)
	if typeof(data.get("tour")) == TYPE_DICTIONARY:
		player.tour = data["tour"] as Dictionary
	return player


static func _list(value: Variant) -> Array:
	return value as Array if typeof(value) == TYPE_ARRAY else []


## The scene files: [{"name", "path", "title"}], sorted by name. `name` is the file name without ".json".
static func scenes(folder: String = SCENE_FOLDER) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(folder):
		return list
	var names: PackedStringArray = DirAccess.get_files_at(folder)
	var sorted_names: Array = Array(names)
	sorted_names.sort()
	for file_name: String in sorted_names:
		if not file_name.ends_with(".json"):
			continue
		var path: String = folder.path_join(file_name)
		var player: RefCounted = load_file(path)
		if player == null:
			continue
		list.append({"name": file_name.trim_suffix(".json"), "path": path, "title": player.title})
	return list


## The time at which the clock starts: 0, or the time of the first event when it is below 0.
func start_time() -> float:
	if events.is_empty():
		return 0.0
	return minf(0.0, float(events[0]["t"]))


## The events whose time the clock has reached, once each, in order.
func due_events(now: float) -> Array[RefCounted]:
	var due: Array[RefCounted] = []
	while _next_event < events.size() and float(events[_next_event]["t"]) <= now + 1e-9:
		due.append(events[_next_event]["event"])
		_next_event += 1
	return due


## The inputs whose time the clock has reached, once each, in order.
func due_inputs(now: float) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	while _next_input < inputs.size() and float(inputs[_next_input]["t"]) <= now + 1e-9:
		due.append(inputs[_next_input])
		_next_input += 1
	return due


## True when every event and input was handed on and the time of the story is over.
func finished(now: float) -> bool:
	return _next_event >= events.size() and _next_input >= inputs.size() and now >= duration


## Starts again from the first item. The caller resets the clock and the director.
func rewind() -> void:
	_next_event = 0
	_next_input = 0
