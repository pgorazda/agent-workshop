# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# The bar under the room (`hud` of session-art.js, `drawTopLine` and `drawCards` of crowd-art.js, `drawBar` of arenas-art.js):
#   "log"     one agent: its last three lines with their state, and a panel with the link, the framework and the counts;
#   "cards"   one arena with several agents: the top line (the link, the counts or who joined, the follow pill, the focus) and a
#             card for each agent;
#   "arenas"  two arenas or more: the tabs of one page, a box for each page, the "+N" of agents that are not shown, the follow
#             switch, and the cards of the arena on screen (or of the one under the mouse).
# The node draws what `src/view/interface_model.gd` gives (`ui`, see the top of that file). It decides nothing: places, states
# and rectangles come from the data. Everything is a function of the data and of the time.
extends Node2D

const DrawKit := preload("res://art/draw_kit.gd")
const TextArt := preload("res://art/text_art.gd")
const Ui := preload("res://art/ui_kit.gd")
const Data := preload("res://art/atlas_data.gd")

## The marks of the follow switch, one for each kind that can pull the camera (4 pixels wide).
const GLYPH: Dictionary = {
	"approval": [".##.", "#..#", "..#.", "....", "..#."],
	"fail": ["#..#", ".##.", ".##.", "#..#"],
	"open": ["####", "#..#", "#..#", "####"],
	"join": ["....", ".#..", "###.", ".#.."],
	"done": ["....", "...#", "#.#.", ".#.."],
	"activity": ["....", ".#..", "#.#.", "...#"],
}
const KINDS: Array[String] = ["approval", "fail", "open", "join", "done", "activity"]
const CHECK: Array[String] = ["...", "..#", "#.#", ".#."]
const LABEL_TEXT: Dictionary = {
	"approval": "approvals", "fail": "failures", "open": "new arenas", "join": "new agents", "done": "finished turns",
	"activity": "busy arenas", "manual": "manual only",
}

## What to draw (see `InterfaceModel`). Empty until the first frame.
var ui: Dictionary = { }


func set_ui(new_ui: Dictionary) -> void:
	ui = new_ui
	queue_redraw()


func _draw() -> void:
	if ui.is_empty():
		return
	var t: float = float(ui["now"])
	DrawKit.fill(self, 0, 232, 480, 38, Ui.BG)
	DrawKit.fill(self, 0, 232, 480, 1, Ui.EDGE)
	DrawKit.fill(self, 0, 233, 480, 1, Ui.EDGE2)
	match str(ui["mode"]):
		"log":
			_draw_log(t)
		"cards":
			_draw_top_line()
			_draw_cards(t)
		_:
			_draw_arenas_bar(t)
			_draw_cards(t)


# ---------------------------------------------------------------- the light of the link

static func light_color(kind: String) -> Color:
	match kind:
		"connected", "demo":
			return Ui.GREEN
		"lost":
			return Ui.RED
	return Ui.GOLD


## The light at the left of the bar: green when connected, gold while it connects or reconnects, red when the link is lost
## (a scripted demo has no link: its light is green and its word says "demo").
func _draw_light(x: float, y: float, glow: bool = false) -> void:
	var connection: Dictionary = ui["connection"]
	var color: Color = light_color(str(connection["kind"]))
	if glow:
		DrawKit.ellipse(self, x, y, 4.0, 4.0, color, 0.25)
	DrawKit.ellipse(self, x, y, 2.5 if glow else 2.2, 2.5 if glow else 2.2, color)


# ---------------------------------------------------------------- one agent: the log

func _draw_log(t: float) -> void:
	var data: Dictionary = ui["log"]
	var lines: Array = data["lines"]
	var connected: bool = str((ui["connection"] as Dictionary)["kind"]) == "connected" or str((ui["connection"] as Dictionary)["kind"]) == "demo"
	if lines.is_empty():
		TextArt.draw(self, "waiting for agent activity", 19, 236, Ui.DIM)
		if connected:
			Ui.dots(self, 326, 238, t)
	for i in lines.size():
		var line: Dictionary = lines[i]
		var y: int = 236 + i * 10
		if str(line["icon"]) != "":
			DrawKit.icon(self, str(line["icon"]), 8, y - 1)
		var state: String = str(line["state"])
		var tool: String = str(line["tool"])
		var target: String = str(line["target"])
		if bool(line["thinking"]):
			TextArt.draw(self, "Thinking", 19, y, Ui.GOLD)
		elif bool(line["error"]):
			TextArt.draw(self, TextArt.fit(TextArt.TINY5, target, 300), 19, y, Ui.RED)
		elif str(line["detail"]) != "":
			TextArt.draw(self, target, 19, y, Ui.GOLD)
			TextArt.draw(self, "   %s" % line["detail"], 19 + TextArt.width(TextArt.TINY5, target), y, Ui.DIM)
		else:
			var used: int = 0
			if tool != "":
				used = TextArt.draw(self, tool, 19, y, Ui.TEXT)
			TextArt.draw(self, TextArt.fit(TextArt.TINY5, "  %s" % target if tool != "" else target, 300 - used), 19 + used, y, Ui.BLUE)
		if state == "run":
			Ui.dots(self, 326, y + 2, t)
		elif state != "" and (state != "WAIT" or Ui.blink_on(t)):
			var color: Color = Ui.GREEN if state == "OK" else (Ui.RED if state == "FAIL" else Ui.GOLD)
			TextArt.draw(self, state, 336 - TextArt.width(TextArt.TINY5, state), y, color)
	DrawKit.fill(self, 344, 236, 1, 30, Ui.EDGE)
	var connection: Dictionary = ui["connection"]
	_draw_light(356.5, 239.5, true)
	TextArt.draw(self, str(connection["word"]), 363, 236, Ui.TEXT if connected else Ui.DIM)
	var agent: Dictionary = data["agent"]
	if not agent.is_empty():
		DrawKit.fill(self, 354, 247, 5, 5, Ui.cord_color(str(agent["cord"])))
		TextArt.draw(self, TextArt.fit(TextArt.TINY5, str(agent["framework"]), 108), 363, 246, Ui.TEXT)
	TextArt.draw(self, "calls %d" % int(data["calls"]), 363, 256, Ui.DIM)
	TextArt.draw(self, "helpers %d" % int(data["helpers"]), 410, 256, Ui.DIM)


# ---------------------------------------------------------------- one arena, several agents: the top line

func _draw_top_line() -> void:
	var top: Dictionary = ui["top"]
	var connection: Dictionary = ui["connection"]
	_draw_light(7.5, 237.5)
	TextArt.draw(self, str(connection["word"]), 12, 234, Ui.TEXT)
	var join: Dictionary = top["join"]
	if not join.is_empty():
		var cw: int = Ui.chip(self, int(join["number"]), 42, 233, Ui.cord_color(str(join["cord"])), 8)
		TextArt.draw(self, "%s %s joined" % [join["framework"], join["session_short"]], 46 + cw, 234, Ui.GREEN)
	else:
		var agents: int = int(top["agents"])
		var helpers: int = int(top["helpers"])
		var text: String = "waiting for agents"
		if agents > 0:
			text = "%d agents · %d helper%s · %d calls" % [agents, helpers, "" if helpers == 1 else "s", int(top["calls"])]
		TextArt.draw(self, text, 42, 234, Ui.DIM)
	var follow: Dictionary = ui["follow"]
	var pill: Rect2i = follow["rect"]
	var word: String = "MANUAL" if bool(follow["manual"]) else "AUTO"
	TextArt.draw(self, "follow", pill.position.x - 26, 234, Ui.DIM)
	DrawKit.box(self, pill.position.x, 233, pill.size.x, 9, Ui.BLUE if bool(follow["manual"]) else Ui.GREEN, Ui.INK, false)
	TextArt.draw(self, word, pill.position.x + 4, 234, Ui.INK)
	var focus: Dictionary = top["focus"]
	if not focus.is_empty():
		var agent: Dictionary = focus["agent"]
		var label: String = str((focus["label"] as Dictionary)["text"]).replace("✗ ", "")
		var chip_w: int = Ui.chip_width(int(agent["number"]))
		var room: int = 476 - (pill.position.x + pill.size.x + 8) - chip_w - 4
		var line: String = TextArt.fit(TextArt.TINY5, "focus: %s %s  %s" % [agent["framework"], focus["session"], label], room)
		var fx: int = 476 - TextArt.width(TextArt.TINY5, line) - chip_w - 4
		Ui.chip(self, int(agent["number"]), fx, 233, Ui.cord_color(str(agent["cord"])), 8)
		TextArt.draw(self, line, fx + chip_w + 4, 234, Ui.GOLD)


# ---------------------------------------------------------------- two arenas or more: the tabs and the boxes

static func state_color(state: String, t: float) -> Variant:
	match state:
		"WAIT":
			if Ui.blink_on(t):
				return Ui.GOLD
		"FAIL":
			return Ui.RED
		"NEW":
			if int(floorf(t / 0.25)) % 2 == 0:
				return Ui.GREEN
	return null


func _draw_arenas_bar(t: float) -> void:
	_draw_light(7.5, 237.5)
	var closing: Variant = ui["closing"]
	if closing != null:
		var shrink: int = DrawKit.rnd(80.0 * (1.0 - float((closing as Dictionary)["k"])))
		DrawKit.fill(self, int((closing as Dictionary)["x"]), 233, shrink, 9, Ui.CARD_BG)
	var tabs: Array = ui["tabs"]
	var labels: Dictionary = ui["labels"]
	for tab: Dictionary in tabs:
		var back: Rect2i = tab["rect"]
		DrawKit.fill(self, back.position.x, 233, back.size.x, 9, Ui.CARD_BG)
	var lit: Variant = ui["lit"]
	if lit != null:
		DrawKit.fill(self, int((lit as Dictionary)["x"]), 233, int((lit as Dictionary)["w"]), 9, Ui.LIT_BG)
		DrawKit.fill(self, int((lit as Dictionary)["x"]), 242, int((lit as Dictionary)["w"]), 1, Ui.CREAM)
	for tab: Dictionary in tabs:
		var place: Rect2i = tab["rect"]
		var letter: String = str(tab["letter"])
		var age: float = float(tab["opened_age"])
		var is_shown: bool = lit != null and int((lit as Dictionary)["x"]) == place.position.x
		if not is_shown and age > 0.3 and age < 1.3 and int(floorf((age - 0.3) / 0.25)) % 2 == 0:
			Ui.outline(self, place.position.x, 233, place.size.x, 9, Ui.GREEN)
		var alpha: float = 1.0 if bool(ui.get("reduced_motion", false)) else clampf(age / 0.3, 0.0, 1.0)
		var state: String = arena_label(self, labels[letter], place.position.x, 233, place.position.x + place.size.x, t, alpha)
		if state == "empty" and age > 1.0:
			Ui.outline(self, place.position.x, 233, place.size.x, 9, Ui.DIM, true)
	_draw_pages(t)
	var follow: Dictionary = ui["follow"]
	var rect: Rect2i = follow["rect"]
	var end: int = int((ui["pages"] as Dictionary)["end"])
	var plus: Variant = ui["unplaced"]
	if plus != null:
		var box: Rect2i = (plus as Dictionary)["rect"]
		DrawKit.box(self, box.position.x, 233, box.size.x, 9, Ui.NEW_BG, Ui.GOLD, false)
		TextArt.draw(self, str((plus as Dictionary)["text"]), box.position.x + 3, 234, Ui.GOLD)
		end = box.position.x + box.size.x
	if end < rect.position.x - 30:
		TextArt.draw(self, "follow", rect.position.x - 26, 234, Ui.DIM)
	draw_follow_switch(self, follow, t)


func _draw_pages(t: float) -> void:
	for item: Dictionary in (ui["pages"] as Dictionary)["items"]:
		var rect: Rect2i = item["rect"]
		var color: Variant = state_color(str(item["state"]), t)
		var has_color: bool = color != null
		if item["kind"] == "arrow":
			var shown: Color = Ui.EDGE
			if has_color:
				shown = color as Color
			DrawKit.box(self, rect.position.x, 233, rect.size.x, 9, Ui.CARD_BG, shown, false)
			var ch: String = "<" if int(item["side"]) < 0 else ">"
			TextArt.draw(self, ch, rect.position.x + ceili(float(rect.size.x - TextArt.width(TextArt.TINY5, ch)) / 2.0), 234, (color as Color) if has_color else Ui.DIM)
			continue
		var is_lit: bool = bool(item["lit"])
		DrawKit.fill(self, rect.position.x, 233, rect.size.x, 9, Ui.LIT_BG if is_lit else Ui.CARD_BG)
		Ui.outline(self, rect.position.x, 233, rect.size.x, 9, (color as Color) if has_color else Ui.EDGE)
		if is_lit:
			DrawKit.fill(self, rect.position.x, 242, rect.size.x, 1, Ui.CREAM)
		var number: String = str(int(item["page"]) + 1)
		TextArt.draw(self, number, rect.position.x + ceili(float(rect.size.x - TextArt.width(TextArt.TINY5, number)) / 2.0), 234, Ui.TEXT if is_lit else Ui.DIM)


## The name of an arena on a plate (wider for a name of two letters), a chip for each agent and its state. When the chips do not
## fit (two-digit numbers in a tab), each agent is a pip in its cord colour instead: the cards, the penguins and the overview still
## show the numbers. `alpha` fades a new tab in. Returns the state of the arena.
static func arena_label(ci: CanvasItem, label: Dictionary, x: int, y: int, right: int, t: float, alpha: float = 1.0) -> String:
	var letter: String = str(label["letter"])
	var index: int = int(label["rug"])
	var letter_w: int = TextArt.width(TextArt.TINY5, letter)
	var plate_w: int = maxi(9, letter_w + 4)
	DrawKit.box(ci, x, y, plate_w, 9, fade(Ui.rug_color(index), alpha), fade(Ui.INK, alpha), false)
	TextArt.draw(ci, letter, x + ceili(float(plate_w - letter_w) / 2.0), y + 1, fade(Ui.WHITE, alpha))
	var cx: int = x + plate_w + 3
	var chips: Array = label["chips"]
	var needed: int = 0
	for chip: Dictionary in chips:
		needed += Ui.chip_width(int(chip["number"])) + 1
	var fits: bool = needed <= right - cx - 24
	for chip: Dictionary in chips:
		var color: Color = Ui.cord_color(str(chip["cord"]))
		if str(chip["state"]) == "WAIT" and Ui.blink_on(t):
			color = Ui.GOLD
		elif str(chip["state"]) == "FAIL":
			color = Ui.RED
		color = fade(color, alpha)
		if fits:
			cx += Ui.chip(ci, int(chip["number"]), cx, y, color, 8) + 1
		else:
			DrawKit.box(ci, cx, y + 1, 5, 7, color, fade(Ui.INK, alpha), false)
			cx += 6
	var state: String = str(label["state"])
	if state == "idle" or state == "empty":
		TextArt.draw(ci, state, right - 2 - TextArt.width(TextArt.TINY5, state), y + 1, fade(Ui.DIM, alpha))
	else:
		Ui.status_text(ci, state, right - 15, y + 1, t)
	return state


static func fade(color: Color, alpha: float) -> Color:
	return Color(color, color.a * alpha)


## The follow switch: in AUTO a mark for each kind that can pull the camera, lit when it is ticked, and gold while the pace holds a
## move back (so that a camera that does not move does not look stuck); in MANUAL the word on blue.
static func draw_follow_switch(ci: CanvasItem, follow: Dictionary, t: float) -> void:
	var rect: Rect2i = follow["rect"]
	if bool(follow["manual"]):
		DrawKit.box(ci, rect.position.x, 233, rect.size.x, 9, Ui.BLUE, Ui.INK, false)
		TextArt.draw(ci, "MANUAL", rect.position.x + 4, 234, Ui.INK)
		return
	var held: bool = bool(follow["held"]) and Ui.blink_on(t)
	DrawKit.box(ci, rect.position.x, 233, rect.size.x, 9, Ui.MANUAL_BG, Ui.GOLD if held else Ui.GREEN, false)
	var kinds: Dictionary = follow["kinds"]
	for i in KINDS.size():
		var kind: String = KINDS[i]
		DrawKit.bitmap(ci, GLYPH[kind], rect.position.x + 2 + i * 5, 235, glyph_color(kind) if bool(kinds.get(kind, false)) else Ui.DOT)


static func glyph_color(kind: String) -> Color:
	match kind:
		"approval":
			return Ui.GOLD
		"fail":
			return Ui.RED
		"open":
			return Ui.GREEN_LT
		"join":
			return Ui.CREAM
		"done":
			return Ui.GREEN
	return Ui.BLUE


# ---------------------------------------------------------------- the cards

func _draw_cards(t: float) -> void:
	var cards: Dictionary = ui["cards"]
	if str(cards["empty_text"]) != "":
		TextArt.draw(self, str(cards["empty_text"]), 10, 252, Ui.DIM)
		return
	if bool(cards["plate"]):
		var plate: Rect2i = cards["plate_rect"]
		var letter: String = str(cards["arena"])
		DrawKit.box(self, plate.position.x, plate.position.y, plate.size.x, plate.size.y, Ui.rug_color(int(cards["rug"])), Ui.INK, false)
		TextArt.draw(self, letter, plate.position.x + ceili(float(plate.size.x - TextArt.width(TextArt.TINY5, letter)) / 2.0), 252, Ui.WHITE)
	for item: Dictionary in cards["items"]:
		_draw_card(item, t)


func _draw_card(item: Dictionary, t: float) -> void:
	var card: Dictionary = item["card"]
	var rect: Rect2i = item["rect"]
	var x0: int = rect.position.x
	var y0: int = rect.position.y
	var cw: int = rect.size.x
	var h: int = rect.size.y
	var state: String = str(card["state"])
	DrawKit.fill(self, x0, y0, cw, h, Ui.CARD_BG)
	var edge: Color = Ui.TEXT if bool(item["focused"]) else (Ui.GOLD if state == "WAIT" and Ui.blink_on(t) else Ui.EDGE)
	DrawKit.fill(self, x0, y0, cw, 1, edge)
	DrawKit.fill(self, x0, y0 + h - 1, cw, 1, edge)
	DrawKit.fill(self, x0, y0, 1, h, edge)
	DrawKit.fill(self, x0 + cw - 1, y0, 1, h, edge)
	var chip_w: int = Ui.chip(self, int(card["number"]), x0 + 3, y0 + 3, Ui.cord_color(str(card["cord"])), 8)
	var helpers: int = int(card["helpers"])
	var extra: String = " +%d" % helpers if helpers > 0 else ""
	var compact: bool = bool(card["compact"])
	if compact:
		TextArt.draw(self, "%s%s" % [card["short"], extra], x0 + 6 + chip_w, y0 + 4, Ui.TEXT)
	else:
		var framework: String = TextArt.fit(TextArt.TINY5, str(card["framework"]), cw - 16 - chip_w)
		TextArt.draw(self, framework, x0 + 6 + chip_w, y0 + 4, Ui.TEXT)
		TextArt.draw(self, "%s%s" % [card["session"], extra], x0 + 10 + chip_w + TextArt.width(TextArt.TINY5, framework), y0 + 4, Ui.DIM)
	if str(card["icon"]) != "":
		DrawKit.icon(self, str(card["icon"]), x0 + 4, y0 + 14)
	if not compact:
		TextArt.draw(self, TextArt.fit(TextArt.TINY5, str(card["target"]), cw - 36), x0 + 14, y0 + 15, Ui.BLUE)
	Ui.status_text(self, state, x0 + cw - 15, y0 + 14 if compact else y0 + 15, t)
