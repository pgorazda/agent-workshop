# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# One room as the mockup draws it (`drawRoom` in crowd-art.js): the baked room with its sign, the glow of the forge
# and of the lamp, then the props and the penguins in the order of their depth (the y of the foot), with a shadow
# under each penguin. The frame code outside art/ gives the penguins as data and this node draws them.
#
# A penguin is a Dictionary:
#   "x", "y"      the stand point, in room pixels (the foot of the penguin)
#   "cord"        the framework of the cap cord: a key of CORDS in atlas_data.gd ("default" for an unknown one)
#   "dir"         "front", "side" or "back" (the left view is the right one with "flip")
#   "pose"        a pose name of the atlas: "idle", "hammer", "read", ...
#   "flip"        mirror the picture (optional, false when missing)
#   "blink"       eyes closed (optional, false when missing)
#   "y_off"       lift of the picture in pixels, negative is up (optional, 0 when missing)
#   "shadow"      the radius of the shadow minus one; 0 for no shadow (optional, 7 when missing)
#   "shadow_ry"   the height of the shadow (optional, 2.4 when missing)
#   "small"       the helper: the picture of a small penguin (optional, false when missing)
#   "flop"        the time in the flop in seconds (optional, -1 when the penguin is not flopping)
#   "think_age", "think_in_place", "number"   for the thought cloud (see effects_art.gd)
#   "focused"     this penguin has the focus: a ring on the floor and a label (optional, false when missing)
#   "activity"    what the actor does ("cheer", "queue", "wait", "approve", ...) and "age", the time in that segment (optional)
# The agents that wait for an approval are given as `notices` (see crowd_art.gd), and the label of the focused penguin as `focus_label`.
extends Node2D

const Atlas := preload("res://art/atlas.gd")
const DrawKit := preload("res://art/draw_kit.gd")
const RoomArt := preload("res://art/room_art.gd")
const EffectsArt := preload("res://art/effects_art.gd")
const RibbonArt := preload("res://art/ribbon_art.gd")
const CrowdArt := preload("res://art/crowd_art.gd")
const Ui := preload("res://art/ui_kit.gd")
const TextArt := preload("res://art/text_art.gd")
const Data := preload("res://art/atlas_data.gd")

const FIRE2 := Color("#ffc23d")
const ORANGE_DARK := Color("#a82a32")
## The mark on the sign post, drawn with the prop.
const SIGN_MARK: Array[String] = [".###.", "#...#", "....#", "..##.", "..#..", ".....", "..#.."]
const SIGN_MARK_POS := Vector2(264, 181)
const SIGN_POST := "prop/sign-post"
## A penguin picture is 48 pixels wide and its foot is 46 pixels below its top.
const PENGUIN_FOOT_X := 24
const PENGUIN_FOOT_Y := 46
const SHADOW_RY := 2.4
const SHADOW_ALPHA := 0.16
## The times of the flop in seconds: the shake, when the cap lands, and when the penguin gets up.
const FLOP_SHAKE := 0.12
const FLOP_CAP_LANDS := 0.55
const FLOP_LIE_END := 1.45

## The colour of the rug and the letter of the sign. An empty letter is the sign of the single room, "AGENT WORKSHOP".
var rug: String = "red"
var letter: String = ""
## The penguins to draw (see the top of the file). Set them with `set_penguins`.
var penguins: Array[Dictionary] = []
## The effect cues to draw (see src/core/effects.gd). Empty for a still picture.
var cues: Array[Dictionary] = []
## The time in seconds. It makes the glow of the forge flicker. Leave it at 0 for a still picture.
var time: float = 0.0
## True when the room is drawn small (a wide view of many rooms). The glow, the effects and the shadows are left out: they are
## too small to see and they cost many draw calls (one rectangle for each row of an ellipse).
var far: bool = false
## The agents that wait for an approval, the oldest first (see crowd_art.gd). Empty for none.
var notices: Array[Dictionary] = []
## The label of the focused penguin: { "text", "kind" } with a kind of "fail", "wait", "done" or "normal". Empty for none.
var focus_label: Dictionary = { }
## True when the room has one agent only (the one-arena log): its penguin has no number chip and no ring, and a plain tag says what it does.
var solo: bool = false
## The seconds since the camera first showed this arena: the ribbon of a new arena is drawn while it is 0 to 2.6. -1 for none.
var ribbon_age: float = -1.0


func set_penguins(list: Array[Dictionary]) -> void:
	penguins = list
	queue_redraw()


## The name of the picture of a penguin. `blink` has eyes closed (a pose with no baked blink picture is shown with open eyes). `small` is the helper: only a few poses are baked in
## that size, and any other pose shows the standing pose of the same direction. A pose that is not baked gives "" (check
## with `Atlas.has`).
static func penguin_picture(cord: String, dir: String, pose: String, blink: bool = false, small: bool = false) -> String:
	var cord_name: String = cord if Data.CORDS.has(cord) else "default"
	var picture: String = "penguin/%s/%s/%s" % [cord_name, dir, pose]
	if small:
		picture += "/small"
		if not Atlas.has(picture):
			picture = "penguin/%s/%s/idle/small" % [cord_name, dir]
	elif blink and Atlas.has(picture + "/blink"):
		picture += "/blink"
	return picture if Atlas.has(picture) else ""


## The look of a penguin that does an activity, from the animations of the atlas: {"dir", "pose", "flip"}. `frame` is
## the frame of the animation (it counts round). An unknown activity gives an idle penguin that faces front.
static func look_of(anim: String, frame: int = 0) -> Dictionary:
	if not Data.ANIMATIONS.has(anim):
		return {"dir": "front", "pose": "idle", "flip": false}
	var entry: Dictionary = Data.ANIMATIONS[anim]
	var poses: Array = entry["poses"]
	return {"dir": entry["dir"], "pose": poses[posmod(frame, poses.size())], "flip": entry["flip"]}


## What to draw, in drawing order: the props and the penguins sorted by depth. Equal depths keep the order in which
## they were added, props first (the mockup sorts the same way, and its sort is stable). An item is a Dictionary with
## "kind" ("prop" or "penguin"), "depth", "order" and the data of the thing (the prop place or the penguin).
static func build_items(places: Array[Dictionary], crowd: Array[Dictionary]) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for place in places:
		items.append({"kind": "prop", "depth": float(place["depth"]), "order": items.size(), "place": place})
	for penguin in crowd:
		items.append({"kind": "penguin", "depth": float(penguin["y"]), "order": items.size(), "penguin": penguin})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["depth"] != b["depth"]:
			return a["depth"] < b["depth"]
		return a["order"] < b["order"])
	return items


func _draw() -> void:
	RoomArt.draw_room(self, rug, letter)
	if not far:
		_draw_glow()
		EffectsArt.draw_under(self, cues, time)
	for item in build_items(Data.PROP_PLACES, penguins):
		if item["kind"] == "prop":
			_draw_prop(item["place"])
		else:
			_draw_penguin(item["penguin"])
	if not far:
		EffectsArt.draw_over(self, cues, time, penguins)
		_draw_crowd()
	if ribbon_age >= 0.0 and letter != "":
		RibbonArt.draw_arena_ribbon(self, letter, rug, ribbon_age)


# What the room shows of its agents, over the effects: the bubble of a penguin in a line, the approval notices, the number chips and
# the label of the focus, and the ribbon of a finished turn (`drawRoom` of crowd-art.js).
func _draw_crowd() -> void:
	if solo:
		_draw_solo()
		return
	for penguin in penguins:
		if str(penguin.get("activity", "")) == "queue" and float(penguin.get("age", 0.0)) > 0.2 and not bool(penguin.get("small", false)):
			CrowdArt.queue_bubble(self, float(penguin["x"]), float(penguin["y"]), time)
	CrowdArt.notices(self, notices, time)
	for penguin in penguins:
		var number: int = int(penguin.get("number", 0))
		if number <= 0:
			continue
		var x: float = float(penguin["x"])
		var y: float = float(penguin["y"])
		var y_off: float = float(penguin.get("y_off", 0))
		var cord: Color = Ui.cord_color(str(penguin["cord"]))
		if bool(penguin.get("small", false)):
			CrowdArt.number_chip(self, number, cord, x, y - 41.0 + y_off, 8)
			continue
		var activity: String = str(penguin.get("activity", ""))
		var flopping: bool = float(penguin.get("flop", -1.0)) >= 0.0
		var top: float = y - 50.0 + y_off if activity == "cheer" else y - 50.0
		if bool(penguin.get("focused", false)) and not ["wait", "approve", "cheer"].has(activity) and not focus_label.is_empty():
			var text: String = TextArt.fit(TextArt.TINY5, str(focus_label["text"]), 150)
			var color: Color = Color("#e03a3a") if str(focus_label["kind"]) == "fail" else Ui.INK
			CrowdArt.focus_tag(self, number, cord, text, color, x + 6.0 if flopping else x, y - 33.0 if flopping else top + 9.0)
		else:
			CrowdArt.number_chip(self, number, cord, x, y - 30.0 if flopping else top)
	for penguin in penguins:
		if str(penguin.get("activity", "")) == "cheer" and not bool(penguin.get("small", false)) and int(penguin.get("number", 0)) > 0:
			CrowdArt.turn_ribbon(self, int(penguin["number"]), Ui.cord_color(str(penguin["cord"])), float(penguin["x"]), float(penguin.get("age", 0.0)))


# The one penguin of a room with a single agent: a tag with what it does while it works, and the red tag of a failure.
func _draw_solo() -> void:
	if focus_label.is_empty():
		return
	for penguin in penguins:
		if bool(penguin.get("small", false)):
			continue
		var x: float = float(penguin["x"])
		var y: float = float(penguin["y"])
		var text: String = TextArt.fit(TextArt.TINY5, str(focus_label["text"]), 200)
		if float(penguin.get("flop", -1.0)) >= 0.12 and str(focus_label["kind"]) == "fail":
			CrowdArt.solo_tag(self, text, Color("#e03a3a"), x + 6.0, y - 33.0)
		elif str(penguin.get("activity", "")) == "work" and str(focus_label["kind"]) == "normal":
			CrowdArt.solo_tag(self, text, Ui.INK, x, y - 44.0)


# The glow of the forge and of the lamp: ellipses of the fire colour, drawn over the room.
func _draw_glow() -> void:
	var forge_alpha: float = 0.05 + 0.015 * sin(time * 9.0)
	DrawKit.ellipse(self, 396, 92, 54, 20, FIRE2, forge_alpha)
	DrawKit.ellipse(self, 396, 92, 36, 13, FIRE2, 0.05)
	DrawKit.ellipse(self, 396, 92, 18, 7, FIRE2, 0.05)
	DrawKit.ellipse(self, 124, 168, 30, 22, FIRE2, 0.06)
	DrawKit.ellipse(self, 124, 168, 20, 15, FIRE2, 0.06)


func _draw_prop(place: Dictionary) -> void:
	Atlas.draw_at(self, place["name"], float(place["x"]), float(place["by"]))
	if place["name"] == SIGN_POST:
		DrawKit.bitmap(self, SIGN_MARK, SIGN_MARK_POS.x, SIGN_MARK_POS.y, ORANGE_DARK)


func _draw_penguin(penguin: Dictionary) -> void:
	var x: float = float(penguin["x"])
	var y: float = float(penguin["y"])
	var cord: String = str(penguin["cord"])
	var flop: float = float(penguin.get("flop", -1.0))
	if flop >= 0.0:
		_draw_flop(x, y, cord, flop)
		return
	if bool(penguin.get("focused", false)) and not far and not solo and not bool(penguin.get("small", false)):
		CrowdArt.focus_ring(self, x, y, Ui.cord_color(cord), time)
	var shadow: int = int(penguin.get("shadow", 7))
	if shadow > 0 and not far:
		DrawKit.ellipse(self, x, y - 1.0, shadow + 1.0, float(penguin.get("shadow_ry", SHADOW_RY)), DrawKit.INK, SHADOW_ALPHA)
	var small: bool = bool(penguin.get("small", false))
	var picture: String = penguin_picture(cord, str(penguin["dir"]), str(penguin["pose"]), bool(penguin.get("blink", false)), small)
	if picture.is_empty():
		return
	var top_left := Vector2(x - PENGUIN_FOOT_X, y - PENGUIN_FOOT_Y + float(penguin.get("y_off", 0)))
	Atlas.draw(self, picture, top_left, bool(penguin.get("flip", false)))


## A penguin that failed: it shakes for a moment, falls on its back with its cap flying off, lies there, and gets up with the cap
## back on its head (the flop of `crowd-art.js`). `age` is the time since the fall began.
func _draw_flop(x: float, y: float, cord: String, age: float) -> void:
	var body: String = "penguin/%s/flop-body" % _cord_name(cord)
	var cap: String = "penguin/%s/cap" % _cord_name(cord)
	if age < FLOP_SHAKE:
		DrawKit.ellipse(self, x, y - 1.0, 8.0, SHADOW_RY, DrawKit.INK, SHADOW_ALPHA)
		var wobble: float = 1.0 if int(floorf(age * 60.0)) % 2 != 0 else -1.0
		Atlas.draw(self, penguin_picture(cord, "front", "idle"), Vector2(x - PENGUIN_FOOT_X + wobble, y - PENGUIN_FOOT_Y))
		return
	if age < FLOP_LIE_END:
		DrawKit.ellipse(self, x, y - 2.0, 16.0, 2.8, DrawKit.INK, SHADOW_ALPHA)
		Atlas.draw_at(self, body, x + 2.0, y + 3.0)
		if age < FLOP_CAP_LANDS:
			var k: float = (age - FLOP_SHAKE) / (FLOP_CAP_LANDS - FLOP_SHAKE)
			Atlas.draw_at(self, cap, x - 1.0 - 29.0 * k, y - 17.0 + 22.0 * k - sin(k * PI) * 16.0)
		else:
			DrawKit.ellipse(self, x - 30.0, y + 3.0, 9.0, 1.8, DrawKit.INK, SHADOW_ALPHA)
			Atlas.draw_at(self, cap, x - 30.0, y + 5.0)
		return
	var back: float = minf(1.0, (age - FLOP_LIE_END) / 0.3)
	var hop: float = roundf(sin(minf(1.0, (age - FLOP_LIE_END) / 0.35) * PI) * 5.0)
	DrawKit.ellipse(self, x, y - 1.0, 8.0, SHADOW_RY, DrawKit.INK, SHADOW_ALPHA)
	var standing: String = penguin_picture(cord, "front", "idle")
	if back < 1.0:
		standing += "/nocap"
	if Atlas.has(standing):
		Atlas.draw(self, standing, Vector2(x - PENGUIN_FOOT_X, y - PENGUIN_FOOT_Y - hop))
	if back < 1.0:
		Atlas.draw_at(self, cap, x - 30.0 + 29.0 * back, y + 5.0 + (-22.0 - hop) * back - sin(back * PI) * 14.0)


static func _cord_name(cord: String) -> String:
	return cord if Data.CORDS.has(cord) else "default"
