# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# Drawing for the tour (`art/tour-art.js` of the mockup; `core/tour.gd` holds the story): while the scene stands still, the rest of the
# screen dims, the parts that matter stay lit with a gold dashed outline, and a callout explains them. A callout is whitewash with a band
# across the top, like the room's walls: cobalt with peacock-eye dots when it reports an event, emerald when it explains something on
# screen, folk red for the title cards. A painted flower sits in its corner, and a dotted cord leads from it to what it explains.
#
# The lit parts are `{ "ell": [cx, cy, rx, ry] }` or `{ "rect": [x, y, w, h] }`. The view works them out from the live scene
# (`view/tour_holes.gd`). The functions that need no node are static, so that a test can check them with no screen.
extends Node2D

const DrawKit := preload("res://art/draw_kit.gd")
const TextArt := preload("res://art/text_art.gd")
const Ui := preload("res://art/ui_kit.gd")

const WALL := Color("#edf1f5")
const WAINSCOT := Color("#2f5fa7")
const WAINSCOT_DK := Color("#234a85")
const BLUE_LT := Color("#9cc0ee")
const GREEN := Color("#3f9a5a")
const GREEN_DK := Color("#2c7343")
const GREEN_LT := Color("#7cc48e")

const LINE_H := 9
const PAD := 7
const BAND_H := 13
## The dim over what is not lit: this opaque at its strongest.
const DIM_ALPHA := 0.6
## The dim and the outline fade in and out over this long (seconds).
const FADE := 0.18
## The viewport, and the room where a callout may stand.
const SCREEN := Vector2i(480, 270)

## What to draw: { "stop": Dictionary of the file, "holes": Array, "age": seconds in the stop, "step": 1-based, "steps": count }.
## Empty when no stop is on.
var state: Dictionary = { }


func set_state(new_state: Dictionary) -> void:
	if new_state == state:
		return
	state = new_state
	queue_redraw()


func _draw() -> void:
	if state.is_empty():
		return
	draw_stop(self, state["stop"], state["holes"], float(state["age"]), int(state["step"]), int(state["steps"]))


# ---------------------------------------------------------------- the lit parts

## The box round a lit part: [x, y, w, h].
static func bounds_of(hole: Dictionary) -> Array:
	if hole.has("ell"):
		var e: Array = hole["ell"]
		return [float(e[0]) - float(e[2]), float(e[1]) - float(e[3]), float(e[2]) * 2.0, float(e[3]) * 2.0]
	return hole["rect"]


## The runs of pixels of row `y` that are lit, from the left, as [[x0, x1], ...] (`spans` of the mockup).
static func spans(holes: Array, y: int) -> Array:
	var out: Array = []
	for hole: Dictionary in holes:
		if hole.has("ell"):
			var e: Array = hole["ell"]
			var d: float = (float(y) + 0.5 - float(e[1])) / float(e[3])
			if absf(d) < 1.0:
				var half: float = float(e[2]) * sqrt(1.0 - d * d)
				out.append([DrawKit.rnd(float(e[0]) - half), DrawKit.rnd(float(e[0]) + half)])
		else:
			var r: Array = hole["rect"]
			if y >= int(r[1]) and y < int(r[1]) + int(r[3]):
				out.append([int(r[0]), int(r[0]) + int(r[2])])
	out.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	return out


## The rectangles of the dim: every row of the screen, except the lit runs.
static func dim_rects(holes: Array) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for y in SCREEN.y:
		var x: int = 0
		for span: Array in spans(holes, y):
			if int(span[0]) > x:
				rects.append(Rect2i(x, y, int(span[0]) - x, 1))
			x = maxi(x, int(span[1]))
		if x < SCREEN.x:
			rects.append(Rect2i(x, y, SCREEN.x - x, 1))
	return rects


static func dim(ci: CanvasItem, holes: Array, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var tint := Color(Ui.INK, alpha)
	for rect in dim_rects(holes):
		ci.draw_rect(Rect2(rect), tint)


## Whether the dash of the outline is on at a pixel: the dashes move slowly with the age of the stop.
static func dash_on(x: int, y: int, age: float) -> bool:
	return posmod(floori(float(x + y) / 2.0) + floori(age * 6.0), 3) != 0


## The pixels of the dashed gold line just outside a lit part.
static func outline_points(hole: Dictionary, age: float) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	if hole.has("rect"):
		var r: Array = hole["rect"]
		var x0: int = int(r[0]) - 1
		var y0: int = int(r[1]) - 1
		var x1: int = int(r[0]) + int(r[2])
		var y1: int = int(r[1]) + int(r[3])
		for i in range(x0, x1 + 1):
			if dash_on(i, y0, age):
				points.append(Vector2i(i, y0))
			if dash_on(i, y1, age):
				points.append(Vector2i(i, y1))
		for j in range(y0, y1 + 1):
			if dash_on(x0, j, age):
				points.append(Vector2i(x0, j))
			if dash_on(x1, j, age):
				points.append(Vector2i(x1, j))
		return points
	var e: Array = hole["ell"]
	var cx: float = float(e[0])
	var cy: float = float(e[1])
	var rx: float = float(e[2])
	var ry: float = float(e[3])
	for y in range(floori(cy - ry - 2.0), ceili(cy + ry + 2.0) + 1):
		for x in range(floori(cx - rx - 2.0), ceili(cx + rx + 2.0) + 1):
			var dx: float = (float(x) + 0.5 - cx) / rx
			var dy: float = (float(y) + 0.5 - cy) / ry
			var d: float = sqrt(dx * dx + dy * dy)
			if d > 1.0 and d <= 1.0 + 1.3 / minf(rx, ry) and dash_on(x, y, age):
				points.append(Vector2i(x, y))
	return points


static func outline(ci: CanvasItem, hole: Dictionary, age: float) -> void:
	for point in outline_points(hole, age):
		DrawKit.px(ci, point.x, point.y, Ui.GOLD)


# ---------------------------------------------------------------- the callout

static func _overlaps(a: Array, b: Array, m: float = 3.0) -> bool:
	return float(a[0]) < float(b[0]) + float(b[2]) + m and float(b[0]) < float(a[0]) + float(a[2]) + m \
			and float(a[1]) < float(b[1]) + float(b[3]) + m and float(b[1]) < float(a[1]) + float(a[3]) + m


## Where the callout goes: next to the first lit part, on the first side where it fits and covers nothing lit (`place` of the mockup).
## `wanted` is a place that the stop asks for, `centred` puts the box in the middle of the room.
static func place(w: int, h: int, holes: Array, wanted: Variant, centred: bool) -> Vector2i:
	if wanted is Array:
		return Vector2i(int((wanted as Array)[0]), int((wanted as Array)[1]))
	if centred:
		return Vector2i(DrawKit.rnd((480.0 - float(w)) / 2.0), DrawKit.rnd((232.0 - float(h)) / 2.0))
	var boxes: Array = []
	for hole: Dictionary in holes:
		boxes.append(bounds_of(hole))
	var candidates: Array[Vector2] = []
	var fw: float = float(w)
	var fh: float = float(h)
	if not boxes.is_empty():
		var first: Array = boxes[0]
		var x: float = float(first[0])
		var y: float = float(first[1])
		var bw: float = float(first[2])
		var bh: float = float(first[3])
		var cx: float = x + bw / 2.0
		var cy: float = y + bh / 2.0
		candidates.append_array([
			Vector2(x + bw + 12.0, cy - fh / 2.0), Vector2(x - 12.0 - fw, cy - fh / 2.0), Vector2(cx - fw / 2.0, y + bh + 10.0), Vector2(cx - fw / 2.0, y - 10.0 - fh),
			Vector2(x + bw + 12.0, y - fh + 8.0), Vector2(x - 12.0 - fw, y - fh + 8.0), Vector2(x + bw + 12.0, y + bh - 8.0), Vector2(x - 12.0 - fw, y + bh - 8.0),
		])
	candidates.append_array([Vector2(170, 92), Vector2(24, 96), Vector2(296, 96), Vector2(170, 180), Vector2(24, 20), Vector2(296, 20)])
	for candidate in candidates:
		var px: int = DrawKit.rnd(candidate.x)
		var py: int = DrawKit.rnd(candidate.y)
		if px < 3 or py < 3 or px + w > 477 or py + h > 229:
			continue
		var blocked: bool = false
		for b: Array in boxes:
			if _overlaps([px, py, w, h], b):
				blocked = true
				break
		if not blocked:
			return Vector2i(px, py)
	return Vector2i(DrawKit.rnd((480.0 - float(w)) / 2.0), 96)


## A dotted cord from the edge of the callout to the point it explains, ending in a gold bead.
static func cord(ci: CanvasItem, x: int, y: int, w: int, h: int, target: Vector2i) -> void:
	var sx: int
	var sy: int
	if target.x < x:
		sx = x
		sy = maxi(y + 4, mini(y + h - 4, target.y))
	elif target.x >= x + w:
		sx = x + w - 1
		sy = maxi(y + 4, mini(y + h - 4, target.y))
	elif target.y < y:
		sx = maxi(x + 4, mini(x + w - 4, target.x))
		sy = y
	else:
		sx = maxi(x + 4, mini(x + w - 4, target.x))
		sy = y + h - 1
	var n: int = maxi(absi(target.x - sx), absi(target.y - sy))
	var i: int = 0
	while i <= n and n > 0:
		var px0: float = float(sx) + float(target.x - sx) * float(i) / float(n)
		var py0: float = float(sy) + float(target.y - sy) * float(i) / float(n)
		DrawKit.px(ci, px0, py0 + 1.0, Ui.INK)
		DrawKit.px(ci, px0, py0, Ui.CREAM)
		i += 2
	DrawKit.ellipse(ci, float(target.x), float(target.y), 2.2, 2.2, Ui.INK)
	DrawKit.ellipse(ci, float(target.x), float(target.y), 1.4, 1.4, Ui.GOLD)


## The peacock eye on the band: a cream disc with four dots round a centre.
static func eye(ci: CanvasItem, x: int, y: int, ring: Color, mid: Color) -> void:
	DrawKit.ellipse(ci, float(x), float(y), 2.0, 2.0, Ui.CREAM)
	DrawKit.px(ci, x - 2, y, ring)
	DrawKit.px(ci, x + 2, y, ring)
	DrawKit.px(ci, x, y - 2, ring)
	DrawKit.px(ci, x, y + 2, ring)
	DrawKit.px(ci, x, y, mid)


## The painted flower in the corner of a callout.
static func flower(ci: CanvasItem, x: int, y: int) -> void:
	for offset: Vector2 in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		DrawKit.ellipse(ci, float(x) + offset.x, float(y) + offset.y, 1.3, 1.3, Ui.ORANGE)
	DrawKit.px(ci, x, y, Ui.GOLD)
	DrawKit.px(ci, x - 4, y + 3, GREEN)
	DrawKit.px(ci, x - 3, y + 3, GREEN_LT)
	DrawKit.px(ci, x + 4, y + 3, GREEN)
	DrawKit.px(ci, x + 3, y + 3, GREEN_LT)


## The band colours of a kind of stop: [band, dark edge].
static func band_of(kind: String) -> Array[Color]:
	match kind:
		"event":
			return [WAINSCOT, WAINSCOT_DK]
		"title":
			return [Ui.ORANGE, Ui.ORANGE_DK]
	return [GREEN, GREEN_DK]


## The size of the callout of a stop: [w, h].
static func callout_size(stop: Dictionary, step: int, steps: int) -> Vector2i:
	var big: bool = str(stop["kind"]) == "title" and stop.has("heading")
	var counter: String = "%d/%d" % [step, steps] if steps > 0 else ""
	var head: int = TextArt.width(TextArt.SILK_BIG, str(stop["heading"])) if big else 0
	var w: int = maxi(TextArt.width(TextArt.SILK, str(stop["title"])) + 22 + TextArt.width(TextArt.TINY5, counter) + 8, head + 2 * PAD + 4)
	for line: Variant in stop["lines"]:
		# the width counts the quote mark too, as the mockup does
		w = maxi(w, TextArt.width(TextArt.TINY5, str(line)) + 2 * PAD + 8)
	var h: int = BAND_H + 5 + (20 if big else 0) + (stop["lines"] as Array).size() * LINE_H + 7
	return Vector2i(w, h)


## A line that starts with a quote mark and a space quotes the event. It shows in cobalt, without those two characters.
static func _plain(line: String) -> String:
	return line.substr(2) if line.begins_with("` ") else line


static func callout(ci: CanvasItem, stop: Dictionary, holes: Array, age: float, step: int, steps: int) -> void:
	var kind: String = str(stop["kind"])
	var big: bool = kind == "title" and stop.has("heading")
	var counter: String = "%d/%d" % [step, steps] if steps > 0 else ""
	var size: Vector2i = callout_size(stop, step, steps)
	var w: int = size.x
	var h: int = size.y
	var place_at: Vector2i = place(w, h, holes, stop.get("box"), bool(stop.get("centred", false)))
	var bx: int = place_at.x
	var y: int = place_at.y + (DrawKit.rnd(4.0 * (1.0 - age / 0.14)) if age < 0.14 else 0)
	var target: Variant = null
	if stop.has("point"):
		target = Vector2i(int((stop["point"] as Array)[0]), int((stop["point"] as Array)[1]))
	elif not holes.is_empty():
		var b: Array = bounds_of(holes[0])
		target = Vector2i(DrawKit.rnd(float(b[0]) + float(b[2]) / 2.0), DrawKit.rnd(float(b[1]) + float(b[3]) / 2.0))
	if target != null:
		cord(ci, bx, y, w, h, target as Vector2i)
	DrawKit.box(ci, bx, y, w, h, WALL, Ui.INK)
	var colours: Array[Color] = band_of(kind)
	DrawKit.fill(ci, bx + 1, y + 1, w - 2, BAND_H - 1, colours[0])
	DrawKit.fill(ci, bx + 1, y + BAND_H, w - 2, 1, colours[1])
	eye(ci, bx + 7, y + 6, BLUE_LT if kind == "event" else Ui.GOLD, WAINSCOT_DK if kind == "event" else colours[1])
	TextArt.draw(ci, str(stop["title"]), bx + 13, y + 3, Ui.CREAM, TextArt.SILK)
	if counter != "":
		TextArt.draw(ci, counter, bx + w - 6 - TextArt.width(TextArt.TINY5, counter), y + 3, BLUE_LT if kind == "event" else Ui.CREAM)
	var ty: int = y + BAND_H + 5
	if big:
		var head: int = TextArt.width(TextArt.SILK_BIG, str(stop["heading"]))
		TextArt.draw(ci, str(stop["heading"]), DrawKit.rnd(float(bx) + float(w - head) / 2.0), ty, Ui.ORANGE_DK, TextArt.SILK_BIG)
		ty += 20
	var lines: Array = stop["lines"]
	for i in lines.size():
		var line: String = str(lines[i])
		var code: bool = line.begins_with("` ")
		var shown: String = _plain(line)
		var x: int = DrawKit.rnd(float(bx) + float(w - TextArt.width(TextArt.TINY5, shown)) / 2.0) if big else bx + PAD
		TextArt.draw(ci, shown, x, ty + i * LINE_H, WAINSCOT_DK if code else Ui.INK)
	flower(ci, bx + w - 7, y + h - 7)


## How far in the dim and the outline are: 0 at the start and the end of the stop, 1 in the middle.
static func fade_of(age: float, dur: float) -> float:
	return maxf(0.0, minf(1.0, minf(age / FADE, (dur - age) / FADE)))


## One stop of the tour, `age` seconds after it began. `step` of `steps` is the counter in the band.
static func draw_stop(ci: CanvasItem, stop: Dictionary, holes: Array, age: float, step: int, steps: int) -> void:
	var dur: float = float(stop["dur"])
	var k: float = fade_of(age, dur)
	dim(ci, holes, DIM_ALPHA * k)
	if k > 0.6:
		for hole: Dictionary in holes:
			outline(ci, hole, age)
	if age > 0.04 and dur - age > 0.06:
		callout(ci, stop, holes, age, step, steps)
