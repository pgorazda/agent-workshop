# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# What the camera view draws besides the rooms (`drawWorld` in arenas-art.js), in screen pixels and not scaled:
#   * "backdrop"  the free places of the pages in view: a dark cell for each place whose arena is not open;
#   * "overlay"   the numbers of the pages, below the pages, when a long move has widened the view (the page that the camera
#                 goes to in gold); and a plain panel over the rows below the room, so that a room that is scaled up a little
#                 in a slide does not show there.
# The view (`src/view/arena_view.gd`) works out the rectangles and the labels and gives them as data. This node only draws.
extends Node2D

const DrawKit := preload("res://art/draw_kit.gd")
const TextArt := preload("res://art/text_art.gd")

const FREE_CELL := Color("#161c2e")
const PANEL := Color("#1b2236")
const DIM := Color("#8b95a8")
const GOLD := Color("#f2c230")
## The room area is 480x232 pixels. The rows below belong to the bar.
const ROOM_WIDTH := 480
const ROOM_HEIGHT := 232
const VIEW_HEIGHT := 270

## "backdrop" or "overlay".
@export var layer: String = "backdrop"
## The free places as screen rectangles (Rect2).
var free_cells: Array[Rect2] = []
## The page numbers: [{ "text": "3", "x": centre x, "y": top y, "gold": bool }].
var page_labels: Array[Dictionary] = []
## The opacity of the page numbers, 0 to 1.
var label_alpha: float = 1.0
## Cover the rows below the room.
var mask_bar: bool = true


func set_cells(cells: Array[Rect2]) -> void:
	free_cells = cells
	queue_redraw()


func set_labels(labels: Array[Dictionary], alpha: float) -> void:
	page_labels = labels
	label_alpha = alpha
	queue_redraw()


func _draw() -> void:
	if layer == "backdrop":
		for cell in free_cells:
			DrawKit.fill(self, cell.position.x, cell.position.y, cell.size.x, cell.size.y, FREE_CELL)
		return
	for label in page_labels:
		var text: String = str(label["text"])
		var x: int = DrawKit.rnd(float(label["x"]) - float(TextArt.width(TextArt.SILK, text)) / 2.0)
		var color: Color = GOLD if bool(label.get("gold", false)) else DIM
		TextArt.draw(self, text, x, float(label["y"]), Color(color, label_alpha), TextArt.SILK)
	if mask_bar:
		DrawKit.fill(self, 0, ROOM_HEIGHT, ROOM_WIDTH, VIEW_HEIGHT - ROOM_HEIGHT, PANEL)
