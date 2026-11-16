extends RefCounted
## What the interface shows and where, for one frame (phase G-6). It reads the director, the camera and the log model and gives
## one Dictionary (`ui`) that the art nodes draw (`art/bar_art.gd`, `art/overview_art.gd`) and that the hit tests read. It has no
## drawing call.
##
## `ui` has these keys:
##   "mode"         "log" (one arena with one agent: the last lines), "cards" (one arena: the top line and the cards) or
##                  "arenas" (two arenas or more: the tabs and the page boxes, and the cards)
##   "now"          the simulation time
##   "connection"   { kind: "connected"|"connecting"|"reconnecting"|"lost"|"demo", word } (set by the caller)
##   "log"          the lines of the one agent, for the mode "log"
##   "top"          for the mode "cards": the counts, the join notice and the focus text
##   "labels"       letter -> { letter, rug, chips: [{ number, cord, state }], state }: what a tab or a cell says of an arena
##   "tabs"         the tabs of the page of the list: [{ letter, slot, rect, opened_age }]
##   "lit"          where the lit tab is, { x, w }, or null
##   "closing"      a tab that shrinks away: { slot, k }, or null
##   "pages"        { items: [{ kind, side, page, pages, rect, lit, state }], end }
##   "unplaced"     the agents that are not shown: { n, rect } or null
##   "follow"       { rect, manual, kinds: { kind: bool }, held }
##   "menu"         the follow menu when it is open: { rect, lines: [{ kind, on, rect }], pace_text, hover }, else null
##   "cards"        { arena, plate, empty_text, items: [{ card, rect, focused }] } (the row of cards)
##   "overview"     in the overview at rest: { cells: [{ letter, rect, free, hover, waiting }], arrows: [{ side, rect, state }] }, else null
##   "penguins"     for the hit test: [{ number, arena, rect }] (the screen rectangles of the penguins of the arena on screen)
##   "hover"        the letter of the arena under the mouse (a tab or a cell), or ""

const ArenaRules := preload("res://src/core/arena_rules.gd")
const BarLayout := preload("res://src/core/bar_layout.gd")
const LogModel := preload("res://src/core/log_model.gd")
const ArenaView := preload("res://src/view/arena_view.gd")
const TextArt := preload("res://art/text_art.gd")

## "NEW": a page whose first arena opened this lately blinks green.
const NEW_PAGE_SECONDS := 1.3
## The size of the click area round a penguin: from 14 px left to 14 px right of its foot, 52 px up to 3 px down.
const PENGUIN_HIT := Rect2(-14.0, -52.0, 28.0, 55.0)
## After this long without a connection, "reconnecting" becomes "lost".
const LOST_AFTER := 10.0

## The follow menu is open.
var menu_open: bool = false
## The mouse position in the pixels of the viewport. Far away when there is no mouse.
var hover_point: Vector2 = Vector2(-100.0, -100.0)
## Show the top line and the cards also for one arena with one agent (the scene `tour` of phase G-8 explains the bar of several agents
## from the start). Without it, one agent gets the log.
var force_cards: bool = false
## What the person is told about the link, for the next build: { kind, word }.
var connection: Dictionary = { "kind": "demo", "word": "demo" }
## The last result of `build()`.
var ui: Dictionary = { }

var _manual_width: int = 0
## The state of each arena, worked out once in a build (the page boxes need it for every arena of every page).
var _state_cache: Dictionary = { }
var _page_letters: Dictionary = { }
var _log: LogModel = null


func _init() -> void:
	_manual_width = TextArt.width(TextArt.TINY5, "MANUAL") + 8


## The state of the link for the bar. `open` is true when the socket is open, `down_for` is the wall-clock seconds without an open
## socket (since the start for a client that never connected). Demo mode has no socket.
static func connection_of(demo: bool, open: bool, ever_open: bool, down_for: float) -> Dictionary:
	if demo:
		return { "kind": "demo", "word": "demo" }
	if open:
		return { "kind": "connected", "word": "online" }
	if down_for >= LOST_AFTER:
		return { "kind": "lost", "word": "offline" }
	return { "kind": "reconnecting" if ever_open else "connecting", "word": "reconnecting" if ever_open else "connecting" }


## The state of an agent as a tab or a chip shows it: "WAIT", "FAIL", "run", "DONE" or "idle".
static func tab_state_of(card_state: String) -> String:
	match card_state:
		"WAIT", "FAIL", "run", "DONE":
			return card_state
	return "idle"


## Builds `ui` for the time `now`.
func build(director: RefCounted, camera: RefCounted, now: float) -> Dictionary:
	var activity_log: LogModel = director.activity_log
	var letters: Array[String] = camera.letters
	var pose: ArenaRules.Pose = camera.pose_at_time(now)
	var moving: bool = pose.k < 1.0
	var early: bool = moving and pose.k < 0.5
	var view_kind: String = camera.view.kind
	var arena: String = camera.arena_shown()
	var page: int = camera.page_shown()
	var from_view: ArenaRules.View = camera.move.from_view
	var arena_from: String = from_view.arena if from_view.kind == "arena" else ""
	var page_from: int = int(ArenaRules.place_of(arena_from)["page"]) if from_view.kind == "arena" and arena_from != "" else (from_view.page if from_view.kind == "page" else page)
	var list_page: int = page_from if early else page
	ui = { "now": now, "connection": connection, "hover": "" }

	var hovered: String = _hovered(letters, view_kind, moving, list_page)
	ui["hover"] = hovered
	# the label of an arena (chips and state) is only needed for the tabs of the page of the list and the cells of the page in the overview
	_state_cache.clear()
	_page_letters.clear()
	_log = activity_log
	var labels: Dictionary = { }
	for letter in letters:
		var place_page: int = int(ArenaRules.place_of(letter)["page"])
		if place_page == list_page or place_page == page:
			labels[letter] = _label(activity_log, letter, camera)
	ui["labels"] = labels

	ui["reduced_motion"] = bool(camera.o.get("reduced_motion", false))

	var single: bool = letters.size() <= 1
	if single:
		menu_open = false
	var sole_count: int = activity_log.agent_count(letters[0] if not letters.is_empty() else "")
	# the follow switch: the switch with its menu for two arenas or more, a pill with the word for one arena with several agents,
	# and none for one agent
	var manual: bool = camera.mode == "MANUAL"
	var follow_rect: Rect2i = BarLayout.follow_rect(manual, _manual_width)
	var pill: bool = false
	if single:
		pill = true
		follow_rect = Rect2i(BarLayout.PILL_X, BarLayout.ROW_Y, TextArt.width(TextArt.TINY5, "MANUAL" if manual else "AUTO") + 8, BarLayout.ROW_H)
		if sole_count <= 1 and not force_cards:
			follow_rect = Rect2i()
	ui["follow"] = { "rect": follow_rect, "manual": manual, "kinds": camera.follow, "held": camera.held, "pace": camera.pace, "pill": pill }
	ui["menu"] = null
	if menu_open and not single:
		ui["menu"] = _menu(camera, now)

	if single:
		var agents: Array[Dictionary] = activity_log.agents_in(letters[0] if not letters.is_empty() else "")
		if agents.size() <= 1 and not force_cards:
			ui["mode"] = "log"
			var sole: Dictionary = agents[0] if not agents.is_empty() else { }
			ui["log"] = {
				"lines": activity_log.lines_of(str(sole["key"])) if not sole.is_empty() else [] as Array[Dictionary],
				"agent": sole,
				"calls": activity_log.calls,
				"helpers": activity_log.helper_count(),
			}
		else:
			ui["mode"] = "cards"
			ui["top"] = _top_line(activity_log, camera, letters[0] if not letters.is_empty() else "", now)
	else:
		ui["mode"] = "arenas"

	ui["tabs"] = []
	ui["lit"] = null
	ui["closing"] = null
	ui["pages"] = { "items": [] as Array[Dictionary], "end": BarLayout.tab_x(4) - BarLayout.TAB_GAP }
	ui["unplaced"] = null
	if not single:
		_build_tabs(director, camera, now, list_page, arena, arena_from, pose, moving)
		_build_pages(director, camera, now, list_page)
	ui["cards"] = _cards(director, camera, activity_log, now, hovered, early, page, view_kind, arena, arena_from)
	ui["overview"] = null
	if view_kind == "page" and not moving and not single:
		ui["overview"] = _overview(director, camera, now, page, hovered)
	ui["penguins"] = _penguin_hits(director, pose, view_kind, arena)
	return ui


# ---------------------------------------------------------------- the pieces

func _hovered(letters: Array[String], view_kind: String, moving: bool, list_page: int) -> String:
	if letters.size() <= 1:
		return ""
	var p: Vector2 = hover_point
	if view_kind == "page":
		if moving:
			return ""
		for slot in 4:
			if BarLayout.CELLS[slot].has_point(Vector2i(p)):
				var letter: String = ArenaRules.name_of(list_page * 4 + slot)
				return letter if letters.has(letter) else ""
		return ""
	if p.y >= float(BarLayout.ROW_Y) and p.y < float(BarLayout.ROW_Y + BarLayout.ROW_H):
		for slot in 4:
			if BarLayout.tab_rect(slot).has_point(Vector2i(p)):
				var letter: String = ArenaRules.name_of(list_page * 4 + slot)
				return letter if letters.has(letter) else ""
	return ""


## What a tab or a cell says of an arena: the rug, a chip for each agent and the state (the most urgent of its agents).
func _label(activity_log: LogModel, letter: String, _camera: RefCounted) -> Dictionary:
	var chips: Array[Dictionary] = []
	var states: Array = []
	for card in activity_log.cards(letter):
		var state: String = tab_state_of(str(card["state"]))
		chips.append({ "number": card["number"], "cord": card["cord"], "state": state })
		states.append(state)
	return { "letter": letter, "rug": ArenaRules.index_of(letter), "chips": chips, "state": ArenaRules.tab_state(states), "states": states }


func _build_tabs(director: RefCounted, camera: RefCounted, now: float, list_page: int, arena: String, arena_from: String, pose: ArenaRules.Pose, moving: bool) -> void:
	var tabs: Array[Dictionary] = []
	for slot in 4:
		var letter: String = ArenaRules.name_of(list_page * 4 + slot)
		if camera.letters.has(letter):
			tabs.append({ "letter": letter, "slot": slot, "rect": BarLayout.tab_rect(slot), "opened_age": now - director.opened_at_of(letter) })
	ui["tabs"] = tabs
	if camera.view.kind == "arena" and int(ArenaRules.place_of(arena)["page"]) == list_page:
		var lit_x: int = BarLayout.tab_x(int(ArenaRules.place_of(arena)["slot"]))
		if moving and arena_from != "" and int(ArenaRules.place_of(arena_from)["page"]) == list_page:
			var from_x: int = BarLayout.tab_x(int(ArenaRules.place_of(arena_from)["slot"]))
			lit_x = int(roundf(float(from_x) + float(lit_x - from_x) * ArenaRules.ease_k(pose.k)))
		ui["lit"] = { "x": lit_x, "w": BarLayout.TAB_W }
	for closed: Dictionary in director.recently_closed:
		var age: float = now - float(closed["t"])
		if age >= 0.0 and age < 0.3 and int(ArenaRules.place_of(str(closed["letter"]))["page"]) == list_page:
			var slot: int = int(ArenaRules.place_of(str(closed["letter"]))["slot"])
			ui["closing"] = { "slot": slot, "x": BarLayout.tab_x(slot), "k": ArenaRules.ease_k(age / 0.3) }


func _build_pages(director: RefCounted, camera: RefCounted, now: float, list_page: int) -> void:
	var list: Dictionary = BarLayout.page_list(camera.pages, list_page)
	var items: Array[Dictionary] = []
	for entry: Dictionary in list["items"]:
		var item: Dictionary = entry.duplicate()
		item["lit"] = entry["kind"] == "box" and int(entry["page"]) == list_page
		item["state"] = _pages_state(director, camera, entry["pages"], now)
		items.append(item)
	var end: int = int(list["end"])
	var unplaced: int = director.unplaced_count()
	var plus: Variant = null
	if unplaced > 0:
		var text: String = "+%d" % unplaced
		var width: int = TextArt.width(TextArt.TINY5, text) + 6
		plus = { "n": unplaced, "text": text, "rect": Rect2i(end + 3, BarLayout.ROW_Y, width, BarLayout.ROW_H) }
	ui["pages"] = { "items": items, "end": end }
	ui["unplaced"] = plus


## The most urgent state on some pages: "WAIT" or "FAIL", else "NEW" for a page whose first arena just opened, else the
## state of the arenas ("run", "DONE", "idle", "empty").
func _pages_state(director: RefCounted, camera: RefCounted, pages: Array, now: float) -> String:
	var states: Array = []
	var newest: float = -INF
	for p: int in pages:
		for letter: String in _letters_of_page(camera, p):
			states.append(_state_of(letter))
	var state: String = ArenaRules.tab_state(states)
	if state == "WAIT" or state == "FAIL":
		return state
	for p: int in pages:
		var first: float = INF
		for letter: String in _letters_of_page(camera, p):
			first = minf(first, director.opened_at_of(letter))
		var age: float = now - first
		if age >= 0.0 and age < NEW_PAGE_SECONDS:
			newest = age
	return "NEW" if newest > -INF else state


## The open arenas of a page. The pages of the arenas are worked out once in a build.
func _letters_of_page(camera: RefCounted, page: int) -> Array:
	if _page_letters.is_empty():
		for letter: String in camera.letters:
			var p: int = int(ArenaRules.place_of(letter)["page"])
			if not _page_letters.has(p):
				_page_letters[p] = []
			(_page_letters[p] as Array).append(letter)
	return _page_letters.get(page, [])


## The most urgent state of the agents of an arena. Worked out once for each arena in a build.
func _state_of(letter: String) -> String:
	if _state_cache.has(letter):
		return str(_state_cache[letter])
	var list: Array = []
	for card in _log.agents_in(letter):
		list.append(tab_state_of(str(card["state"])))
	var state: String = ArenaRules.tab_state(list)
	_state_cache[letter] = state
	return state


func _menu(camera: RefCounted, _now: float) -> Dictionary:
	var lines: Array[Dictionary] = []
	for i in BarLayout.MENU_LINES:
		var kind: String = "pace" if i == BarLayout.PACE_LINE else ("manual" if i == BarLayout.MANUAL_LINE else ArenaRules.KINDS[i])
		var on: bool = camera.mode == "MANUAL" if kind == "manual" else (false if kind == "pace" else bool(camera.follow.get(kind, false)))
		lines.append({ "kind": kind, "on": on, "rect": BarLayout.menu_line_rect(i), "centre": BarLayout.menu_line_centre(i) })
	var window: float = float(camera.o["pace_window"])
	var pace_text: String = "moves: no limit"
	if not is_inf(camera.pace):
		pace_text = "at most %d moves / %d s" % [int(roundf(camera.pace * window)), int(window)]
	var hover_index: int = -1
	for i in lines.size():
		if (lines[i]["rect"] as Rect2i).has_point(Vector2i(hover_point)):
			hover_index = i
	return {
		"rect": BarLayout.MENU, "lines": lines, "pace_text": pace_text, "hover": hover_index, "pace_window": window,
		"pace_down": BarLayout.pace_arrow_rect(-1), "pace_up": BarLayout.pace_arrow_rect(1),
	}


func _top_line(activity_log: LogModel, camera: RefCounted, letter: String, now: float) -> Dictionary:
	var join: Dictionary = activity_log.recent_join(now).duplicate()
	if not join.is_empty():
		join["session_short"] = LogModel.short_session(str(join["session"]))
	var focus_number: Variant = camera.focus_of(letter)
	var focus: Dictionary = { }
	if focus_number != null:
		for a in activity_log.agents_in(letter):
			if a["number"] == focus_number:
				focus = { "agent": a, "label": activity_log.focus_label(str(a["key"])), "session": LogModel.short_session(str(a["session"])) }
	return {
		"join": join, "agents": activity_log.agent_count(), "helpers": activity_log.helper_count(), "calls": activity_log.calls, "focus": focus,
	}


## The row of cards: the arena on screen, the arena under the mouse (with its letter in front), the arena that the overview
## opened from, or the first arena of the page.
func _cards(director: RefCounted, camera: RefCounted, activity_log: LogModel, now: float, hovered: String, early: bool, page: int, view_kind: String, arena: String, arena_from: String) -> Dictionary:
	var letters: Array[String] = camera.letters
	var list_page: int = int(ArenaRules.place_of(arena_from)["page"]) if early and arena_from != "" else page
	var overview: bool = view_kind == "page" or (early and arena_from == "")
	var mine: String = str(camera.view.origin) if view_kind == "page" else arena
	var chosen: String = hovered
	if chosen == "" and overview:
		if mine != "" and letters.has(mine) and int(ArenaRules.place_of(mine)["page"]) == list_page:
			chosen = mine
		else:
			for l in letters:
				if int(ArenaRules.place_of(l)["page"]) == list_page:
					chosen = l
					break
	if chosen == "":
		chosen = arena_from if early and arena_from != "" and letters.has(arena_from) else arena
	if chosen == "" and not letters.is_empty():
		chosen = letters[0]
	var out: Dictionary = { "arena": chosen, "rug": ArenaRules.index_of(chosen) if chosen != "" else 0, "plate": false, "empty_text": "", "items": [] as Array[Dictionary], "plate_rect": Rect2i() }
	if chosen == "":
		return out
	var cards: Array[Dictionary] = activity_log.cards(chosen)
	var plate: bool = hovered != "" or (overview and chosen != mine)
	if not plate and cards.is_empty() and now - director.opened_at_of(chosen) > 1.0:
		var since: Variant = director.arenas.empty_since_of(chosen)
		var text: String = "no agents here"
		if since != null and letters.size() > 1:
			var left: float = float(since) + director.arenas.close_after() - now
			text = "no agents here: this arena closes in %d s" % maxi(0, ceili(left))
		out["empty_text"] = text
		return out
	var x: int = BarLayout.CARDS_X
	var w: int = BarLayout.CARDS_W
	if plate:
		var plate_w: int = maxi(11, TextArt.width(TextArt.TINY5, chosen) + 6)
		out["plate"] = true
		out["plate_rect"] = Rect2i(4, BarLayout.CARD_Y, plate_w, BarLayout.CARD_H)
		x = plate_w + 7
		w = 469 - plate_w
	var compact: bool = cards.size() > LogModel.FULL_CARDS_UP_TO
	var rects: Array[Rect2i] = BarLayout.card_rects(cards.size(), compact, x, w)
	var focus_number: Variant = camera.focus_of(chosen)
	var items: Array[Dictionary] = []
	for i in cards.size():
		items.append({ "card": cards[i], "rect": rects[i], "focused": focus_number != null and cards[i]["number"] == focus_number })
	out["items"] = items
	return out


func _overview(_director: RefCounted, camera: RefCounted, _now: float, page: int, hovered: String) -> Dictionary:
	var cells: Array[Dictionary] = []
	var labels: Dictionary = ui["labels"]
	for slot in 4:
		var letter: String = ArenaRules.name_of(page * 4 + slot)
		var free: bool = not camera.letters.has(letter)
		var waiting: bool = false
		if not free:
			waiting = (labels[letter] as Dictionary)["states"].has("WAIT")
		cells.append({ "letter": letter, "rect": BarLayout.CELLS[slot], "free": free, "hover": letter == hovered, "waiting": waiting })
	var arrows: Array[Dictionary] = []
	for side: int in [-1, 1]:
		var there: Array[int] = []
		for p: int in camera.pages:
			if (p - page) * side > 0:
				there.append(p)
		if not there.is_empty():
			arrows.append({ "side": side, "rect": BarLayout.EDGE_ARROWS[0 if side < 0 else 1], "pages": there, "page": there.back() if side < 0 else there[0], "state": _pages_state(_director, camera, there, _now) })
	return { "cells": cells, "arrows": arrows }


## The screen rectangles of the penguins of the arena on screen (and the helpers: they stand for their parent). Only for a view
## of one arena. A click on a penguin gives its agent the focus.
func _penguin_hits(director: RefCounted, pose: ArenaRules.Pose, view_kind: String, arena: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if view_kind != "arena" or arena == "":
		return out
	var room: Rect2 = ArenaView.screen_rect(arena, pose)
	var factor: float = room.size.x / ArenaView.ROOM_WIDTH
	for actor: RefCounted in director.actors_in(arena):
		if actor.hidden or actor.leaving:
			continue
		var at: Vector2 = room.position + actor.position * factor
		var rect: Rect2 = Rect2(at + PENGUIN_HIT.position * factor, PENGUIN_HIT.size * factor)
		out.append({ "number": actor.number, "arena": arena, "rect": rect, "y": actor.position.y, "helper": actor.is_helper })
	return out


# ---------------------------------------------------------------- hit tests

## What is at a point of the viewport: a Dictionary with a "kind":
##   "close_menu"  a click outside the open follow menu
##   "menu_line"   { index, kind } a line of the follow menu ("pace" has `direction` -1 or 1 on the arrows, 0 elsewhere)
##   "menu"        inside the menu, on nothing
##   "follow"      the follow switch
##   "tab"         { arena }
##   "page"        { page } a box of the list of pages
##   "page_arrow"  { page } an arrow at an end of the boxes: the nearest page beyond it
##   "card"        { arena, number }
##   "edge_arrow"  { page } an arrow at an edge of the overview
##   "cell"        { arena } an arena in the overview
##   "penguin"     { arena, number }
##   "none"
func hit(point: Vector2) -> Dictionary:
	if ui.is_empty():
		return { "kind": "none" }
	var p: Vector2i = Vector2i(point)
	var follow: Dictionary = ui["follow"]
	if ui["menu"] != null:
		var menu: Dictionary = ui["menu"]
		if (follow["rect"] as Rect2i).has_point(p):
			return { "kind": "follow" }
		if (menu["rect"] as Rect2i).has_point(p):
			var pace_down: Rect2i = BarLayout.pace_arrow_rect(-1)
			var pace_up: Rect2i = BarLayout.pace_arrow_rect(1)
			if pace_down.has_point(p):
				return { "kind": "menu_line", "index": BarLayout.PACE_LINE, "line": "pace", "direction": -1 }
			if pace_up.has_point(p):
				return { "kind": "menu_line", "index": BarLayout.PACE_LINE, "line": "pace", "direction": 1 }
			for i: int in (menu["lines"] as Array).size():
				var line: Dictionary = menu["lines"][i]
				if (line["rect"] as Rect2i).has_point(p) and line["kind"] != "pace":
					return { "kind": "menu_line", "index": i, "line": line["kind"], "direction": 0 }
			return { "kind": "menu" }
		return { "kind": "close_menu" }
	if (follow["rect"] as Rect2i).has_point(p):
		return { "kind": "follow" }
	if ui["mode"] == "arenas":
		for tab: Dictionary in ui["tabs"]:
			if (tab["rect"] as Rect2i).has_point(p):
				return { "kind": "tab", "arena": tab["letter"] }
		for item: Dictionary in (ui["pages"] as Dictionary)["items"]:
			if (item["rect"] as Rect2i).has_point(p):
				return { "kind": "page" if item["kind"] == "box" else "page_arrow", "page": item["page"] }
	if ui["mode"] != "log":
		var cards: Dictionary = ui["cards"]
		for item: Dictionary in cards["items"]:
			if (item["rect"] as Rect2i).has_point(p):
				return { "kind": "card", "arena": cards["arena"], "number": (item["card"] as Dictionary)["number"] }
	var overview: Variant = ui["overview"]
	if overview != null:
		for arrow: Dictionary in (overview as Dictionary)["arrows"]:
			if (arrow["rect"] as Rect2i).has_point(p):
				return { "kind": "edge_arrow", "page": arrow["page"] }
		for cell: Dictionary in (overview as Dictionary)["cells"]:
			if not cell["free"] and (cell["rect"] as Rect2i).has_point(p):
				return { "kind": "cell", "arena": cell["letter"] }
		return { "kind": "none" }
	# the penguin that stands in front (the largest y) gets the click
	var best: Dictionary = { }
	for entry: Dictionary in ui["penguins"]:
		if (entry["rect"] as Rect2).has_point(point):
			if best.is_empty() or float(entry["y"]) > float(best["y"]):
				best = entry
	if not best.is_empty():
		return { "kind": "penguin", "arena": best["arena"], "number": best["number"] }
	return { "kind": "none" }
