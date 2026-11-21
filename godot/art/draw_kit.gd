# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# The drawing primitives of the frame code, as in look.js: pixel, fill, box, ellipse, line, bitmap and icon.
# Every function takes the CanvasItem to draw on (call it from `_draw`). Positions are rounded to whole pixels
# with floor(x + 0.5), as Math.round does.
#
# Each shape that is made of rectangles or pixels also has a function with the suffix `_rects` or `_points`.
# It gives the same shapes as data, so that a test can check them with no screen.
extends RefCounted

const Atlas := preload("res://art/atlas.gd")

## The dark outline colour of look.js (P.ink).
const INK := Color("#1d2333")
## The shadow of a box has this opacity.
const BOX_SHADOW_ALPHA := 0.22


## Math.round for the numbers that the art uses.
static func rnd(value: float) -> int:
	return floori(value + 0.5)


# ---------------------------------------------------------------- shapes as data

## The rectangles of a filled ellipse, one for each row: runs of pixels whose centre lies inside it (pxEll).
##
## A pixel is inside when ((x + 0.5 - cx) / rx)^2 + ((y + 0.5 - cy) / ry)^2 <= 1. In one row the pixels that are inside form one run.
## The ends of the run come from the equation of the ellipse and are then checked with the test above, so the result is the one that a
## test of every pixel gives (`ellipse_rects_by_pixel`, kept to check this). It is fast: a row costs a few operations, not a test for
## each pixel. The glow of the forge is five ellipses that are drawn in every frame.
static func ellipse_rects(cx: float, cy: float, rx: float, ry: float) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	if rx <= 0.0 or ry <= 0.0:
		return rects
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		var dy: float = (y + 0.5 - cy) / ry
		var rest: float = 1.0 - dy * dy
		if rest < 0.0:
			continue
		var half: float = rx * sqrt(rest)
		var first: int = ceili(cx - half - 0.5)
		var last: int = floori(cx + half - 0.5)
		# the ends are made exact with the test of the definition: move out while the pixel outside is inside, and in while the end is outside
		while _inside(first - 1, dy, cx, rx):
			first -= 1
		while first <= last and not _inside(first, dy, cx, rx):
			first += 1
		while _inside(last + 1, dy, cx, rx):
			last += 1
		while last >= first and not _inside(last, dy, cx, rx):
			last -= 1
		if first <= last:
			rects.append(Rect2i(first, y, last - first + 1, 1))
	return rects


static func _inside(x: int, dy: float, cx: float, rx: float) -> bool:
	var dx: float = (x + 0.5 - cx) / rx
	return dx * dx + dy * dy <= 1.0


## The same rectangles from a test of every pixel (the definition). Slow: only for the tests.
static func ellipse_rects_by_pixel(cx: float, cy: float, rx: float, ry: float) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	if rx <= 0.0 or ry <= 0.0:
		return rects
	var x0: int = floori(cx - rx)
	var x1: int = ceili(cx + rx)
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		var run: int = -1
		var in_run: bool = false
		for x in range(x0, x1 + 2):
			var dx: float = (x + 0.5 - cx) / rx
			var dy: float = (y + 0.5 - cy) / ry
			var inside: bool = x <= x1 and dx * dx + dy * dy <= 1.0
			if inside and not in_run:
				run = x
				in_run = true
			elif not inside and in_run:
				rects.append(Rect2i(run, y, x - run, 1))
				in_run = false
	return rects


## The pixels of a line from (x0, y0) to (x1, y1), in drawing order (Bresenham, as pxLine).
static func line_points(x0: float, y0: float, x1: float, y1: float) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var ax: int = rnd(x0)
	var ay: int = rnd(y0)
	var bx: int = rnd(x1)
	var by: int = rnd(y1)
	var dx: int = absi(bx - ax)
	var dy: int = -absi(by - ay)
	var sx: int = 1 if ax < bx else -1
	var sy: int = 1 if ay < by else -1
	var err: int = dx + dy
	while true:
		points.append(Vector2i(ax, ay))
		if ax == bx and ay == by:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			ax += sx
		if e2 <= dx:
			err += dx
			ay += sy
	return points


## The rectangles of a bitmap: one for each run of "#" in a row. Any other character is empty.
static func bitmap_rects(rows: Array, x: float, y: float) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	var ox: int = rnd(x)
	var oy: int = rnd(y)
	for j in rows.size():
		var row: String = rows[j]
		var start: int = -1
		for i in range(row.length() + 1):
			var on: bool = i < row.length() and row[i] == "#"
			if on and start < 0:
				start = i
			elif not on and start >= 0:
				rects.append(Rect2i(ox + start, oy + j, i - start, 1))
				start = -1
	return rects


## The parts of a box, in drawing order: the four edges (corners left out), then the inside. The shadow comes first
## and is separate (`box_shadow_rect`).
static func box_rects(x: float, y: float, w: int, h: int) -> Array[Rect2i]:
	var bx: int = rnd(x)
	var by: int = rnd(y)
	return [
		Rect2i(bx + 1, by, w - 2, 1),
		Rect2i(bx + 1, by + h - 1, w - 2, 1),
		Rect2i(bx, by + 1, 1, h - 2),
		Rect2i(bx + w - 1, by + 1, 1, h - 2),
		Rect2i(bx + 1, by + 1, w - 2, h - 2),
	]


## The line under a box that has a shadow.
static func box_shadow_rect(x: float, y: float, w: int, h: int) -> Rect2i:
	return Rect2i(rnd(x) + 1, rnd(y) + h, w - 2, 1)


# ---------------------------------------------------------------- drawing

## One pixel.
static func px(ci: CanvasItem, x: float, y: float, color: Color) -> void:
	ci.draw_rect(Rect2(rnd(x), rnd(y), 1, 1), color)


## A filled rectangle.
static func fill(ci: CanvasItem, x: float, y: float, w: float, h: float, color: Color) -> void:
	ci.draw_rect(Rect2(rnd(x), rnd(y), w, h), color)


## A box with a one pixel outline, corners cut, and an optional shadow line below it.
static func box(ci: CanvasItem, x: float, y: float, w: int, h: int, fill_color: Color, line_color: Color, shadow: bool = true) -> void:
	if shadow:
		ci.draw_rect(Rect2(box_shadow_rect(x, y, w, h)), Color(INK, BOX_SHADOW_ALPHA))
	var parts: Array[Rect2i] = box_rects(x, y, w, h)
	for i in 4:
		ci.draw_rect(Rect2(parts[i]), line_color)
	ci.draw_rect(Rect2(parts[4]), fill_color)


## A filled ellipse made of one rectangle for each row, with an opacity.
static func ellipse(ci: CanvasItem, cx: float, cy: float, rx: float, ry: float, color: Color, alpha: float = 1.0) -> void:
	var tint := Color(color, color.a * alpha)
	for rect in ellipse_rects(cx, cy, rx, ry):
		ci.draw_rect(Rect2(rect), tint)


## A line of single pixels.
static func line(ci: CanvasItem, x0: float, y0: float, x1: float, y1: float, color: Color) -> void:
	for point in line_points(x0, y0, x1, y1):
		ci.draw_rect(Rect2(Vector2(point), Vector2.ONE), color)


## A bitmap: rows of text, "#" is a pixel in `color`.
static func bitmap(ci: CanvasItem, rows: Array, x: float, y: float, color: Color) -> void:
	for rect in bitmap_rects(rows, x, y):
		ci.draw_rect(Rect2(rect), color)


## One of the 7x7 activity icons (read, search, write, exec, delegate, think, ask, star, web, other).
static func icon(ci: CanvasItem, icon_name: String, x: float, y: float) -> void:
	Atlas.draw(ci, "icon/%s" % icon_name, Vector2(x, y))
