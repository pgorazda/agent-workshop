# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# The mouse pointer and the key caps of a scripted demonstration (`drawCursor` of crowd-art.js and `keycaps` of arenas-art.js). A
# recording has no real person, so the scenes script the pointer and the keys, and the client draws them over the picture: an arrow that
# moves along a path, a gold ring that spreads at each click, and a key cap that shows for a moment when a key is pressed. They are
# drawn only in recording mode and in demo mode. `core/recording.gd` works out what to show at a time; this node draws it.
extends Node2D

const DrawKit := preload("res://art/draw_kit.gd")
const TextArt := preload("res://art/text_art.gd")
const Ui := preload("res://art/ui_kit.gd")

## The arrow, row by row: "k" is the dark outline and "w" is white.
const ARROW: Array[String] = [
	"k.......", "kk......", "kwk.....", "kwwk....", "kwwwk...", "kwwwwk..", "kwwwwwk.", "kwwwwwwk", "kwwwkkkk", "kwwk....", "kkk.....",
]
## The ring of a click spreads for this long (seconds), from a radius of 2 pixels, by 20 pixels a second.
const RING_SECONDS := 0.3
const RING_SPEED := 20.0
## A key cap shows for this long. It looks pressed for the first part of it.
const KEY_SECONDS := 1.1
const KEY_DOWN_SECONDS := 0.15
## The right edge of a key cap, and its top.
const KEY_RIGHT := 466
const KEY_TOP := 206

## What to draw: { "pointers": [{ "x", "y", "ring_ages": [seconds since a click] }], "keys": [{ "label", "age" }] }.
var state: Dictionary = { }


func set_state(new_state: Dictionary) -> void:
	if new_state == state:
		return
	state = new_state
	queue_redraw()


func _draw() -> void:
	for key: Dictionary in state.get("keys", []):
		key_cap(self, str(key["label"]), float(key["age"]))
	for pointer: Dictionary in state.get("pointers", []):
		pointer_at(self, int(pointer["x"]), int(pointer["y"]), pointer.get("ring_ages", []))


## The arrow with its tip at (x, y), and a ring for each click that is less than `RING_SECONDS` old.
static func pointer_at(ci: CanvasItem, x: int, y: int, ring_ages: Array) -> void:
	for age: Variant in ring_ages:
		var a: float = float(age)
		if a >= 0.0 and a < RING_SECONDS:
			Ui.ring(ci, x, y, 2.0 + a * RING_SPEED, 2.0 + a * RING_SPEED, Ui.GOLD)
	for j in ARROW.size():
		var row: String = ARROW[j]
		for i in row.length():
			var ch: String = row[i]
			if ch != ".":
				DrawKit.px(ci, x + i, y + j, Ui.INK if ch == "k" else Ui.WHITE)


## The key cap of a key that was pressed `age` seconds ago. Nothing is drawn before the press or after `KEY_SECONDS`.
static func key_cap(ci: CanvasItem, label: String, age: float) -> void:
	if age < 0.0 or age > KEY_SECONDS:
		return
	var rect: Rect2i = key_rect(label, age)
	DrawKit.box(ci, rect.position.x, rect.position.y, rect.size.x, rect.size.y, Ui.CREAM, Ui.INK, age >= KEY_DOWN_SECONDS)
	TextArt.draw(ci, label, rect.position.x + 6, rect.position.y + 4, Ui.INK, TextArt.SILK)


## The place of the key cap: it is one pixel lower while it is pressed.
static func key_rect(label: String, age: float) -> Rect2i:
	var w: int = TextArt.width(TextArt.SILK, label) + 12
	return Rect2i(KEY_RIGHT - w, KEY_TOP + (1 if age < KEY_DOWN_SECONDS else 0), w, 15)
