# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# What the view says besides the bar (the bar itself is `bar_art.gd`): a key cap at the lower right of the room while the clock is
# paused or runs at another speed (the look of the key caps in `keycaps` of arenas-art.js), a line for a problem (a wrong option),
# and the list of scenes of the demo mode. Two nodes draw it: the layer "caps" lies under the follow menu, and the layer "menu"
# (the list of scenes) lies over everything.
extends Node2D

const DrawKit := preload("res://art/draw_kit.gd")
const TextArt := preload("res://art/text_art.gd")
const Ui := preload("res://art/ui_kit.gd")

## What to show (see `LiveView.status_info`):
##   "speed"       "paused", or a text such as "2x" (shown only when it is not "1x")
##   "notes"       lines of problems to show (for example a wrong option)
##   "menu"        the names of the scenes of the menu, or an empty list when the menu is closed
##   "menu_index"  the selected line
var info: Dictionary = { }
## "caps" (the key cap and the problem line) or "menu" (the list of scenes).
@export var layer: String = "caps"


func set_info(new_info: Dictionary) -> void:
	info = new_info
	queue_redraw()


func _draw() -> void:
	if info.is_empty():
		return
	if layer == "menu":
		_draw_menu()
		return
	var speed: String = str(info.get("speed", ""))
	if speed != "" and speed != "1.0x" and speed != "1x":
		var w: int = TextArt.width(TextArt.SILK, speed.to_upper()) + 12
		var x: int = 466 - w
		DrawKit.box(self, x, 206, w, 15, Ui.CREAM, Ui.INK, true)
		TextArt.draw(self, speed.to_upper(), x + 6, 210, Ui.INK, TextArt.SILK)
	var notes: Array = info.get("notes", [])
	if not notes.is_empty():
		var text: String = TextArt.fit(TextArt.TINY5, str(notes[0]), 440)
		var nw: int = TextArt.width(TextArt.TINY5, text) + 8
		var nx: int = floori(240.0 - float(nw) / 2.0)
		DrawKit.box(self, nx, 3, nw, 11, Ui.CREAM, Ui.INK, true)
		TextArt.draw(self, text, nx + 4, 5, Color("#e03a3a"))


func _draw_menu() -> void:
	var names: Array = info.get("menu", [])
	if names.is_empty():
		return
	var width: int = 120
	for entry: Variant in names:
		width = maxi(width, TextArt.width(TextArt.TINY5, str(entry)) + 24)
	var height: int = 14 + names.size() * 10
	var x: int = int(240.0 - float(width) / 2.0)
	var y: int = int(116.0 - float(height) / 2.0)
	DrawKit.box(self, x, y, width, height, Ui.PAPER, Ui.INK)
	TextArt.draw(self, "SCENES", x + 6, y + 3, Ui.INK, TextArt.SILK)
	var selected: int = int(info.get("menu_index", 0))
	for i in names.size():
		var line_y: int = y + 14 + i * 10
		if i == selected:
			DrawKit.fill(self, x + 3, line_y - 1, width - 6, 10, Ui.GOLD)
		TextArt.draw(self, str(names[i]), x + 8, line_y, Ui.INK)
