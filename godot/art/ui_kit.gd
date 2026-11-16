# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# The colours and the small parts that the interface shares (the bar, the overview, the chips, the notices): the colours of the
# log (`HC` in look.js), a number chip, an outline, the three dots of a running call, and the status text of a card. They follow
# `crowd-art.js` and `arenas-art.js` of the mockup.
extends RefCounted

const DrawKit := preload("res://art/draw_kit.gd")
const TextArt := preload("res://art/text_art.gd")
const Data := preload("res://art/atlas_data.gd")

# the colours of the log, the bar and the overview
const BG := Color("#1b2236")
const EDGE := Color("#34405e")
const EDGE2 := Color("#283152")
const TEXT := Color("#f7f9fc")
const DIM := Color("#8b95a8")
const BLUE := Color("#9cc0ee")
const GOLD := Color("#f2c230")
const GREEN := Color("#6fdc8c")
const RED := Color("#ff6b6b")
const DOT := Color("#3d4866")
const CARD_BG := Color("#222b44")
const LIT_BG := Color("#34416a")
const NEW_BG := Color("#3a2a1e")
const MANUAL_BG := Color("#1d3326")
const FREE := Color("#161c2e")
const MENU_HOVER := Color("#2c3756")
# the colours of the room
const INK := Color("#1d2333")
const CREAM := Color("#f7f9fc")
const WHITE := Color("#ffffff")
const PAPER := Color("#f1e3c0")
const PAPER_DK := Color("#dfcb9b")
const ORANGE := Color("#d23c3c")
const ORANGE_DK := Color("#a82a32")
const GREEN_P := Color("#3f9a5a")
const GREEN_DK := Color("#2c7343")
const GREEN_LT := Color("#7cc48e")
const GOLD_DK := Color("#c79a1c")
const TEXT_DIM_ROOM := Color("#7d6a4f")


## The cord colour of a framework (a key of CORDS in atlas_data.gd; an unknown one is the grey of "default").
static func cord_color(cord: String) -> Color:
	return Color.html(str(Data.CORDS.get(cord, Data.CORDS["default"])))


## The colour of the rug of an arena by its index (A is 0).
static func rug_color(index: int) -> Color:
	return Color.html(str((Data.RUGS[index % Data.RUGS.size()] as Dictionary)["color"]))


static func rug_dark(index: int) -> Color:
	return Color.html(str((Data.RUGS[index % Data.RUGS.size()] as Dictionary)["dark"]))


## True for the first 0.4 s of each 0.8 s: the blink of a card or a tab that waits for an approval.
static func blink_on(t: float) -> bool:
	return int(floorf(t / 0.4)) % 2 == 0


## The width of a number chip: the number and 5 pixels.
static func chip_width(number: int) -> int:
	return TextArt.width(TextArt.TINY5, str(number)) + 5


## A chip with a number, in the cord colour. `h` is 9 (the usual) or 8 (small). Returns its width.
static func chip(ci: CanvasItem, number: int, x: float, y: float, color: Color, h: int = 9) -> int:
	var s: String = str(number)
	var w: int = TextArt.width(TextArt.TINY5, s) + 5
	DrawKit.box(ci, x, y, w, h, color, INK, false)
	TextArt.draw(ci, s, x + 3, y + (1 if h == 9 else 0), WHITE)
	return w


## An outline of one pixel; a dashed one has two pixels on and two off.
static func outline(ci: CanvasItem, x: int, y: int, w: int, h: int, color: Color, dashed: bool = false) -> void:
	for i in w:
		if not dashed or i % 4 < 2:
			DrawKit.px(ci, x + i, y, color)
			DrawKit.px(ci, x + i, y + h - 1, color)
	for j in h:
		if not dashed or j % 4 < 2:
			DrawKit.px(ci, x, y + j, color)
			DrawKit.px(ci, x + w - 1, y + j, color)


## Three dots of a running call: one is lit, and it moves.
static func dots(ci: CanvasItem, x: int, y: int, t: float, on: Color = GOLD, off: Color = DOT) -> void:
	var lit: int = int(floorf(t * 6.0)) % 3
	for i in 3:
		DrawKit.fill(ci, x + i * 4, y, 2, 2, on if lit == i else off)


## The status of a card at its right edge: dots for "run"; "WAIT" blinks; "OK" is green, "FAIL" red, "DONE" green.
static func status_text(ci: CanvasItem, state: String, x: int, y: int, t: float) -> void:
	if state == "run":
		dots(ci, x, y + 2, t)
		return
	if state == "" or state == "idle":
		return
	if state == "WAIT" and not blink_on(t):
		return
	var color: Color = RED if state == "FAIL" else (GOLD if state == "WAIT" else GREEN)
	TextArt.draw(ci, state, x + 10 - TextArt.width(TextArt.TINY5, state), y, color)


## The rectangles of an ellipse ring on the floor (the focus ring): one rectangle for each run of pixels in a row whose distance
## from the centre is between 0.62 and 1 of the radius (a pixel is tested at its centre).
static func ring_rects(cx: float, cy: float, rx: float, ry: float) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	var x0: int = floori(cx - rx - 1.0)
	var x1: int = ceili(cx + rx + 1.0)
	for y in range(floori(cy - ry - 1.0), ceili(cy + ry + 1.0) + 1):
		var run: int = 0
		var in_run: bool = false
		for x in range(x0, x1 + 2):
			var inside: bool = false
			if x <= x1:
				var dx: float = (float(x) + 0.5 - cx) / rx
				var dy: float = (float(y) + 0.5 - cy) / ry
				var d: float = dx * dx + dy * dy
				inside = d <= 1.0 and d > 0.62
			if inside and not in_run:
				run = x
				in_run = true
			elif not inside and in_run:
				rects.append(Rect2i(run, y, x - run, 1))
				in_run = false
	return rects


static func ring(ci: CanvasItem, cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	for rect in ring_rects(cx, cy, rx, ry):
		ci.draw_rect(Rect2(rect), color)
