# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# What a room shows of its agents (`drawRoom` in crowd-art.js): the number chips above the penguins, the focus ring and the
# focus label, the approval notices at the sign post (stacked, with "+N"), the "..." bubble of a penguin in a line, and the ribbon
# of a finished turn. The room node (`room_stage_art.gd`) calls these with data. Nothing here reads a clock.
#
# A notice is { "number", "cord", "framework", "session", "target", "x", "approved" }, the oldest first.
extends RefCounted

const DrawKit := preload("res://art/draw_kit.gd")
const TextArt := preload("res://art/text_art.gd")
const Ui := preload("res://art/ui_kit.gd")
const RibbonArt := preload("res://art/ribbon_art.gd")

## The notice at the sign post and the notices stacked behind it.
const NOTICE_W := 128
const NOTICE_H := 56
const NOTICE_FRONT := Vector2i(176, 100)
const NOTICE_BACK := Vector2i(182, 100)
const NOTICE_STEP := 7
## At most this many notices show behind the front one. The "+N" counts them all.
const NOTICE_BEHIND_MAX := 4
## The finished-turn ribbon.
const TURN_LABEL := "TURN COMPLETE!"
const TURN_RIBBON_Y := 74
const TURN_FROM := 0.15
const TURN_TO := 3.2


## The label above the focused penguin: a box with the chip and the text, and a small tail pointing at the penguin at (x, y).
static func focus_tag(ci: CanvasItem, number: int, cord: Color, label: String, color: Color, x: float, y: float) -> void:
	var cw: int = Ui.chip_width(number)
	var w: int = cw + TextArt.rich_width(TextArt.TINY5, label) + 10
	var h: int = 13
	var bx: int = DrawKit.rnd(x - float(w) / 2.0)
	bx = maxi(8, mini(472 - w, bx))
	var by: int = DrawKit.rnd(y) - h
	var tx: int = DrawKit.rnd(x)
	DrawKit.box(ci, bx, by, w, h, Ui.CREAM, Ui.INK)
	DrawKit.fill(ci, tx - 1, by + h - 1, 3, 1, Ui.CREAM)
	DrawKit.px(ci, tx, by + h, Ui.INK)
	DrawKit.px(ci, tx - 2, by + h - 1, Ui.INK)
	DrawKit.px(ci, tx + 2, by + h - 1, Ui.INK)
	DrawKit.px(ci, tx - 1, by + h, Ui.INK)
	DrawKit.px(ci, tx + 1, by + h, Ui.INK)
	Ui.chip(ci, number, bx + 2, by + 2, cord)
	TextArt.rich(ci, [[label, color]], bx + cw + 6, by + 3)


## The tag above the one penguin of a room that has a single agent (`tag` of session-art.js): what it does, with no number. A tail
## points at the penguin at (x, y).
static func solo_tag(ci: CanvasItem, label: String, color: Color, x: float, y: float) -> void:
	var w: int = TextArt.rich_width(TextArt.TINY5, label) + 8
	var bx: int = DrawKit.rnd(x - float(w) / 2.0)
	bx = maxi(10, mini(470 - w, bx))
	var by: int = DrawKit.rnd(y) - 11
	var tx: int = DrawKit.rnd(x)
	DrawKit.box(ci, bx, by, w, 11, Ui.CREAM, Ui.INK)
	DrawKit.fill(ci, tx - 1, by + 10, 3, 1, Ui.CREAM)
	DrawKit.px(ci, tx, by + 11, Ui.INK)
	DrawKit.px(ci, tx - 2, by + 10, Ui.INK)
	DrawKit.px(ci, tx + 2, by + 10, Ui.INK)
	DrawKit.px(ci, tx - 1, by + 11, Ui.INK)
	DrawKit.px(ci, tx + 1, by + 11, Ui.INK)
	TextArt.rich(ci, [[label, color]], bx + 4, by + 2)


## The chip above a penguin that is not focused: its number in the cord colour.
static func number_chip(ci: CanvasItem, number: int, cord: Color, x: float, y: float, h: int = 9) -> void:
	Ui.chip(ci, number, DrawKit.rnd(x) - ceili(float(Ui.chip_width(number)) / 2.0), y, cord, h)


## The focus ring on the floor under a penguin: a soft ellipse and a ring. `t` makes the ring breathe by one pixel.
static func focus_ring(ci: CanvasItem, x: float, y: float, cord: Color, t: float) -> void:
	var beat: int = int(floorf(t * 3.0)) % 2
	DrawKit.ellipse(ci, x, y - 1.0, 14.0, 5.0, cord, 0.22)
	Ui.ring(ci, x, y - 1.0, 13.0 + float(beat), 4.6 + float(beat) * 0.4, cord)


## One notice. The front one shows its agent, its command and the hint; the ones behind show only their top.
static func notice(ci: CanvasItem, entry: Dictionary, bx: int, by: int, front: bool, t: float) -> void:
	DrawKit.box(ci, bx, by, NOTICE_W, NOTICE_H, Ui.PAPER, Ui.INK)
	DrawKit.fill(ci, bx + 1, by + 1, NOTICE_W - 2, 12, Ui.ORANGE)
	DrawKit.fill(ci, bx + 1, by + 13, NOTICE_W - 2, 1, Ui.ORANGE_DK)
	var head: String = "APPROVAL NEEDED"
	TextArt.draw(ci, head, DrawKit.rnd(float(bx) + float(NOTICE_W) / 2.0 - float(TextArt.width(TextArt.SILK, head)) / 2.0), by + 3, Ui.CREAM, TextArt.SILK)
	if not front:
		return
	var number: int = int(entry["number"])
	var cw: int = Ui.chip(ci, number, bx + 6, by + 17, Ui.cord_color(str(entry["cord"])))
	TextArt.draw(ci, "%s  %s" % [entry["framework"], entry["session"]], bx + 6 + cw + 4, by + 18, Ui.INK)
	DrawKit.fill(ci, bx + 6, by + 29, NOTICE_W - 12, 11, Ui.PAPER_DK)
	TextArt.draw(ci, TextArt.fit(TextArt.TINY5, str(entry["target"]), NOTICE_W - 18), bx + 9, by + 31, Ui.INK)
	TextArt.draw(ci, "answer in its terminal", bx + 6, by + 44, Ui.TEXT_DIM_ROOM)
	if Ui.blink_on(t):
		DrawKit.icon(ci, "ask", bx + NOTICE_W - 13, by + 43)


## The notices of the agents that wait for an approval in a room, the oldest first: the oldest in front, the others stacked
## behind it, and a "+N" on the front one. The tail of the front notice points at its penguin.
static func notices(ci: CanvasItem, list: Array[Dictionary], t: float) -> void:
	if list.is_empty():
		return
	var behind: int = mini(list.size() - 1, NOTICE_BEHIND_MAX)
	for k in range(behind, 0, -1):
		notice(ci, list[k], NOTICE_BACK.x + k * NOTICE_STEP, NOTICE_BACK.y - k * NOTICE_STEP, false, t)
	var front: Dictionary = list[0]
	var bx: int = NOTICE_FRONT.x
	var by: int = NOTICE_FRONT.y
	var h: int = NOTICE_H
	var tx: int = DrawKit.rnd(float(front["x"])) - 3
	notice(ci, front, bx, by, true, t)
	if bool(front.get("approved", false)):
		DrawKit.fill(ci, bx + 1, by + 1, NOTICE_W - 2, 12, Ui.GREEN_P)
		DrawKit.fill(ci, bx + 1, by + 13, NOTICE_W - 2, 1, Ui.GREEN_DK)
		var word: String = "APPROVED"
		TextArt.draw(ci, word, DrawKit.rnd(float(bx) + 64.0 - float(TextArt.width(TextArt.SILK, word)) / 2.0), by + 3, Ui.CREAM, TextArt.SILK)
	DrawKit.fill(ci, tx, by + h - 1, 7, 1, Ui.PAPER)
	DrawKit.px(ci, tx - 1, by + h - 1, Ui.INK)
	DrawKit.px(ci, tx + 7, by + h - 1, Ui.INK)
	for i in 4:
		DrawKit.fill(ci, tx + i, by + h + i, 7 - 2 * i, 1, Ui.PAPER)
		DrawKit.px(ci, tx - 1 + i, by + h + i, Ui.INK)
		DrawKit.px(ci, tx + 7 - i, by + h + i, Ui.INK)
	DrawKit.px(ci, tx + 3, by + h + 4, Ui.INK)
	if list.size() > 1:
		var extra: String = "+%d" % (list.size() - 1)
		var ew: int = TextArt.width(TextArt.TINY5, extra)
		DrawKit.box(ci, bx + NOTICE_W - ew - 10, by + 2, ew + 6, 10, Ui.GOLD, Ui.INK, false)
		TextArt.draw(ci, extra, bx + NOTICE_W - ew - 7, by + 3, Ui.INK)


## The bubble of a penguin that waits in a line: a small speech box with three dots.
static func queue_bubble(ci: CanvasItem, x: float, y: float, t: float) -> void:
	var bx: int = DrawKit.rnd(x) + 6
	var by: int = DrawKit.rnd(y) - 40
	DrawKit.box(ci, bx, by, 17, 9, Ui.CREAM, Ui.INK)
	DrawKit.px(ci, bx + 2, by + 9, Ui.INK)
	DrawKit.px(ci, bx + 3, by + 9, Ui.CREAM)
	DrawKit.px(ci, bx + 3, by + 10, Ui.INK)
	Ui.dots(ci, bx + 3, by + 4, t, Ui.INK, Color("#b6c0cc"))


## The ribbon of a finished turn with the agent's number, over the penguin that celebrates. `age` is the time in the cheer.
static func turn_ribbon(ci: CanvasItem, number: int, cord: Color, x: float, age: float) -> void:
	if age <= TURN_FROM or age >= TURN_TO:
		return
	var cw: int = Ui.chip_width(number)
	var label_w: int = TextArt.width(TextArt.SILK, TURN_LABEL)
	var w: int = label_w + 16 + cw + 4
	RibbonArt.draw_ribbon(ci, x + float(cw + 4) / 2.0, float(TURN_RIBBON_Y), TURN_LABEL, Ui.GOLD, Ui.GOLD_DK, Ui.INK)
	Ui.chip(ci, number, DrawKit.rnd(x - float(w) / 2.0 + float(cw + 4) / 2.0) - cw - 2, TURN_RIBBON_Y + 2, cord)
