extends RefCounted
## The rules of the arenas, with no drawing in them. This is a port of the arena rules of the JavaScript mockup (removed, see the git history):
## which arena an agent goes to, where the arenas are, and what the camera shows.
## The rules are in `docs/2d-arenas-plan.md`.
##
## This is a faithful batch port. `simulate_camera` reads the whole script of a session, and it can see
## the future (the `until` time of an approval). The incremental camera of phase G-5 comes later.
##
## Names are the JavaScript names in snake_case, with two changes:
##   * `ease` is `ease_k`, because `ease` is a built-in GDScript function;
##   * `indexOf` is `index_of`, and `byName` is `by_name`.
## Options are a Dictionary with snake_case keys (`DEFAULTS`). A spec for `simulate_camera` is a
## Dictionary with the keys `events`, `focus_events`, `opened`, `closed`, `inputs`, `duration` and `opts`.
## Numbers that may be missing in JavaScript (`undefined` or `null`) are `null` here: `Variant`.
##
## Porting notes (see also godot/README.md):
##   * `Math.round` is `js_round`. It is not the same as `round` for negative halves.
##   * JavaScript sorts are stable. GDScript sorts are not. Every sort here has a tie-break, or it
##     is a scan that keeps the first of equal values.
##   * `Infinity` is `INF`. `null` stays `null`.
##   * A GDScript lambda copies the local variables that it uses. So the camera keeps its state in
##     the fields of `CameraSim`, and its helpers are methods.

const Self := preload("res://src/core/arena_rules.gd")

## The plan's starting values. Every one of them is a guess to tune by watching the mockup.
const DEFAULTS := {
	"arena_size": 4, # agents in an arena; helpers stay with their parent and do not count
	"max_arenas": INF, # no limit of its own: names go on after Z (AA, AB, ...)
	"slide": 0.5, # seconds to slide to another arena of the same page
	"fly": 0.7, # to an arena on the next page: out to the size of a page, across, and in again...
	"fly_step": 0.15, # ...this much more for each page further away...
	"fly_max": 1.0, # ...but never longer than this
	"zoom_out_max": 8, # a long move widens the view by about a page for each page it crosses, up to this many rooms
	"zoom": 0.3, # from an arena out to its page (the overview), or back in
	"scroll": 0.5, # from one page of the overview to the next...
	"scroll_step": 0.15, # ...this much more for each page further away...
	"scroll_max": 0.8, # ...but never longer than this
	"fade": 0.15, # the cut that replaces every move when the person asks for reduced motion
	"hold_after_move": 1.5, # after a move, the camera stays at least this long
	"hold_approval": 4, # an approval notice on screen keeps the camera this long, or until it is answered
	"quiet": 3, # ordinary activity moves the camera only after this long without an event on screen...
	"min_stay": 5, # ...and after the camera has been there at least this long
	"pull_expiry": 10, # a new arena or a finished turn stops pulling after this long; an approval never does
	"focus_hold": 1.5, # the focus inside an arena
	"new_penguin": 0.6, # the first penguin of a new arena pops in this long after the arena opens
	"leave_after": 600, # an agent leaves after this long without an event, unless a call or approval is open
	"close_after": 30, # an empty arena closes after this long, unless it is the only one
	"gutter": 0.1, # the space between two pages, in rooms
	"step": 1.0 / 30.0, # the camera is simulated in steps of this length
	# what pulls the camera in AUTO (the follow switch); MANUAL ignores them all
	"follow": { "approval": true, "fail": false, "open": true, "join": false, "done": true, "activity": true },
	# the pace: in AUTO the camera moves by itself at most this many times a second, counted over pace_window
	# seconds. Approvals are let past it; the person is never limited.
	"pace": 0.3,
	"pace_window": 10,
}
## The pulls, most urgent first. Ordinary activity ('activity' in the follow switch) is not a pull.
const RANK := { "approval": 0, "fail": 1, "open": 2, "done": 3, "join": 4 }
const KINDS: Array[String] = ["approval", "fail", "open", "join", "done", "activity"]
const STATES: Array[String] = ["WAIT", "FAIL", "run", "DONE", "idle"]


## `{...DEFAULTS, ...opts}`: a shallow merge, as in JavaScript. A `follow` in `opts` replaces the whole default.
static func merged(opts: Dictionary = { }) -> Dictionary:
	var o: Dictionary = DEFAULTS.duplicate()
	o.merge(opts, true)
	return o


## `Math.round`: halves go up, also below zero (`Math.round(-0.5)` is -0, and `round(-0.5)` is -1 in GDScript).
## `x - floor(x)` is exact for a double, so this never rounds twice.
static func js_round(x: float) -> float:
	var f: float = floorf(x)
	return f + 1.0 if x - f >= 0.5 else f


static func ease_k(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


static func clamp01(k: float) -> float:
	return maxf(0.0, minf(1.0, k))


## Arena names: A to Z, then AA, AB, ... like the columns of a spreadsheet. A name is also a place (below).
static func name_of(i: int) -> String:
	var s: String = ""
	var n: int = i + 1
	while n > 0:
		s = char(65 + ((n - 1) % 26)) + s
		n = floori((n - 1) / 26.0)
	return s


static func index_of(arena_name: String) -> int:
	var i: int = 0
	for k in arena_name.length():
		i = i * 26 + (arena_name.unicode_at(k) - 64)
	return i - 1


## A sort comparator: the arenas in the order of their names. Two names are never equal.
static func by_name(a: String, b: String) -> bool:
	return index_of(a) < index_of(b)


# ---------------------------------------------------------------- the arena model

class Arena extends RefCounted:
	var letter: String = ""
	## An ordered set. The keys are the agents, the values are `true`.
	var agents: Dictionary = { }
	var empty_since: Variant = null


## Who is in which arena. `place()` and `leave()` as agents come and go, `tick()` to close empty arenas.
class Arenas extends RefCounted:
	var _arena_size: float
	var _max_arenas: float
	var _close_after: float
	var _open: Dictionary = { } # letter -> Arena, in the order they opened
	var _home: Dictionary = { } # the arena each agent was last in, so that it can go back there


	func _init(opts: Dictionary = { }) -> void:
		var o: Dictionary = Self.merged(opts)
		_arena_size = float(o["arena_size"])
		_max_arenas = float(o["max_arenas"])
		_close_after = float(o["close_after"])
		var first: Arena = Arena.new()
		first.letter = Self.name_of(0)
		_open[first.letter] = first


	static func _by_letter(a: Arena, b: Arena) -> bool:
		return Self.index_of(a.letter) < Self.index_of(b.letter)


	func _sorted() -> Array[Arena]:
		var list: Array[Arena] = []
		for a: Arena in _open.values():
			list.append(a)
		list.sort_custom(_by_letter)
		return list


	func _has_room(a: Arena) -> bool:
		return a != null and a.agents.size() < _arena_size


	func letters() -> Array[String]:
		var out: Array[String] = []
		for a in _sorted():
			out.append(a.letter)
		return out


	func agents(letter: String) -> Array:
		if not _open.has(letter):
			return []
		var found: Arena = _open[letter]
		return found.agents.keys()


	## The arena of agent `n`, or `null`.
	func arena_of(n: int) -> Variant:
		for a: Arena in _open.values():
			if a.agents.has(n):
				return a.letter
		return null


	## The arena agent `n` goes to: where it is, else its old arena if there is room, else the first with
	## room, else a new arena with the lowest free letter; `null` when every arena is full and no more may open.
	func place(n: int, _now: float) -> Variant:
		var at: Variant = arena_of(n)
		if at != null:
			return at
		var arena: Arena = null
		var home_arena: Arena = _open.get(_home.get(n))
		if _has_room(home_arena):
			arena = home_arena
		else:
			for a in _sorted():
				if _has_room(a):
					arena = a
					break
		if arena == null:
			if _open.size() >= _max_arenas:
				return null
			var i: int = 0
			while _open.has(Self.name_of(i)):
				i += 1
			arena = Arena.new()
			arena.letter = Self.name_of(i)
			_open[arena.letter] = arena
		arena.agents[n] = true
		arena.empty_since = null
		_home[n] = arena.letter
		return arena.letter


	## The time at which an open arena became empty, or `null` (it has agents, or it is not open).
	func empty_since_of(letter: String) -> Variant:
		if not _open.has(letter):
			return null
		return (_open[letter] as Arena).empty_since


	func close_after() -> float:
		return _close_after


	func leave(n: int, now: float) -> void:
		for a: Arena in _open.values():
			if a.agents.erase(n) and a.agents.size() == 0:
				a.empty_since = now


	## Closes the arenas that have been empty long enough, never the last one. Returns their letters.
	func tick(now: float) -> Array[String]:
		var closed: Array[String] = []
		for a in _sorted():
			if _open.size() > 1 and a.agents.size() == 0 and a.empty_since != null and now - float(a.empty_since) >= _close_after:
				_open.erase(a.letter)
				closed.append(a.letter)
		return closed


static func create_arenas(opts: Dictionary = { }) -> Arenas:
	return Arenas.new(opts)


## Whether an agent leaves: long enough without an event, and nothing it waits for.
## `info` has `last_event`, and optionally `open_calls` (default 0) and `waiting` (default false).
static func leaves(info: Dictionary, now: float, opts: Dictionary = { }) -> bool:
	var o: Dictionary = merged(opts)
	var open_calls: float = float(info.get("open_calls", 0))
	var waiting: bool = bool(info.get("waiting", false))
	return open_calls == 0.0 and not waiting and now - float(info["last_event"]) >= float(o["leave_after"])


## A tab shows the most urgent state of its arena's agents.
static func tab_state(states: Array) -> String:
	if states.is_empty():
		return "empty"
	for s in STATES:
		if states.has(s):
			return s
	return "idle"


# ---------------------------------------------------------------- the world: pages of four
# The arenas sit in pages of four, each a 2x2 matrix, and the pages side by side: A B / C D on the first page,
# E F / G H on the second, and so on (the 10th page holds AK AL / AM AN). An arena keeps its place for as long
# as it is open. A closed arena leaves a free place, which the next new arena takes: it gets the lowest free name.
# Positions are in rooms: an arena is 1 x 1, a page 2 x 2 with a gutter after it, and the world is two rooms high.

## `{ page, slot, x, y }` of an arena. `gutter` is the option of the same name.
static func _place(letter: String, gutter: float) -> Dictionary:
	var i: int = index_of(letter)
	@warning_ignore("integer_division")
	var page: int = i / 4
	var slot: int = i % 4
	@warning_ignore("integer_division")
	var row: int = slot / 2
	return { "page": page, "slot": slot, "x": float(page) * (2.0 + gutter) + float(slot % 2), "y": float(row) }


static func place_of(letter: String, opts: Dictionary = { }) -> Dictionary:
	return _place(letter, float(merged(opts)["gutter"]))


static func _world_width(pages: Array, gutter: float) -> float:
	var top: int = 0
	for p: int in pages:
		top = maxi(top, p)
	return float(top + 1) * (2.0 + gutter) - gutter


static func world_width(pages: Array, opts: Dictionary = { }) -> float:
	return _world_width(pages, float(merged(opts)["gutter"]))


## The pages that hold at least one of the arenas, in order. Letters are unique, so no sort has a tie.
static func _pages_of(letters: Array, gutter: float) -> Array[int]:
	var seen: Dictionary = { }
	for l: String in letters:
		seen[int(_place(l, gutter)["page"])] = true
	var out: Array[int] = []
	for p: int in seen.keys():
		out.append(p)
	out.sort()
	return out


static func pages_of(letters: Array, opts: Dictionary = { }) -> Array[int]:
	return _pages_of(letters, float(merged(opts)["gutter"]))


## A camera pose: the centre of what is on screen, and how many rooms it spans across (1: one arena; 2: a page).
class Pose extends RefCounted:
	var cx: float = 0.0
	var cy: float = 0.0
	var s: float = 1.0
	## How far the move has got, 0 to 1. Only `pose_at` sets it.
	var k: float = 1.0


	func _init(p_cx: float = 0.0, p_cy: float = 0.0, p_s: float = 1.0, p_k: float = 1.0) -> void:
		cx = p_cx
		cy = p_cy
		s = p_s
		k = p_k


	func to_dict(with_k: bool = true) -> Dictionary:
		var d: Dictionary = { "cx": cx, "cy": cy, "s": s }
		if with_k:
			d["k"] = k
		return d


static func arena_pose(letter: String, opts: Dictionary = { }) -> Pose:
	var p: Dictionary = place_of(letter, opts)
	return Pose.new(float(p["x"]) + 0.5, float(p["y"]) + 0.5, 1.0)


static func page_pose(page: int, opts: Dictionary = { }) -> Pose:
	return Pose.new(float(page) * (2.0 + float(merged(opts)["gutter"])) + 1.0, 1.0, 2.0)


## How far a move between pages widens the view midway (in rooms across): a fly to the next page to the size of a
## page, and a longer fly or scroll by about a page for each page it crosses, up to `zoom_out_max`, so that the pages
## in between pass by small instead of smeared. 0: the move does not widen the view.
static func peak_for(kind: String, pages: int, opts: Dictionary = { }) -> float:
	var o: Dictionary = merged(opts)
	var wide: float = minf(float(o["zoom_out_max"]), (2.0 + float(o["gutter"])) * float(pages))
	if kind == "fly":
		return 2.0 if pages <= 1 else wide
	if kind == "scroll" and pages > 1:
		return wide
	return 0.0


## A view: the camera shows an arena (`kind` "arena") or a page of the overview (`kind` "page").
class View extends RefCounted:
	var kind: String = "arena"
	var arena: String = "" # the arena shown, for kind "arena"
	var page: int = 0 # the page shown, for kind "page"
	## For kind "page": the arena the overview was opened from.
	var origin: String = ""


	static func of_arena(letter: String) -> View:
		var v: View = View.new()
		v.kind = "arena"
		v.arena = letter
		return v


	static func of_page(p_page: int, p_origin: String) -> View:
		var v: View = View.new()
		v.kind = "page"
		v.page = p_page
		v.origin = p_origin
		return v


## A move of the camera: where it starts and ends, when, how long, and how far it widens midway.
class Move extends RefCounted:
	var from_pose: Pose
	var to_pose: Pose
	var t0: float = 0.0
	var dur: float = 0.0
	var peak: float = 0.0
	var from_view: View


## Where a move has got to. The view stays on the world: up to the size of a page it stays inside it, and
## wider it is centred on the world's height (and on its width, when it is wider than the whole world).
static func pose_at(move: Move, now: float, width: float) -> Pose:
	var k: float = clamp01((now - move.t0) / move.dur) if move.dur > 0.0 else 1.0
	var e: float = ease_k(k)
	var s: float = move.from_pose.s + (move.to_pose.s - move.from_pose.s) * e
	if move.peak != 0.0:
		s += (move.peak - s) * sin(PI * k)
	var cx: float = move.from_pose.cx + (move.to_pose.cx - move.from_pose.cx) * e
	var cy: float = move.from_pose.cy + (move.to_pose.cy - move.from_pose.cy) * e
	cy += (1.0 - cy) * clamp01(s - 1.0)
	if k >= 1.0:
		# exactly there, so that an arena is drawn on whole pixels again
		cx = move.to_pose.cx
		cy = move.to_pose.cy
		s = move.to_pose.s
	var lo: float = s / 2.0
	var hi: float = width - s / 2.0
	cx = width / 2.0 if lo > hi else maxf(lo, minf(hi, cx))
	return Pose.new(cx, cy, s, k)


## How long a move takes: 'slide' (an arena of the same page), 'fly' (an arena on another page), 'zoom'
## (between an arena and its page) or 'scroll' (between pages of the overview). `pages` is how many pages apart.
static func move_duration(kind: String, pages: int = 0, opts: Dictionary = { }) -> float:
	var o: Dictionary = merged(opts)
	if bool(o.get("reduced_motion", false)):
		return float(o["fade"])
	if kind == "slide":
		return float(o["slide"])
	if kind == "zoom":
		return float(o["zoom"])
	if kind == "fly":
		return minf(float(o["fly_max"]), float(o["fly"]) + float(o["fly_step"]) * float(maxi(0, pages - 1)))
	return minf(float(o["scroll_max"]), float(o["scroll"]) + float(o["scroll_step"]) * float(maxi(0, pages - 1)))


# ---------------------------------------------------------------- the camera

## What `simulate_camera` returns: a frame for each step, and a log of every move with its reason.
class CameraResult extends RefCounted:
	var frames: Array[Dictionary] = []
	## Same name as in the JavaScript (it hides the built-in `log` function, which nothing here needs).
	@warning_ignore("shadowed_global_identifier")
	var log: Array[Dictionary] = []
	var step: float = 1.0 / 30.0


	## The frame nearest to time `t`.
	func at(t: float) -> Dictionary:
		var i: int = int(clampf(Self.js_round(t / step), 0.0, float(frames.size() - 1)))
		return frames[i]


## One pull: something that may move the camera to an arena.
class Pull extends RefCounted:
	var id: int = 0
	var kind: String = ""
	var arena: String = ""
	var n: Variant = null
	var t: float = 0.0
	var rank: int = 0
	var until: float = INF


## Steps the camera through a scripted session. All state is in member fields, so that the helpers are
## methods and not closures. `run()` makes the frames.
class CameraSim extends RefCounted:
	const EPS := 1e-9

	var o: Dictionary
	var ev: Array = [] # the events, sorted by time
	var fev: Array = [] # the focus events, sorted by time
	var inp: Array = [] # the inputs, sorted by time
	var opens: Array = [] # [{ letter, t }]
	var closed: Array = [] # [{ letter, t }]
	var duration: float = 0.0
	var gutter: float = 0.1
	var pulls: Array[Pull] = []
	var served: Dictionary = { } # pull id -> true
	var act_by: Dictionary = { } # arena -> the times of its events
	var act_at: Dictionary = { } # arena -> pointer into act_by
	var mode: String = "AUTO"
	var follow: Dictionary = { }
	var view: View
	var move: Move
	var cause_n: Variant = null # the agent of the pull that moved the camera; it gets the focus on arrival
	var pace: float = 0.3
	var auto_moves: Array[float] = [] # when the camera moved by itself within the last pace_window seconds
	var ribbon: Variant = null # { arena, t }: the camera has just shown a new arena for the first time
	var focus: Dictionary = { }
	var focus_since: Dictionary = { }
	var newest_of: Dictionary = { }
	var prio_of: Dictionary = { }
	var f_at: Dictionary = { }
	var fev_by: Dictionary = { }
	var ii: int = 0
	var prev_letters: Array[String] = []
	var result: CameraResult = CameraResult.new()
	# the values of the current step
	var now: float = 0.0
	var letters: Array[String] = []
	var pages: Array[int] = []
	var width: float = 2.0


	## Events, inputs and the like are sorted by `t`. Equal times keep their order (a stable sort).
	static func sorted_by_t(list: Array) -> Array:
		var order: Array = []
		for i in list.size():
			order.append(i)
		order.sort_custom(
			func(a: int, b: int) -> bool:
				var ta: float = (list[a] as Dictionary)["t"]
				var tb: float = (list[b] as Dictionary)["t"]
				return ta < tb or (ta == tb and a < b)
		)
		var out: Array = []
		for i: int in order:
			out.append(list[i])
		return out


	func _init(spec: Dictionary) -> void:
		o = Self.merged(spec.get("opts", { }))
		gutter = float(o["gutter"])
		duration = float(spec["duration"])
		ev = sorted_by_t(spec.get("events", []))
		fev = sorted_by_t(spec.get("focus_events", []))
		inp = sorted_by_t(spec.get("inputs", []))
		closed = spec.get("closed", [])
		var given: Variant = spec.get("opened")
		opens = [{ "letter": Self.name_of(0), "t": 0.0 }] if given == null else given
		result.step = float(o["step"])
		var id: int = 0
		for e: Dictionary in ev:
			var kind: String = e["kind"]
			if not Self.RANK.has(kind):
				continue
			var p: Pull = Pull.new()
			p.id = id
			id += 1
			p.kind = kind
			p.arena = e["arena"]
			p.n = e.get("n")
			p.t = float(e["t"])
			p.rank = Self.RANK[kind]
			if kind == "approval":
				var until: Variant = e.get("until")
				p.until = INF if until == null else float(until)
			else:
				p.until = p.t + float(o["pull_expiry"])
			pulls.append(p)
		for e: Dictionary in ev:
			var arena: String = e["arena"]
			if not act_by.has(arena):
				act_by[arena] = []
			(act_by[arena] as Array).append(float(e["t"]))
		for e: Dictionary in fev:
			var arena: String = e["arena"]
			if not fev_by.has(arena):
				fev_by[arena] = []
			(fev_by[arena] as Array).append(e)
		var mode_option: Variant = o.get("mode")
		mode = "AUTO" if mode_option == null else str(mode_option)
		follow = (Self.DEFAULTS["follow"] as Dictionary).duplicate()
		follow.merge(o.get("follow", { }), true)
		pace = float(o["pace"])
		view = View.of_arena(str((opens[0] as Dictionary)["letter"]))
		var still: Pose = Self.arena_pose(view.arena, o)
		move = Move.new()
		move.from_pose = still
		move.to_pose = still
		move.from_view = view
		prev_letters = _letters_at(0.0)


	# ------------------------------------------------ helpers

	func _is_open(a: Dictionary, t: float) -> bool:
		if float(a["t"]) > t + EPS:
			return false
		for c: Dictionary in closed:
			if c["letter"] == a["letter"] and float(c["t"]) >= float(a["t"]) and float(c["t"]) <= t + EPS:
				return false
		return true


	## The open arenas at time `t`, in the order of their names.
	func _letters_at(t: float) -> Array[String]:
		var seen: Dictionary = { }
		for a: Dictionary in opens:
			if _is_open(a, t):
				seen[str(a["letter"])] = true
		var out: Array[String] = []
		for l: String in seen.keys():
			out.append(l)
		out.sort_custom(Self.by_name)
		return out


	## The newest activity of each arena, read with a pointer per arena, since time only moves forward.
	func _last_activity(letter: String, at_time: float) -> float:
		var ts: Array = act_by.get(letter, [])
		var i: int = act_at.get(letter, -1)
		while i + 1 < ts.size() and float(ts[i + 1]) <= at_time + EPS:
			i += 1
		act_at[letter] = i
		return float(ts[i]) if i >= 0 else -INF


	func _page_of(letter: String) -> int:
		return int(Self._place(letter, gutter)["page"])


	func _idx(letter: String) -> int:
		return letters.find(letter)


	func _here() -> int:
		return _page_of(view.arena) if view.kind == "arena" else view.page


	func _pose_of(next: View) -> Pose:
		return Self.arena_pose(next.arena, o) if next.kind == "arena" else Self.page_pose(next.page, o)


	func _go(next: View, kind: String, apart: int, why: String, n: Variant) -> void:
		var p: Pose = Self.pose_at(move, now, width)
		var m: Move = Move.new()
		m.from_pose = Pose.new(p.cx, p.cy, p.s)
		m.to_pose = _pose_of(next)
		m.t0 = now
		m.dur = Self.move_duration(kind, apart, o)
		m.peak = 0.0 if bool(o.get("reduced_motion", false)) else Self.peak_for(kind, apart, o)
		m.from_view = view
		move = m
		view = next
		cause_n = n
		result.log.append({ "t": now, "to": next.arena if next.kind == "arena" else "page %d" % (next.page + 1), "why": why })


	func _cut(next: View) -> void:
		var p: Pose = _pose_of(next)
		var m: Move = Move.new()
		m.from_pose = p
		m.to_pose = p
		m.t0 = now
		m.from_view = next
		move = m
		view = next


	## To an arena: a slide on the same page, a fly to another, a zoom in from the overview of its page.
	## `letter` may be `null` (nothing to go to).
	func _move_to(letter: Variant, why: String, n: Variant = null) -> void:
		if letter == null or typeof(letter) != TYPE_STRING:
			return
		var target: String = letter
		if _idx(target) < 0 or (view.kind == "arena" and view.arena == target):
			return
		var a: int = _here()
		var b: int = _page_of(target)
		var kind: String = "slide"
		if a != b:
			kind = "fly"
		elif view.kind == "page":
			kind = "zoom"
		_go(View.of_arena(target), kind, absi(b - a), why, n)


	## To a page of the overview: a zoom out from one of its arenas, a scroll from another page.
	## `page` may be `null` (no such page).
	func _open_page(page: Variant, why: String) -> void:
		if page == null or not pages.has(int(page)):
			return
		var target: int = int(page)
		if view.kind == "page" and view.page == target:
			return
		var a: int = _here()
		var origin: String = view.arena if view.kind == "arena" else view.origin
		var kind: String = "fly"
		if view.kind == "page":
			kind = "scroll"
		elif a == target:
			kind = "zoom"
		_go(View.of_page(target, origin), kind, absi(target - a), why, null)


	func _active(p: Pull) -> bool:
		return now >= p.t and now < p.until and not served.has(p.id) and letters.has(p.arena)


	## The arena at `index` of the open arenas, or `null` when there is none. JavaScript gives `undefined`.
	func _letter_at(index: int) -> Variant:
		if index < 0 or index >= letters.size():
			return null
		return letters[index]


	## N: the oldest waiting approval elsewhere, else the newest failure, else the newest finished turn.
	func _needs_you() -> Variant:
		var others: Array[String] = []
		for l in letters:
			if view.kind != "arena" or l != view.arena:
				others.append(l)
		var oldest: Pull = null
		for p in pulls:
			if p.kind == "approval" and now >= p.t and now < p.until and others.has(p.arena):
				if oldest == null or p.t < oldest.t: # the first of equal times stays
					oldest = p
		if oldest != null:
			return oldest.arena
		for kind: String in ["fail", "done"]:
			var found: Variant = null
			for e: Dictionary in ev:
				if e["kind"] != kind or float(e["t"]) > now or not others.has(e["arena"]):
					continue
				var later: bool = false
				for x: Dictionary in ev:
					if x.get("n") == e.get("n") and float(x["t"]) > float(e["t"]) and float(x["t"]) <= now:
						later = true
						break
				if not later:
					found = e["arena"] # the last one in time order wins
			if found != null:
				return found
		return null


	func _frame_pulls_pending() -> Array[String]:
		var out: Array[String] = []
		for p in pulls:
			if _active(p):
				out.append("%s:%s" % [p.kind, p.arena])
		return out


	## Tab and Esc in the overview: the arena the overview was opened from, else the first arena of the page.
	func _tab_target() -> Variant:
		if _idx(view.origin) >= 0:
			return view.origin
		for l in letters:
			if _page_of(l) == view.page:
				return l
		return null



	# ------------------------------------------------ one step

	func _closed_view() -> void:
		# what is on screen has closed: a cut to the left neighbour (or the right one), or to the nearest page
		if view.kind == "arena" and _idx(view.arena) < 0:
			var old: int = prev_letters.find(view.arena)
			var next: Variant = null
			var left: Array[String] = prev_letters.slice(0, maxi(0, old))
			left.reverse()
			for l in left:
				if _idx(l) >= 0:
					next = l
					break
			if next == null:
				for l: String in prev_letters.slice(old + 1):
					if _idx(l) >= 0:
						next = l
						break
			if next == null and not letters.is_empty():
				next = letters[0]
			if next != null:
				_cut(View.of_arena(str(next)))
				result.log.append({ "t": now, "to": str(next), "why": "closed" })
		elif view.kind == "page" and not pages.has(view.page):
			if not pages.is_empty():
				var best: int = pages[0]
				for p in pages:
					if absi(p - view.page) < absi(best - view.page):
						best = p
				_cut(View.of_page(best, view.origin))
				result.log.append({ "t": now, "to": "page %d" % (best + 1), "why": "closed" })


	func _truthy(v: Variant) -> bool:
		match typeof(v):
			TYPE_NIL:
				return false
			TYPE_BOOL:
				return v
			TYPE_STRING:
				return v != ""
			TYPE_INT, TYPE_FLOAT:
				return v != 0
		return true


	func _inputs() -> void:
		while ii < inp.size() and float((inp[ii] as Dictionary)["t"]) <= now + EPS:
			var i: Dictionary = inp[ii]
			ii += 1
			var key: Variant = i.get("key")
			var click: Variant = i.get("click")
			if key == "F":
				mode = "MANUAL" if mode == "AUTO" else "AUTO"
			elif _truthy(i.get("toggle")):
				var kind: String = i["toggle"]
				follow[kind] = not bool(follow.get(kind, false))
			elif _truthy(i.get("manual")):
				mode = "MANUAL"
			elif i.get("pace") != null:
				pace = float(i["pace"])
			elif key == "Tab":
				if view.kind == "page":
					_move_to(_tab_target(), "tab")
				elif letters.size() > 1:
					_open_page(_page_of(view.arena), "tab")
			elif key == "Esc":
				if view.kind == "page":
					_move_to(_tab_target(), "esc")
			elif key == "Left" or key == "Right":
				var d: int = -1 if key == "Left" else 1
				if view.kind == "page":
					# the overview scrolls a page
					var at_page: int = pages.find(view.page) + d
					var page_target: Variant = null
					if at_page >= 0 and at_page < pages.size():
						page_target = pages[at_page]
					_open_page(page_target, "key")
				else:
					mode = "MANUAL"
					_move_to(_letter_at(_idx(view.arena) + d), "key")
			elif key == "N":
				mode = "MANUAL"
				_move_to(_needs_you(), "N")
			elif click == "tab" or click == "cell":
				mode = "MANUAL"
				_move_to(i.get("arena"), "click")
			elif click == "page":
				_open_page(i.get("page"), "click")


	func _serve(arrived: float) -> void:
		# the camera is at an arena: what it shows there has been seen
		if view.kind == "arena" and now >= arrived - EPS:
			for p in pulls:
				if _active(p) and p.arena == view.arena:
					served[p.id] = true
					if p.kind == "open":
						ribbon = { "arena": p.arena, "t": now }
			if cause_n != null:
				focus[view.arena] = cause_n
				focus_since[view.arena] = now
				cause_n = null


	## Follow AUTO: the pulls that are ticked in the follow switch first, then (if ticked) ordinary activity;
	## nothing moves while the overview is open. The pace limits how often the camera moves by itself: when it has
	## moved as often as it may in the last pace_window seconds, the move waits ('held'); pulls keep their order,
	## so the most urgent goes first when it may, and a pull that expires meanwhile is only shown in the bar.
	## Approvals are let past the pace, since someone is blocked until they answer; they still count as moves.
	## Returns `held`.
	func _auto(arrived: float) -> bool:
		var held: bool = false
		var window: float = float(o["pace_window"])
		while not auto_moves.is_empty() and auto_moves[0] <= now - window + EPS:
			auto_moves.pop_front()
		if mode == "AUTO" and view.kind == "arena" and now >= arrived + float(o["hold_after_move"]) - EPS:
			var reading: bool = false
			for p in pulls:
				if p.kind == "approval" and p.arena == view.arena and now >= p.t and now < p.until and now - maxf(p.t, arrived) < float(o["hold_approval"]) - EPS:
					reading = true
					break
			if not reading:
				var target: Variant = null
				var why: String = ""
				var n: Variant = null
				# the most urgent pull: the lowest rank, then the oldest; the first of equal ones stays
				var pull: Pull = null
				for p in pulls:
					if bool(follow[p.kind]) and _active(p) and p.arena != view.arena:
						if pull == null or p.rank < pull.rank or (p.rank == pull.rank and p.t < pull.t):
							pull = p
				if pull != null:
					target = pull.arena
					why = "pull:" + pull.kind
					n = pull.n
				elif bool(follow["activity"]) and now - _last_activity(view.arena, now) >= float(o["quiet"]) - EPS and now - arrived >= float(o["min_stay"]) - EPS:
					# the arena with the newest activity; the first of equal ones stays
					var best: float = -INF
					for l in letters:
						if l == view.arena:
							continue
						var last: float = _last_activity(l, now)
						if now - last < float(o["quiet"]) and (target == null or last > best):
							target = l
							best = last
					why = "activity"
				if target != null:
					var past_pace: bool = pull != null and pull.kind == "approval"
					if past_pace or float(auto_moves.size()) < maxf(1.0, Self.js_round(pace * window)):
						_move_to(target, why, n)
						auto_moves.append(now)
					else:
						held = true
		return held


	## The focus inside each arena: in AUTO the newest event, held `focus_hold` s, and a failure, an approval or a
	## finished turn at once; in MANUAL it stays where it is.
	func _focus_step() -> void:
		var hold: float = float(o["focus_hold"])
		for l in letters:
			var list: Array = fev_by.get(l, [])
			var i: int = f_at.get(l, 0)
			while i < list.size() and float((list[i] as Dictionary)["t"]) <= now + EPS:
				var e: Dictionary = list[i]
				newest_of[l] = e
				if _truthy(e.get("priority")):
					prio_of[l] = e
				i += 1
			f_at[l] = i
			if mode == "MANUAL" and focus.get(l) != null:
				continue
			var prio: Variant = prio_of.get(l)
			var newest: Variant = newest_of.get(l)
			if prio != null:
				prio_of[l] = null
				if (prio as Dictionary).get("n") != focus.get(l):
					focus[l] = (prio as Dictionary).get("n")
					focus_since[l] = now
				continue
			if newest != null and (newest as Dictionary).get("n") != focus.get(l) and now - float(focus_since.get(l, -INF)) >= hold - EPS:
				focus[l] = (newest as Dictionary).get("n")
				focus_since[l] = now


	func step(s: int) -> void:
		now = float(s) * float(o["step"])
		letters = _letters_at(now)
		pages = Self._pages_of(letters, gutter)
		width = Self._world_width(pages, gutter)
		_closed_view()
		prev_letters = letters
		_inputs()
		var arrived: float = move.t0 + move.dur
		_serve(arrived)
		var held: bool = _auto(arrived)
		_focus_step()
		var pose: Pose = Self.pose_at(move, now, width)
		var fv: View = move.from_view
		# null where JavaScript has null: an arena only for the view of an arena, and so on
		var frame_arena: Variant = null
		var frame_from: Variant = null
		var frame_arena_from: Variant = null
		if view.kind == "arena":
			frame_arena = view.arena
		else:
			frame_from = view.origin
		if fv.kind == "arena":
			frame_arena_from = fv.arena
		result.frames.append(
			{
				"t": now,
				"mode": mode,
				"follow": follow.duplicate(),
				"pace": pace,
				"held": held,
				"letters": letters,
				"pages": pages,
				"width": width,
				"view": view.kind,
				"arena": frame_arena,
				"page": _here(),
				"from": frame_from,
				"pose": pose.to_dict(true),
				"moving": pose.k < 1.0,
				"k": pose.k,
				"move": { "from": move.from_pose.to_dict(false), "to": move.to_pose.to_dict(false) },
				"arena_from": frame_arena_from,
				"page_from": _page_of(fv.arena) if fv.kind == "arena" else fv.page,
				"focus": focus.duplicate(),
				"ribbon": ribbon,
				"pending": _frame_pulls_pending(),
			},
		)


	func run() -> CameraResult:
		var steps: int = int(Self.js_round(duration / float(o["step"])))
		for s in range(steps + 1):
			step(s)
		return result


## Steps the camera through a scripted session and returns what it does at every step.
##   events:       [{ t, arena, n, kind }]: kind 'activity', 'fail', 'open' (an agent opened a new arena), 'join' (an
##                 agent joined an arena that had room), 'done' (a main agent's turn finished) or 'approval' (with
##                 `until`, the time it is answered). Every event is activity.
##   focus_events: [{ t, arena, n, priority }]: what moves the focus inside an arena
##   opened:       [{ letter, t }]: when each arena opened; the first one at 0
##   closed:       [{ letter, t }]: when an arena closed (an arena may open again later under the same letter)
##   inputs:       [{ t, key }] with key 'F' (AUTO or MANUAL), 'Tab', 'Esc', 'Left', 'Right' or 'N'; [{ t, toggle: kind }]
##                 (one line of the follow menu: a kind of KINDS on or off); [{ t, manual: true }] (its 'manual only');
##                 [{ t, pace }] (its pace: moves a second, INF for no limit);
##                 or [{ t, click, arena }] with click 'tab' (a tab of the list) or 'cell' (an arena in the
##                 overview), or [{ t, click: 'page', page }] (a page's box in the list; pages count from 0)
##   duration:     seconds to simulate
##   opts:         the options of `DEFAULTS`, and `mode` ('AUTO' or 'MANUAL') and `reduced_motion`
## Returns a `CameraResult`: `frames`, `log` and `at(t)`.
static func simulate_camera(spec: Dictionary) -> CameraResult:
	return CameraSim.new(spec).run()
