extends RefCounted
## Recording mode: the pure parts. `tools/record.mjs` starts the client with the engine's Movie Maker (`--write-movie`,
## `--fixed-fps`) and `--record-fps`. Godot calls `_process` once for each frame of the clip, and the view runs the simulation up to the
## time of that frame. Nothing here reads a clock, a window or a file.
##
## Frame `i` of a clip at `fps` frames a second shows the story at the time `i / fps`: the simulation has run `floor(i * 60 / fps)`
## steps of 1/60 s (`steps_at_frame`). So a clip at 30 fps and live play at 144 fps show the same story, and a clip at any rate shows the
## same moments (the frames of a rate that does not divide 60 show the last step before their time).
##
## The scripted pointer, the key caps and the open windows of the follow menu come from the scene file (see `net/timeline_player.gd`).

const Clock := preload("res://src/core/clock.gd")
const ArenaRules := preload("res://src/core/arena_rules.gd")

## The kinds of segment in which a penguin stands on a spot of its own (the mockup's `OCCUPYING`). A penguin that thinks where it stands
## is left out: it holds no spot.
const OCCUPYING: Array[String] = ["work", "wait", "sit", "think", "flop", "approve", "cheer", "queue"]
## Two penguins closer than this (pixels) on one spot count as sharing it.
const SHARE_DISTANCE := 1.5
## Where the hover point is when no pointer is on screen.
const NO_POINT := Vector2(-100.0, -100.0)


## The number of frames of a clip: `ceil(duration * fps)`, as the mockup's recorder counts.
static func frame_count(duration: float, fps: int) -> int:
	return maxi(1, int(ceilf(duration * float(fps) - 1e-9)))


## The time of frame `frame` in seconds.
static func time_of_frame(frame: int, fps: int) -> float:
	return float(frame) / float(fps)


## The number of simulation steps that have run when the scene time is `t`.
static func steps_at_time(t: float) -> int:
	return int(floorf(t * (1.0 / Clock.STEP) + 1e-9))


## The steps that have run when frame `frame` is drawn.
static func steps_at_frame(frame: int, fps: int) -> int:
	return int(floorf(float(frame) * (1.0 / Clock.STEP) / float(fps) + 1e-9))


# ---------------------------------------------------------------- the scripted pointer, keys and menu

## The place of a pointer on a path `[[t, x, y], ...]` at the time `t` (`cursorAt` of the JavaScript mockup), or null before the first point and after the
## last. The pointer eases from point to point (smoothstep) and its place is rounded like `Math.round`.
static func cursor_at(t: float, path: Array) -> Variant:
	if path.size() < 2:
		return null
	var first: Array = path[0]
	var last: Array = path[path.size() - 1]
	if t < float(first[0]) or t > float(last[0]):
		return null
	var i: int = 0
	while i < path.size() - 2 and t > float((path[i + 1] as Array)[0]):
		i += 1
	var a: Array = path[i]
	var b: Array = path[i + 1]
	var k: float = minf(1.0, (t - float(a[0])) / (float(b[0]) - float(a[0])))
	var e: float = ArenaRules.ease_k(k)
	return Vector2i(int(ArenaRules.js_round(float(a[1]) + (float(b[1]) - float(a[1])) * e)), int(ArenaRules.js_round(float(a[2]) + (float(b[2]) - float(a[2])) * e)))


## The pointers on screen at `t`: [{ "x", "y", "ring_ages": [seconds since each click] }]. `paths` is the list of the scene file.
static func pointers_at(t: float, paths: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Variant in paths:
		var entry: Dictionary = item as Dictionary
		var place: Variant = cursor_at(t, entry["path"])
		if place == null:
			continue
		var ages: Array = []
		for click: Variant in entry.get("clicks", []):
			ages.append(t - float(click))
		out.append({ "x": (place as Vector2i).x, "y": (place as Vector2i).y, "ring_ages": ages })
	return out


## The point that the first pointer on screen has, for the hover of the interface (a hover over a tab or a cell shows that arena's
## cards). `NO_POINT` when no pointer is on screen.
static func hover_point_at(t: float, paths: Array) -> Vector2:
	for item: Variant in paths:
		var place: Variant = cursor_at(t, (item as Dictionary)["path"])
		if place != null:
			return Vector2(place as Vector2i)
	return NO_POINT


## The key caps that show at `t`: [{ "label", "age" }] for a key pressed up to 1.1 s ago.
static func key_caps_at(t: float, keys: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Variant in keys:
		var age: float = t - float((item as Dictionary)["t"])
		if age >= 0.0 and age <= 1.1:
			out.append({ "label": str((item as Dictionary)["label"]), "age": age })
	return out


## True while the follow menu is open in the script of the scene.
static func menu_open_at(t: float, menus: Array) -> bool:
	for item: Variant in menus:
		var entry: Dictionary = item as Dictionary
		if t >= float(entry["open"]) and t < float(entry["close"]):
			return true
	return false


# ---------------------------------------------------------------- the check of the spots

## The penguins that stand on one spot at the same time, in all arenas: a list of sentences, empty when there is none. The mockup checks
## its hand-written scripts for this (`slotConflicts`). The client picks the spots itself, so this checks the result: two penguins of
## one arena that stand at the same place while both hold a spot or a place in a line.
static func spot_conflicts(director: RefCounted, t: float) -> Array[String]:
	var found: Array[String] = []
	for letter: String in director.letters():
		var standing: Array[RefCounted] = []
		for actor: RefCounted in director.actors_in(letter):
			if actor.hidden or actor.think_in_place:
				continue
			if OCCUPYING.has(str(actor.current_segment().get("kind", ""))):
				standing.append(actor)
		for i in standing.size():
			for j in range(i + 1, standing.size()):
				var a: RefCounted = standing[i]
				var b: RefCounted = standing[j]
				if (a.position as Vector2).distance_to(b.position as Vector2) < SHARE_DISTANCE:
					found.append("t=%.2f arena %s: %s and %s stand on one spot at (%d, %d)" % [t, letter, a.key, b.key, int(a.position.x), int(a.position.y)])
	return found
