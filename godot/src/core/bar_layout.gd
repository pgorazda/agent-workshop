extends RefCounted
## Where the parts of the bar and of the overview lie, in the pixels of the 480x270 viewport (docs/2d-arenas-plan.md, "The
## screen"; phase G-6). The numbers are those of the mockup's `arenas.js`. This file has no drawing: the art draws at these
## places, and the hit tests of the input read them.
##
## The room is 480x232 and the bar is the 38 rows under it. The top line of the bar is the row at y 233 (9 pixels high). The
## cards are the row at y 243 (25 pixels high).

const BAR_TOP := 232
const ROW_Y := 233
const ROW_H := 9
const CARD_Y := 243
const CARD_H := 25
const CARD_GAP := 2
const CARDS_X := 4
const CARDS_W := 472

## The four tabs of a page, then a box for each page.
const TAB_X0 := 14
const TAB_W := 80
const TAB_GAP := 3
const PAGE_W := 12
const PAGE_GAP := 2
## At most this many page boxes show, around the page of the list. An arrow at either end stands for the pages beyond.
const PAGE_WINDOW := 5
const ARROW_W := 7
## The follow switch in AUTO is this wide. In MANUAL it is as wide as the word, so the caller gives the width.
const FOLLOW_W := 33
const FOLLOW_RIGHT := 476
## The follow label and the switch in the top line of one arena.
const PILL_X := 214

## The follow menu: lines 0 to 5 are the kinds, 6 is the pace, 7 is "manual only".
const MENU := Rect2i(350, 125, 126, 106)
const MENU_LINES := 8
const PACE_LINE := 6
const MANUAL_LINE := 7
## The pace levels of the menu: moves in the pace window, from 1 to 10, then no limit.
const PACE_LEVELS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

## The overview: the four cells of a page at half size, and the arrows at its edges.
const CELLS: Array[Rect2i] = [Rect2i(0, 0, 240, 116), Rect2i(240, 0, 240, 116), Rect2i(0, 116, 240, 116), Rect2i(240, 116, 240, 116)]
const EDGE_ARROWS: Array[Rect2i] = [Rect2i(0, 44, 9, 28), Rect2i(471, 44, 9, 28)]


## The left edge of the tab of a slot (0 to 3) in a page.
static func tab_x(slot: int) -> int:
	return TAB_X0 + slot * (TAB_W + TAB_GAP)


static func tab_rect(slot: int) -> Rect2i:
	return Rect2i(tab_x(slot), ROW_Y, TAB_W, ROW_H)


## Where the boxes of the pages start.
static func page_x0() -> int:
	return tab_x(4) + 2


## The boxes and arrows of the pages. `pages` is the list of the pages that exist (their numbers from 0), `page` the page that
## the list shows. Returns { before, shown, after (the pages), items: [{ kind: "arrow"|"box", side, page, pages, rect }], end }.
## `end` is the x where the list ends (the "+N" of agents that are not shown comes after it).
static func page_list(pages: Array[int], page: int) -> Dictionary:
	var out: Dictionary = { "before": [] as Array[int], "shown": [] as Array[int], "after": [] as Array[int], "items": [] as Array[Dictionary], "end": tab_x(4) - TAB_GAP }
	if pages.size() <= 1 and page <= 0:
		return out
	var n: int = pages.size()
	var start: int = 0
	if n > PAGE_WINDOW:
		start = maxi(0, mini(n - PAGE_WINDOW, pages.find(page) - 2))
	var before: Array[int] = []
	var shown: Array[int] = []
	var after: Array[int] = []
	for i in n:
		if i < start:
			before.append(pages[i])
		elif i < start + PAGE_WINDOW:
			shown.append(pages[i])
		else:
			after.append(pages[i])
	var items: Array[Dictionary] = []
	var x: int = page_x0()
	if not before.is_empty():
		items.append({ "kind": "arrow", "side": -1, "page": before.back(), "pages": before, "rect": Rect2i(x, ROW_Y, ARROW_W, ROW_H) })
		x += ARROW_W + PAGE_GAP
	for p in shown:
		items.append({ "kind": "box", "side": 0, "page": p, "pages": [p], "rect": Rect2i(x, ROW_Y, PAGE_W, ROW_H) })
		x += PAGE_W + PAGE_GAP
	if not after.is_empty():
		items.append({ "kind": "arrow", "side": 1, "page": after[0], "pages": after, "rect": Rect2i(x, ROW_Y, ARROW_W, ROW_H) })
		x += ARROW_W + PAGE_GAP
	out["before"] = before
	out["shown"] = shown
	out["after"] = after
	out["items"] = items
	out["end"] = x - PAGE_GAP
	return out


## The rectangle of the follow switch. `manual_width` is the width of the word MANUAL plus its padding.
static func follow_rect(manual: bool, manual_width: int) -> Rect2i:
	var w: int = manual_width if manual else FOLLOW_W
	return Rect2i(FOLLOW_RIGHT - w, ROW_Y, w, ROW_H)


## The centre of a line of the menu, and the rectangle that a click on the line hits.
static func menu_line_centre(i: int) -> Vector2i:
	return Vector2i(MENU.position.x + 60, MENU.position.y + 19 + i * 11)


static func menu_line_rect(i: int) -> Rect2i:
	var ly: int = menu_line_centre(i).y - 4
	return Rect2i(MENU.position.x + 1, ly - 1, MENU.size.x - 2, 11)


## The two arrows of the pace line: their centres in x and the top y of their boxes (9 x 9 pixels).
static func pace_arrow_rect(direction: int) -> Rect2i:
	var ly: int = menu_line_centre(PACE_LINE).y - 4
	var cx: int = MENU.position.x + MENU.size.x - (20 if direction < 0 else 9)
	return Rect2i(cx - 4, ly, 9, 9)


## The pace level after a click: `direction` -1 lowers it and 1 raises it. The levels are moves in the pace window (1 to 10)
## and then no limit (INF). `pace` is moves a second, and `window` the seconds that the moves are counted over.
static func next_pace(pace: float, window: float, direction: int) -> float:
	if is_inf(pace):
		return float(PACE_LEVELS.back()) / window if direction < 0 else INF
	var level: int = clampi(int(roundf(pace * window)), PACE_LEVELS[0], PACE_LEVELS.back())
	var next: int = level + direction
	if next > PACE_LEVELS.back():
		return INF
	return float(maxi(next, PACE_LEVELS[0])) / window


## The cards of a row of `count` cards from x with width w. Full cards leave room for five. Returns their rectangles.
static func card_rects(count: int, compact: bool, x: int = CARDS_X, w: int = CARDS_W) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	if count <= 0:
		return rects
	var slots: int = maxi(count, count if compact else 5)
	var card_w: int = floori(float(w - CARD_GAP * (slots - 1)) / float(slots))
	for i in count:
		rects.append(Rect2i(x + i * (card_w + CARD_GAP), CARD_Y, card_w, CARD_H))
	return rects
