# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# What the interface draws over the rooms (`overviewLabels` and `drawMenu` of arenas-art.js): in the overview at rest the label
# of each arena (its letter, its agents' chips and its state, at full size), "free" in a free place, an outline round the arena
# under the mouse or one that waits for an approval, and an arrow at each edge that has pages beyond it; and the follow menu
# that opens from the follow switch. It draws what `src/view/interface_model.gd` gives (`ui`).
extends Node2D

const DrawKit := preload("res://art/draw_kit.gd")
const TextArt := preload("res://art/text_art.gd")
const Ui := preload("res://art/ui_kit.gd")
const BarArt := preload("res://art/bar_art.gd")

## What to draw (see `InterfaceModel`).
var ui: Dictionary = { }


func set_ui(new_ui: Dictionary) -> void:
	ui = new_ui
	queue_redraw()


func _draw() -> void:
	if ui.is_empty():
		return
	var t: float = float(ui["now"])
	var overview: Variant = ui["overview"]
	if overview != null:
		_draw_overview(overview as Dictionary, t)
	if ui["menu"] != null:
		_draw_menu(ui["menu"] as Dictionary, t)


func _draw_overview(overview: Dictionary, t: float) -> void:
	var labels: Dictionary = ui["labels"]
	for cell: Dictionary in overview["cells"]:
		var rect: Rect2i = cell["rect"]
		if bool(cell["free"]):
			var word: String = "free"
			TextArt.draw(self, word, rect.position.x + float(rect.size.x) / 2.0 - float(TextArt.width(TextArt.TINY5, word)) / 2.0, rect.position.y + float(rect.size.y) / 2.0 - 3.0, Ui.EDGE)
			continue
		var edge: Variant = null
		if bool(cell["hover"]):
			edge = Ui.CREAM
		elif bool(cell["waiting"]) and Ui.blink_on(t):
			edge = Ui.GOLD
		if edge != null:
			Ui.outline(self, rect.position.x, rect.position.y, rect.size.x, rect.size.y, edge as Color)
		DrawKit.fill(self, rect.position.x + 1, rect.position.y + 1, rect.size.x - 2, 11, Color(Ui.BG, 0.85))
		BarArt.arena_label(self, labels[str(cell["letter"])], rect.position.x + 2, rect.position.y + 2, rect.position.x + rect.size.x - 2, t)
	for arrow: Dictionary in overview["arrows"]:
		var rect: Rect2i = arrow["rect"]
		var color: Variant = BarArt.state_color(str(arrow["state"]), t)
		var shown: Color = Ui.EDGE if color == null else color as Color
		DrawKit.box(self, rect.position.x, rect.position.y, rect.size.x, rect.size.y, Ui.BG, shown, false)
		var ch: String = "<" if int(arrow["side"]) < 0 else ">"
		TextArt.draw(self, ch, rect.position.x + 5 - ceili(float(TextArt.width(TextArt.TINY5, ch)) / 2.0), 54, Ui.TEXT if color == null else color as Color)


## The follow menu: tick what may pull the camera (keys 1 to 6), set the pace ([ and ]), or manual only (0).
func _draw_menu(menu: Dictionary, t: float) -> void:
	var rect: Rect2i = menu["rect"]
	DrawKit.box(self, rect.position.x, rect.position.y, rect.size.x, rect.size.y, Ui.BG, Ui.EDGE, true)
	TextArt.draw(self, "FOLLOW", rect.position.x + 6, rect.position.y + 4, Ui.TEXT, TextArt.SILK)
	var follow: Dictionary = ui["follow"]
	var hover: int = int(menu["hover"])
	var lines: Array = menu["lines"]
	for i in lines.size():
		var line: Dictionary = lines[i]
		var kind: String = str(line["kind"])
		var centre: Vector2i = line["centre"]
		var ly: int = centre.y - 4
		if kind == "pace" or kind == "manual":
			DrawKit.fill(self, rect.position.x + 4, ly - 2, rect.size.x - 8, 1, Ui.EDGE)
		if i == hover:
			DrawKit.fill(self, rect.position.x + 1, ly - 1, rect.size.x - 2, 11, Ui.MENU_HOVER)
		if kind == "pace":
			var held_now: bool = bool(follow["held"]) and Ui.blink_on(t)
			TextArt.draw(self, str(menu["pace_text"]), rect.position.x + 8, ly + 1, Ui.GOLD if held_now else Ui.TEXT)
			for direction: int in [-1, 1]:
				var box: Rect2i = menu["pace_down"] if direction < 0 else menu["pace_up"]
				DrawKit.box(self, box.position.x, box.position.y, 9, 9, Ui.CARD_BG, Ui.EDGE, false)
				var ch: String = "<" if direction < 0 else ">"
				TextArt.draw(self, ch, box.position.x + 4 - ceili(float(TextArt.width(TextArt.TINY5, ch)) / 2.0), ly + 1, Ui.TEXT)
			continue
		var on: bool = bool(line["on"])
		DrawKit.box(self, rect.position.x + 6, ly + 1, 7, 7, Ui.GREEN if on else Ui.BG, Ui.EDGE, false)
		if on:
			DrawKit.bitmap(self, BarArt.CHECK, rect.position.x + 8, ly + 2, Ui.INK)
		if kind != "manual":
			DrawKit.bitmap(self, BarArt.GLYPH[kind], rect.position.x + 17, ly + 2, BarArt.glyph_color(kind))
		var dim: bool = kind != "manual" and bool(follow["manual"])
		TextArt.draw(self, str(BarArt.LABEL_TEXT[kind]), rect.position.x + 24, ly + 1, Ui.DIM if dim else Ui.TEXT)
		var key: String = "0" if kind == "manual" else str(i + 1)
		TextArt.draw(self, key, rect.position.x + rect.size.x - 8 - TextArt.width(TextArt.TINY5, key), ly + 1, Ui.DIM)
