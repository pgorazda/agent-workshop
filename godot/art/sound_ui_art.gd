# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# The sound switch and its menu (`art/sound-ui.js` of the mockup; `src/core/sound_model.gd` keeps the state). The switch sits in the
# top-right corner, styled like the follow switch: a note for the music, gold while a tune plays, and a bell for the event sounds.
# A red slash when all sound is off. Its menu picks a tune (1 to 4, 0 for none) and turns the event sounds on or off (E). A short
# note under the switch confirms a change.
#
# The node draws what `SoundModel.ui()` gives (`state`). The places and the hit tests are static: they are in the pixels of the
# 480x270 viewport, and the input of the view calls `hit` with the point of the mouse.
extends Node2D

const DrawKit := preload("res://art/draw_kit.gd")
const TextArt := preload("res://art/text_art.gd")
const Ui := preload("res://art/ui_kit.gd")

const NOTE: Array[String] = ["..##.", "..#.#", "..#..", "###..", "##..."]
const BELL: Array[String] = ["..#..", ".###.", ".###.", "#####", "..#.."]
const TICK: Array[String] = ["...", "..#", "#.#", ".#."]

const PILL := Rect2i(453, 3, 23, 9)
const MENU_W := 150
const MENU_X := 476 - MENU_W
const MENU_Y := 15
## The height of a row of the menu.
const ROW_H := 11

## What to draw (see `SoundModel.ui`). Empty until the first frame.
var state: Dictionary = { }


func set_state(new_state: Dictionary) -> void:
	if new_state == state:
		return
	state = new_state
	queue_redraw()


# ---------------------------------------------------------------- the places

## The top of the text of the row `i` of the menu: the tunes, then "no music".
static func row_y(i: int) -> int:
	return MENU_Y + 27 + i * ROW_H


## The top of the text of the line of the event sounds, when the menu has `tunes` tunes.
static func events_y(tunes: int) -> int:
	return row_y(tunes) + ROW_H + 5 + 10


static func menu_rect(tunes: int) -> Rect2i:
	return Rect2i(MENU_X, MENU_Y, MENU_W, events_y(tunes) - MENU_Y + 13 + 4 + 12)


## What is at a point of the 480x270 viewport. A Dictionary with a "kind": "pill" (the switch), "tune" (with `tune`: the name, or ""
## for no music), "events", "menu" (inside the open menu, on nothing) or "none". `shown` has "open" and "tunes" (the list of tunes).
static func hit(point: Vector2, shown: Dictionary) -> Dictionary:
	var p: Vector2i = Vector2i(point)
	if PILL.has_point(p):
		return { "kind": "pill" }
	if not bool(shown.get("open", false)):
		return { "kind": "none" }
	var tunes: Array = shown.get("tunes", [])
	if not menu_rect(tunes.size()).has_point(p):
		return { "kind": "none" }
	for i in tunes.size() + 1:
		var y: int = row_y(i)
		if p.y >= y - 1 and p.y < y + ROW_H - 1:
			return { "kind": "tune", "tune": str((tunes[i] as Dictionary)["name"]) if i < tunes.size() else "" }
	var ey: int = events_y(tunes.size())
	if p.y >= ey - 1 and p.y < ey + ROW_H - 1:
		return { "kind": "events" }
	return { "kind": "menu" }


# ---------------------------------------------------------------- the drawing

func _draw() -> void:
	if state.is_empty():
		return
	_draw_pill()
	if bool(state["open"]):
		_draw_menu()
	elif str(state["toast"]) != "":
		_draw_toast(str(state["toast"]))


func _draw_pill() -> void:
	var on: bool = bool(state["on"])
	var edge: Color = Ui.GOLD if bool(state["open"]) else (Ui.GREEN if on else Ui.EDGE)
	DrawKit.box(self, PILL.position.x, PILL.position.y, PILL.size.x, PILL.size.y, Ui.BG, edge, false)
	DrawKit.bitmap(self, NOTE, PILL.position.x + 3, PILL.position.y + 2, Ui.GOLD if on and str(state["tune"]) != "" else Ui.DOT)
	DrawKit.bitmap(self, BELL, PILL.position.x + 14, PILL.position.y + 2, Ui.CREAM if on and bool(state["events"]) else Ui.DOT)
	if not on:
		for i in 7:
			DrawKit.px(self, PILL.position.x + 8 + i, PILL.position.y + 1 + i, Ui.RED)


func _draw_menu() -> void:
	var tunes: Array = state["tunes"]
	var rect: Rect2i = menu_rect(tunes.size())
	var x: int = rect.position.x
	var y: int = rect.position.y
	var w: int = rect.size.x
	DrawKit.box(self, x, y, w, rect.size.y, Ui.BG, Ui.EDGE, true)
	TextArt.draw(self, "SOUND", x + 6, y + 4, Ui.TEXT, TextArt.SILK)
	TextArt.draw(self, "S", x + w - 8 - TextArt.width(TextArt.TINY5, "S"), y + 4, Ui.DIM)
	TextArt.draw(self, "music", x + 6, y + 17, Ui.DIM)
	var hover: int = int(state["hover"])
	for i in tunes.size() + 1:
		var row_top: int = row_y(i)
		var entry: Dictionary = tunes[i] as Dictionary if i < tunes.size() else { "name": "", "label": "no music", "about": "" }
		var key: String = str(i + 1) if i < tunes.size() else "0"
		var chosen: bool = str(state["tune"]) == str(entry["name"])
		if hover == i:
			DrawKit.fill(self, x + 1, row_top - 1, w - 2, ROW_H, Ui.MENU_HOVER)
		DrawKit.box(self, x + 6, row_top + 1, 7, 7, Ui.BG, Ui.GOLD if chosen else Ui.EDGE, false)
		if chosen:
			DrawKit.fill(self, x + 8, row_top + 3, 3, 3, Ui.GOLD)
		TextArt.draw(self, str(entry["label"]), x + 18, row_top + 1, Ui.GOLD if chosen else Ui.TEXT)
		if str(entry["about"]) != "":
			TextArt.draw(self, str(entry["about"]), x + 68, row_top + 1, Ui.DIM)
		TextArt.draw(self, key, x + w - 8 - TextArt.width(TextArt.TINY5, key), row_top + 1, Ui.DIM)
	var line_y: int = row_y(tunes.size()) + ROW_H
	DrawKit.fill(self, x + 4, line_y + 1, w - 8, 1, Ui.EDGE)
	var ly: int = line_y + 5
	TextArt.draw(self, "event sounds", x + 6, ly, Ui.DIM)
	ly = events_y(tunes.size())
	var events: bool = bool(state["events"])
	if hover == 5:
		DrawKit.fill(self, x + 1, ly - 1, w - 2, ROW_H, Ui.MENU_HOVER)
	DrawKit.box(self, x + 6, ly + 1, 7, 7, Ui.GREEN if events else Ui.BG, Ui.EDGE, false)
	if events:
		DrawKit.bitmap(self, TICK, x + 8, ly + 2, Ui.INK)
	DrawKit.bitmap(self, BELL, x + 17, ly + 2, Ui.CREAM if events else Ui.DOT)
	TextArt.draw(self, "tink, bell, flop, chime, fanfare", x + 25, ly + 1, Ui.TEXT if events else Ui.DIM)
	TextArt.draw(self, "E", x + w - 8 - TextArt.width(TextArt.TINY5, "E"), ly + 1, Ui.DIM)
	ly += 13
	DrawKit.fill(self, x + 4, ly, w - 8, 1, Ui.EDGE)
	ly += 4
	TextArt.draw(self, "M: all sound on or off", x + 6, ly, Ui.DIM)


func _draw_toast(text: String) -> void:
	var w: int = TextArt.width(TextArt.TINY5, text) + 12
	var x: int = 476 - w
	DrawKit.box(self, x, 15, w, 11, Ui.BG, Ui.EDGE, true)
	TextArt.draw(self, text, x + 6, 17, Ui.TEXT)
