# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# Finds a picture by its name and draws it. The names and rectangles are in atlas_data.gd.
extends RefCounted

const Data := preload("res://art/atlas_data.gd")

static var _textures: Array[Texture2D] = []


## True when the atlas has a picture with this name.
static func has(picture: String) -> bool:
	return Data.PICTURES.has(picture)


## The size of a picture in pixels.
static func size_of(picture: String) -> Vector2i:
	var entry: Array = Data.PICTURES[picture]
	return Vector2i(int(entry[3]), int(entry[4]))


## The rectangle of a picture in its sheet.
static func rect_of(picture: String) -> Rect2i:
	var entry: Array = Data.PICTURES[picture]
	return Rect2i(int(entry[1]), int(entry[2]), int(entry[3]), int(entry[4]))


## The index of the sheet that holds a picture.
static func sheet_of(picture: String) -> int:
	var entry: Array = Data.PICTURES[picture]
	return int(entry[0])


## The texture of a sheet. It loads the first time. The import settings of the file decide the filter and the format.
static func texture(sheet: int) -> Texture2D:
	if _textures.is_empty():
		_textures.resize(Data.SHEETS.size())
	if _textures[sheet] == null:
		_textures[sheet] = load(Data.SHEETS[sheet]) as Texture2D
	return _textures[sheet]


## Loads every sheet now. The start-up code calls this, so that no sheet loads in the middle of a frame.
static func load_all() -> void:
	for sheet in Data.SHEETS.size():
		texture(sheet)


## Draws a picture with its top left corner at `pos` (rounded to whole pixels). `flip_h` mirrors it in place: it covers the
## same pixels as the plain picture. The left view of a penguin is the right view, mirrored. `tint` multiplies the colours:
## white pictures take any colour.
static func draw(ci: CanvasItem, picture: String, pos: Vector2, flip_h: bool = false, tint: Color = Color.WHITE) -> void:
	var entry: Array = Data.PICTURES[picture]
	var src := Rect2(float(entry[1]), float(entry[2]), float(entry[3]), float(entry[4]))
	var top_left := Vector2(floorf(pos.x + 0.5), floorf(pos.y + 0.5))
	ci.draw_texture_rect_region(texture(int(entry[0])), destination(top_left, src.size, flip_h), src, tint)


## The rectangle on the screen for a picture of `size` with its top left corner at `top_left`. A negative width tells Godot
## to mirror the picture. The rectangle keeps its left edge: Godot 4.7.2 draws the mirrored picture on the same pixels
## (phase G-2 moved it one width to the right, and the room view of phase G-3 showed this).
static func destination(top_left: Vector2, size: Vector2, flip_h: bool) -> Rect2:
	return Rect2(top_left, Vector2(-size.x if flip_h else size.x, size.y))


## Draws a picture with its bottom centre at (x, y): the mockup's drawAt(). Props and cropped pieces use this.
static func draw_at(ci: CanvasItem, picture: String, x: float, bottom: float, tint: Color = Color.WHITE) -> void:
	var size: Vector2i = size_of(picture)
	draw(ci, picture, Vector2(x - floorf(size.x / 2.0), bottom - size.y), false, tint)
