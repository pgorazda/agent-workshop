# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# The room: the baked picture of a room for each rug colour, and its sign. The baked room has an empty sign board.
# The sign changes with the arena letter, so the text and the plate are drawn here, with the arithmetic of room()
# in look.js. The baker checks this arithmetic: a baked room plus the sign is the same picture as room() draws.
extends RefCounted

const Atlas := preload("res://art/atlas.gd")
const DrawKit := preload("res://art/draw_kit.gd")
const TextArt := preload("res://art/text_art.gd")
const Data := preload("res://art/atlas_data.gd")

const CREAM := Color("#f7f9fc")
const SIGN_CENTER := 62
const SIGN_TEXT_Y := 15
const PLATE_Y := 14
const PLATE_H := 11
const PLATE_MIN_W := 11
const SOLO_TEXT := "AGENT WORKSHOP"
const ARENA_TEXT := "ARENA"


## The name of the picture of the room for a rug colour ("red", "cobalt", "emerald", "yellow", "teal").
static func picture_name(rug: String) -> String:
	return "room/%s" % rug


## The colours of a rug: {"name", "color", "dark"}. An unknown name gives the first rug.
static func rug_named(rug: String) -> Dictionary:
	for entry in Data.RUGS:
		if entry["name"] == rug:
			return entry
	return Data.RUGS[0]


## The rug of an arena by its number: A is 0. The colours repeat every five arenas.
static func rug_of_arena(index: int) -> Dictionary:
	return Data.RUGS[index % Data.RUGS.size()]


## Where the sign draws its parts. An empty letter is the sign of the single room ("AGENT WORKSHOP").
static func sign_layout(letter: String) -> Dictionary:
	if letter.is_empty():
		var w: int = TextArt.width(TextArt.SILK, SOLO_TEXT)
		return {"solo": true, "text_x": DrawKit.rnd(SIGN_CENTER - w / 2.0), "text_y": SIGN_TEXT_Y, "text_w": w}
	var arena_w: int = TextArt.width(TextArt.SILK, ARENA_TEXT)
	var letter_w: int = TextArt.width(TextArt.SILK, letter)
	var plate_w: int = maxi(PLATE_MIN_W, letter_w + 6)
	var x: int = DrawKit.rnd(SIGN_CENTER - (arena_w + 4 + plate_w) / 2.0)
	var plate_x: int = x + arena_w + 4
	return {
		"solo": false,
		"text_x": x, "text_y": SIGN_TEXT_Y, "text_w": arena_w,
		"plate_x": plate_x, "plate_y": PLATE_Y, "plate_w": plate_w, "plate_h": PLATE_H,
		"letter_x": plate_x + floori((plate_w - letter_w) / 2.0), "letter_y": SIGN_TEXT_Y + 1, "letter_w": letter_w,
	}


## Draws the sign on a room whose top left corner is at `origin`.
static func draw_sign(ci: CanvasItem, rug: String, letter: String, origin: Vector2 = Vector2.ZERO) -> void:
	var layout: Dictionary = sign_layout(letter)
	var text_pos := origin + Vector2(float(layout["text_x"]), float(layout["text_y"]))
	if layout["solo"]:
		TextArt.draw(ci, SOLO_TEXT, text_pos.x, text_pos.y, CREAM, TextArt.SILK)
		return
	TextArt.draw(ci, ARENA_TEXT, text_pos.x, text_pos.y, CREAM, TextArt.SILK)
	var color: Color = Color.html(rug_named(rug)["color"])
	var plate_pos := origin + Vector2(float(layout["plate_x"]), float(layout["plate_y"]))
	DrawKit.box(ci, plate_pos.x, plate_pos.y, int(layout["plate_w"]), int(layout["plate_h"]), color, DrawKit.INK, false)
	var letter_pos := origin + Vector2(float(layout["letter_x"]), float(layout["letter_y"]))
	TextArt.draw(ci, letter, letter_pos.x, letter_pos.y, CREAM, TextArt.SILK)


## Draws a room with its sign. The top left corner is at `pos`. Use an empty `letter` for the single room.
static func draw_room(ci: CanvasItem, rug: String, letter: String, pos: Vector2 = Vector2.ZERO) -> void:
	Atlas.draw(ci, picture_name(rug), pos)
	draw_sign(ci, rug, letter, pos)
