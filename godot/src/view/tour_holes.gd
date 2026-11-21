extends RefCounted
## Works out what stays lit in a stop of the tour. The scene file says what to light (`core/tour.gd` lists the kinds of hole).
## The mockup knew the places because it scripted its penguins. The client has live penguins, so this reads their places from the director
## and the places of the cards from the interface, at the moment that the stop begins. The scene stands still during a stop, so the places
## do not change until it ends.

const Ui := preload("res://art/ui_kit.gd")
const TextArt := preload("res://art/text_art.gd")
const DrawKit := preload("res://art/draw_kit.gd")


## The holes of a stop as `{ rect: [x, y, w, h] }` and `{ ell: [cx, cy, rx, ry] }` for `art/tour_art.gd`. `ui` is the last result of
## `InterfaceModel.build`. A hole that has nothing to light (an agent that is not there) gives nothing.
static func resolve(stop: Dictionary, director: RefCounted, camera: RefCounted, ui: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var focus_number: Variant = camera.focus_of(camera.arena_shown())
	for item: Variant in stop.get("holes", []):
		var hole: Dictionary = item as Dictionary
		if hole.has("agent"):
			out.append_array(_agent(director, _number(hole["agent"], focus_number), focus_number))
		elif hole.has("card"):
			var rect: Variant = card_rect(ui, _number(hole["card"], focus_number))
			if rect != null:
				out.append({ "rect": rect })
		elif hole.has("helper"):
			var helper: Variant = _helper_of(director, _number(hole["helper"], focus_number))
			if helper != null:
				out.append({ "ell": [DrawKit.rnd((helper as RefCounted).position.x), DrawKit.rnd((helper as RefCounted).position.y - 15.0), 11, 18] })
		elif hole.has("near"):
			var actor: RefCounted = director.penguin_with_number(_number(hole["near"], focus_number))
			if actor != null and not actor.hidden:
				var e: Array = hole["ell"]
				out.append({ "ell": [DrawKit.rnd(actor.position.x) + int(e[0]), DrawKit.rnd(actor.position.y) + int(e[1]), int(e[2]), int(e[3])] })
		elif hole.has("rect") or hole.has("ell"):
			out.append(hole)
	return out


## An agent number of a hole: a number, or "focus" for the agent that has the focus (0 when none has).
static func _number(value: Variant, focus_number: Variant) -> int:
	if typeof(value) == TYPE_STRING and str(value) == "focus":
		return int(focus_number) if focus_number != null else 0
	return int(value)


## The rectangle of the card of agent `n` in the cards that the interface shows, or null.
static func card_rect(ui: Dictionary, n: int) -> Variant:
	var cards: Dictionary = ui.get("cards", { })
	for item: Dictionary in cards.get("items", []):
		if int((item["card"] as Dictionary)["number"]) == n:
			var r: Rect2i = item["rect"]
			return [r.position.x, r.position.y, r.size.x, r.size.y]
	return null


static func _helper_of(director: RefCounted, parent_number: int) -> Variant:
	var parent: RefCounted = director.penguin_with_number(parent_number)
	if parent == null:
		return null
	for helper: RefCounted in director.helpers():
		if helper.parent_key == parent.key and not helper.hidden:
			return helper
	return null


## A penguin, and above it its focus label (if it has the focus) or its number chip, placed as the room draws them
## (`room_stage_art.gd`): an ellipse round the body, one more when it lies flopped, and the box of the label or the chip.
static func _agent(director: RefCounted, n: int, focus_number: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var actor: RefCounted = director.penguin_with_number(n)
	if actor == null or actor.hidden:
		return out
	var x: int = DrawKit.rnd(actor.position.x)
	var y: int = DrawKit.rnd(actor.position.y)
	var activity: String = str(actor.activity)
	var flopping: bool = actor.flop_age >= 0.0
	var top: float = actor.position.y - 50.0 + float(actor.y_off) if activity == "cheer" else actor.position.y - 50.0
	out.append({ "ell": [x, y - 21, 15, 25] })
	if flopping:
		out.append({ "ell": [x - 16, y - 6, 30, 14] })
	var chip_w: int = Ui.chip_width(n)
	if focus_number != null and n == int(focus_number) and not ["wait", "approve", "cheer"].has(activity):
		var label: Dictionary = director.activity_log.focus_label(str(actor.key))
		var text: String = TextArt.fit(TextArt.TINY5, str(label["text"]), 150)
		var lx: float = actor.position.x + 6.0 if flopping else actor.position.x
		var ly: float = actor.position.y - 33.0 if flopping else top + 9.0
		var w: int = chip_w + TextArt.rich_width(TextArt.TINY5, text) + 10
		var bx: int = maxi(8, mini(472 - w, DrawKit.rnd(lx - float(w) / 2.0)))
		out.append({ "rect": [bx - 1, DrawKit.rnd(ly) - 14, w + 2, 18] })
	else:
		var chip_top: float = actor.position.y - 30.0 if flopping else top
		out.append({ "rect": [x - ceili(float(chip_w) / 2.0) - 1, DrawKit.rnd(chip_top) - 1, chip_w + 2, 11] })
	return out
