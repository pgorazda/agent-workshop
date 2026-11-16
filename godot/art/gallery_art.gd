# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# The gallery: a node that shows every picture of the atlas, page by page, with a line of text. The pages are made
# from the atlas data, so a new picture shows up with no change here. `build_pages()` has no screen need: a test uses
# it to check that every picture is on a page.
extends Node2D

const Atlas := preload("res://art/atlas.gd")
const DrawKit := preload("res://art/draw_kit.gd")
const TextArt := preload("res://art/text_art.gd")
const RoomArt := preload("res://art/room_art.gd")
const Data := preload("res://art/atlas_data.gd")

const SCREEN := Vector2i(480, 270)
const BACKGROUND := Color("#1b2236")
const CREAM := Color("#f7f9fc")
const GOLD := Color("#f2c230")
const DIM := Color("#8b95a8")
const GAP := 1
const MARGIN := 3
const CAPTION_HEIGHT := 14
## The line of text on every page. It has Polish letters and the middle dot.
const SAMPLE_LINE := "Zażółć gęślą jaźń · AGENT WORKSHOP 0123"

## The page that is shown. Set it with `show_page`.
var page_index: int = 0
## The time to load the sheets, in milliseconds, for the caption. -1 when it was not measured.
var load_ms: float = -1.0

var _pages: Array[Dictionary] = []


func _init() -> void:
	_pages = build_pages()


func _ready() -> void:
	queue_redraw()


func page_count() -> int:
	return _pages.size()


func page_title(index: int) -> String:
	return _pages[index]["title"]


func show_page(index: int) -> void:
	page_index = posmod(index, _pages.size())
	queue_redraw()


# ---------------------------------------------------------------- the pages

## Every page. A page is a Dictionary: "kind" ("flow", "mirror", "glyphs" or "room"), "title", and what the kind needs:
## "items" (name, x and y of each picture) for the flow kinds, "font" for glyphs, "rug" and "letter" for rooms.
static func build_pages() -> Array[Dictionary]:
	var pages: Array[Dictionary] = []
	var groups: Array[Array] = []
	for cord: String in Data.CORDS:
		groups.append(["penguins %s" % cord, _names_with_prefix("penguin/%s/" % cord)])
	groups.append(["props", _names_with_prefix("prop/")])
	groups.append(["icons, sparks and flames", _names_with_prefix("icon/") + _names_with_prefix("spark/") + _names_with_prefix("flame/")])
	for group in groups:
		var chunks: Array[Array] = _flow(group[1])
		for i in chunks.size():
			pages.append({"kind": "flow", "title": "%s %d/%d" % [group[0], i + 1, chunks.size()], "items": chunks[i]})
	# the left view is the right view, mirrored: show the side pictures of the first cord that way
	var mirrored: Array[String] = _names_with_prefix("penguin/claude-code/side/").filter(func(n: String) -> bool: return not n.ends_with("/blink") and not n.ends_with("/small"))
	var mirror_chunks: Array[Array] = _flow(mirrored)
	for i in mirror_chunks.size():
		pages.append({"kind": "mirror", "title": "penguins mirrored (left view) %d/%d" % [i + 1, mirror_chunks.size()], "items": mirror_chunks[i]})
	for font: String in Data.GLYPH_FONTS:
		pages.append({"kind": "glyphs", "title": "glyphs %s" % font, "font": font})
	pages.append({"kind": "room", "title": "room red, single room sign", "rug": "red", "letter": ""})
	for i in Data.RUGS.size():
		var rug: Dictionary = Data.RUGS[i]
		pages.append({"kind": "room", "title": "room %s, arena %s" % [rug["name"], char(65 + i)], "rug": rug["name"], "letter": char(65 + i)})
	pages.append({"kind": "room", "title": "room cobalt, arena AA (a double letter)", "rug": "cobalt", "letter": "AA"})
	return pages


static func _names_with_prefix(prefix: String) -> Array[String]:
	var found: Array[String] = []
	for picture: String in Data.PICTURES:
		if picture.begins_with(prefix):
			found.append(picture)
	return found


## Lays pictures out in rows, left to right, and starts a new page when the next row does not fit.
## Gives one array of {name, x, y} for each page.
static func _flow(names: Array) -> Array[Array]:
	var pages: Array[Array] = []
	var current: Array = []
	var x: int = MARGIN
	var y: int = MARGIN
	var row_h: int = 0
	var limit: int = SCREEN.y - CAPTION_HEIGHT
	for picture: String in names:
		var size: Vector2i = Atlas.size_of(picture)
		if x + size.x + MARGIN > SCREEN.x:
			x = MARGIN
			y += row_h + GAP
			row_h = 0
		if y + size.y > limit:
			pages.append(current)
			current = []
			x = MARGIN
			y = MARGIN
			row_h = 0
		current.append({"name": picture, "x": x, "y": y})
		x += size.x + GAP
		row_h = maxi(row_h, size.y)
	if not current.is_empty():
		pages.append(current)
	return pages


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	DrawKit.fill(self, 0, 0, SCREEN.x, SCREEN.y, BACKGROUND)
	if _pages.is_empty():
		return
	var page: Dictionary = _pages[page_index]
	var caption_y: int = SCREEN.y - 10
	match page["kind"]:
		"flow", "mirror":
			var mirror: bool = page["kind"] == "mirror"
			for item: Dictionary in page["items"]:
				Atlas.draw(self, item["name"], Vector2(item["x"], item["y"]), mirror)
		"glyphs":
			_draw_glyph_page(page["font"])
		"room":
			RoomArt.draw_room(self, page["rug"], page["letter"])
	TextArt.draw(self, SAMPLE_LINE, 6, caption_y - 11, CREAM, TextArt.TINY5)
	var caption: String = "%s   %d/%d" % [page["title"], page_index + 1, _pages.size()]
	if load_ms >= 0.0:
		caption += "   sheets loaded in %.1f ms" % load_ms
	TextArt.draw(self, caption, 6, caption_y, GOLD, TextArt.TINY5)
	var hint: String = "arrow keys"
	TextArt.draw(self, hint, SCREEN.x - 6 - TextArt.width(TextArt.TINY5, hint), caption_y, DIM, TextArt.TINY5)


## All the characters of a font in lines, then the width table of a few texts, and a "?" for a character the atlas lacks.
func _draw_glyph_page(font: String) -> void:
	var chars: String = ""
	for picture: String in Data.PICTURES:
		if picture.begins_with("glyph/%s/" % font):
			chars += char(picture.get_slice("U+", 1).hex_to_int())
	var x: int = 6
	var y: int = 6
	var line_h: int = TextArt.cell_height(font) + 3
	for i in chars.length():
		var ch: String = chars[i]
		var w: int = TextArt.advance(font, ch)
		if x + w > SCREEN.x - 6:
			x = 6
			y += line_h
		TextArt.draw(self, ch, x, y, CREAM, font)
		x += w + 2
	y += line_h * 2
	for sample: String in ["AGENT WORKSHOP  ARENA  SESSION START", "The quick brown fox jumps over the lazy dog", SAMPLE_LINE, "not in the atlas: Ж 漢 → shows as ??? "]:
		TextArt.draw(self, sample, 6, y, GOLD, font)
		y += line_h
