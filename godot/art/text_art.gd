# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# Text drawn from the glyph atlas. The glyphs were drawn by text() of look.js (one character at a time, in white), so
# the letters are the mockup's. The width of a text is the sum of the widths of its glyphs. For ASCII text this is the
# width that textW() gives. Some Polish letters of Silkscreen have a fractional width in the font, which textW() rounds
# up for the whole string and the atlas rounds up for each glyph: such text is up to five pixels wider here (in the large size).
#
# The set of characters is printable ASCII, the Polish letters, the middle dot and two arrows. A character that
# the atlas does not hold is drawn as "?".
extends RefCounted

const Atlas := preload("res://art/atlas.gd")
const DrawKit := preload("res://art/draw_kit.gd")
const Data := preload("res://art/atlas_data.gd")

## The font ids of the atlas: Tiny5 at 8 pixels (the normal text), Silkscreen at 8 (titles, ribbons), and at 16 (the tour).
const TINY5 := "tiny5-8"
const SILK := "silk-8"
const SILK_BIG := "silk-16"

## The cross that look.js draws as a bitmap (GL), for the "✗" sign. It is 5 pixels wide, one pixel down, and has 2 pixels of space.
const CROSS_ROWS: Array[String] = ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"]
const CROSS_DROP := 1
const CROSS_SPACE := 2
const CROSS_CHAR := "✗"


## The name of the picture of a character in a font, for example "glyph/silk-8/U+0041".
static func glyph_name(font: String, ch: String) -> String:
	return "glyph/%s/U+%04X" % [font, ch.unicode_at(0)]


## The glyph name that is used for a character: its own, or the one of "?" when the atlas does not hold it.
static func glyph_for(font: String, ch: String) -> String:
	var wanted: String = glyph_name(font, ch)
	if Data.PICTURES.has(wanted):
		return wanted
	return glyph_name(font, Data.UNKNOWN_CHAR)


## The glyphs that were asked for: font -> { character code -> [texture, source rectangle, advance] }. A text is drawn in every frame,
## so the lookup of a glyph (its name, its entry in the atlas data, its texture) is done once for each character.
static var _glyphs: Dictionary = { }


static func _glyph(font: String, code: int) -> Array:
	var table: Dictionary
	if _glyphs.has(font):
		table = _glyphs[font]
	else:
		table = { }
		_glyphs[font] = table
	var cached: Variant = table.get(code)
	if cached != null:
		return cached as Array
	var entry: Array = Data.PICTURES[glyph_for(font, String.chr(code))]
	var made: Array = [Atlas.texture(int(entry[0])), Rect2(float(entry[1]), float(entry[2]), float(entry[3]), float(entry[4])), int(entry[3])]
	table[code] = made
	return made


## The width in pixels of one character: the advance of its glyph.
static func advance(font: String, ch: String) -> int:
	return int(_glyph(font, ch.unicode_at(0))[2])


## The width of a text, as textW() of look.js gives it.
static func width(font: String, text: String) -> int:
	var total: int = 0
	for i in text.length():
		total += int(_glyph(font, text.unicode_at(i))[2])
	return total


## Cuts a text to a width: the end is replaced by two dots, as `fit` of crowd-art.js does. A text that fits stays as it is.
static func fit(font: String, text: String, max_width: int) -> String:
	if width(font, text) <= max_width:
		return text
	var cut: String = text
	while cut.length() > 1 and width(font, cut + "..") > max_width:
		cut = cut.substr(0, cut.length() - 1)
	return cut + ".."


## The height of the glyph cells of a font, and the pixels between the top of the line and the first row.
static func cell_height(font: String) -> int:
	return int((Data.GLYPH_FONTS[font] as Dictionary)["h"])


static func offset_y(font: String) -> int:
	return int((Data.GLYPH_FONTS[font] as Dictionary)["oy"])


## The width of a text that `rich` draws: the "✗" sign is a bitmap of 5 pixels and 2 pixels of space.
static func rich_width(font: String, text: String) -> int:
	var total: int = 0
	for i in text.length():
		if text[i] == CROSS_CHAR:
			total += CROSS_ROWS[0].length() + CROSS_SPACE
		else:
			total += advance(font, text[i])
	return total


## Draws a text with its line top left at (x, y), like text() of look.js. Returns the width. `color` tints the white glyphs.
static func draw(ci: CanvasItem, text: String, x: float, y: float, color: Color, font: String = TINY5) -> int:
	var pen_x: int = DrawKit.rnd(x)
	var top: float = float(DrawKit.rnd(y) + offset_y(font))
	for i in text.length():
		var glyph: Array = _glyph(font, text.unicode_at(i))
		var source: Rect2 = glyph[1]
		ci.draw_texture_rect_region(glyph[0] as Texture2D, Rect2(float(pen_x), top, source.size.x, source.size.y), source, color)
		pen_x += int(glyph[2])
	return pen_x - DrawKit.rnd(x)


## Draws a text in coloured parts, like rich() of look.js: `segments` is a list of [text, color]. The "✗" sign is a
## bitmap, as in the mockup. Returns the x where the text ends.
static func rich(ci: CanvasItem, segments: Array, x: float, y: float, font: String = TINY5) -> float:
	var pen: float = x
	for segment: Array in segments:
		var part: String = segment[0]
		var color: Color = segment[1]
		var run: String = ""
		for i in part.length():
			var ch: String = part[i]
			if ch == CROSS_CHAR:
				if not run.is_empty():
					pen += draw(ci, run, pen, y, color, font)
					run = ""
				DrawKit.bitmap(ci, CROSS_ROWS, pen, y + CROSS_DROP, color)
				pen += CROSS_ROWS[0].length() + CROSS_SPACE
			else:
				run += ch
		if not run.is_empty():
			pen += draw(ci, run, pen, y, color, font)
	return pen
