# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# The ribbon of a new arena (`ribbon` and `arenaRibbon` in the mockup): when the camera shows an arena for the first time, a
# ribbon in the colour of its rug says "ARENA B" on the wall, with a few gold sparkles round it. It sits on the wall, where
# nothing plays: lower down it would hide the label of the new penguin or the ribbon of a finished turn.
extends RefCounted

const DrawKit := preload("res://art/draw_kit.gd")
const TextArt := preload("res://art/text_art.gd")
const EffectsArt := preload("res://art/effects_art.gd")
const RoomArt := preload("res://art/room_art.gd")

const CREAM := Color("#f7f9fc")
## How long the ribbon stays, in seconds.
const LIFE := 2.6
const RIBBON_Y := 12
const RIBBON_CENTRE := 240
## [delay, dx, dy] of the sparkles round the ribbon.
const SPARKLES: Array = [
	[0.05, -52.0, 10.0], [0.3, 50.0, 8.0], [0.6, -38.0, 34.0], [0.9, 56.0, 32.0], [1.3, -60.0, 22.0], [1.7, 44.0, 12.0],
]


## The size of a ribbon with this label: its width without the tails.
static func ribbon_width(label: String) -> int:
	return TextArt.width(TextArt.SILK, label) + 16


## A ribbon with its centre at `cx` and its top at `y`: two tails, a box and the label.
static func draw_ribbon(ci: CanvasItem, cx: float, y: float, label: String, fill_color: Color, dark_color: Color, text_color: Color) -> void:
	var w: int = ribbon_width(label)
	var x0: int = DrawKit.rnd(cx - float(w) / 2.0)
	var h: int = 13
	for side: int in [-1, 1]:
		for r in 11:
			var n: int = DrawKit.rnd(3.0 - absf(float(r - 5)) * 0.6)
			var a: int = x0 - 11 + n if side < 0 else x0 + w - 1
			var b: int = x0 + 1 if side < 0 else x0 + w + 10 - n
			DrawKit.fill(ci, a, y + 4 + r, b - a, 1, dark_color)
			DrawKit.px(ci, a - 1 if side < 0 else b, y + 4 + r, DrawKit.INK)
		var tail_x: int = x0 - 11 if side < 0 else x0 + w - 1
		DrawKit.fill(ci, tail_x, y + 3, 12, 1, DrawKit.INK)
		DrawKit.fill(ci, tail_x, y + 15, 12, 1, DrawKit.INK)
	DrawKit.box(ci, x0, y, w, h, fill_color, DrawKit.INK)
	DrawKit.fill(ci, x0 + 1, y + h - 2, w - 2, 1, dark_color)
	TextArt.draw(ci, label, x0 + 8, y + 3, text_color, TextArt.SILK)


## The ribbon of arena `letter` at `age` seconds after the camera first showed it. Nothing is drawn before 0 or after LIFE.
static func draw_arena_ribbon(ci: CanvasItem, letter: String, rug: String, age: float) -> void:
	if age < 0.0 or age > LIFE:
		return
	for entry: Array in SPARKLES:
		EffectsArt.sparkle(ci, float(RIBBON_CENTRE) + float(entry[1]), float(entry[2]), age - float(entry[0]))
	var colors: Dictionary = RoomArt.rug_named(rug)
	var top: float = float(RIBBON_Y) - (3.0 if age < 0.1 else 0.0)
	draw_ribbon(ci, RIBBON_CENTRE, top, "ARENA %s" % letter, Color.html(str(colors["color"])), Color.html(str(colors["dark"])), CREAM)
