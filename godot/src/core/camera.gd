extends RefCounted
## The incremental camera of the arenas (docs/2d-arenas-plan.md, "The camera"; phase G-5).
##
## It gives the same results as the batch camera `ArenaRules.simulate_camera`, but it does not read the future. The batch
## camera is given the whole story of a session and knows when an approval ends (`until`). This camera is fed while the
## story happens: an approval is open until `answer()` says that it ended. Both must agree on every case where the answer
## time is known. `test_camera_parity.gd` runs all golden cases through both. The batch port stays as the oracle.
##
## The camera has no nodes and draws nothing. The frame code does this each frame:
##   1. feeds what happened: `feed()` for each event (`open`, `join`, `done`, `fail`, `approval`, `activity`), `feed_focus()`,
##      `arena_opened()`, `arena_closed()`, `answer()` when an approval ends, and the person's inputs;
##   2. calls `advance(now)`: it runs the steps of 1/30 s (`DEFAULTS.step`) up to the simulation time `now`;
##   3. asks for the pose with `pose_at_time(t)`. The decisions come every 1/30 s, but the pose is a function of the time,
##      so it is smooth at any frame rate (choice 4 of the plan).
##
## Events must not be dated in the future. Equal times keep the order of arrival. An event of the same agent, or of any
## other kind, is activity too (every event is activity).
##
## The person's inputs are methods (`press`, `click_tab`, `click_cell`, `click_page`, `toggle`, `manual_only`, `set_pace`) that
## queue an input at a time. The next step applies it, as the batch camera applies the `inputs` of its spec.
##
## Signals tell the interface what changed: `moved` (a move started, with its log entry), `mode_changed`, `ribbon_started`
## (the camera shows a new arena for the first time) and `held_changed` (a move waits for the pace limit: the follow switch blinks).

const ArenaRules := preload("res://src/core/arena_rules.gd")

signal moved(entry: Dictionary)
signal mode_changed(mode: String)
signal ribbon_started(arena: String, at: float)
signal held_changed(held: bool)

const EPS := 1e-9
## The most moves kept in `moves` and `log`. A session that runs for days must not grow without end.
const LOG_LIMIT := 10000
## The long moves that the benchmark looks for widen the view to at least this many rooms across.
const LONG_MOVE_ROOMS := 4.0

## One pull: something that may move the camera to an arena.
class Pull extends RefCounted:
	var id: int = 0
	var kind: String = ""
	var arena: String = ""
	var n: Variant = null
	var t: float = 0.0
	var rank: int = 0
	var until: float = INF

var o: Dictionary
var mode: String = "AUTO"
var follow: Dictionary = { }
var pace: float = 0.3
var view: ArenaRules.View
var move: ArenaRules.Move
## The agent of the pull that moved the camera. It gets the focus on arrival.
var cause_n: Variant = null
## The arena of the last ribbon: { arena, t } or null.
var ribbon: Variant = null
var focus: Dictionary = { }
var focus_since: Dictionary = { }
## The open arenas in the order of their names, their pages and the width of the world in rooms.
var letters: Array[String] = []
var pages: Array[int] = []
var width: float = 2.0
var held: bool = false
var now: float = 0.0
## One entry for each move, as the batch camera logs it: { t, to, why }. (It has the name of the batch camera's field.)
@warning_ignore("shadowed_global_identifier")
var log: Array[Dictionary] = []
## The same moves with more: { id, t, to, why, kind, apart, dur, peak, wide }. The benchmark reads this.
var moves: Array[Dictionary] = []
## The number of the last move. 0 before the first move.
var move_id: int = 0
## Keep a whole frame for each step in `frames` (for tests). Off in the app.
var record_frames: bool = false
var frames: Array[Dictionary] = []

var _pulls: Array[Pull] = []
var _next_pull_id: int = 0
var _served: Dictionary = { } # pull id -> true
var _last_activity: Dictionary = { } # arena -> the time of its newest event
var _agent_last: Dictionary = { } # agent key -> the time of its newest event
var _fail_events: Array[Dictionary] = [] # { t, arena, n }: failures not yet followed by another event of the agent
var _done_events: Array[Dictionary] = []
var _topology: Array[Dictionary] = [] # { t, open, letter }, in order of arrival
var _open_set: Dictionary = { }
var _inputs: Array[Dictionary] = []
var _auto_moves: Array[float] = []
var _newest_of: Dictionary = { }
var _prio_of: Dictionary = { }
var _focus_queue: Dictionary = { } # arena -> Array of { t, n, priority }
var _prev_letters: Array[String] = []
var _gutter: float = 0.1
var _topology_dirty: bool = true
var _next_step: int = 0
var _first_letter: String = ""


func _init(opts: Dictionary = { }) -> void:
	o = ArenaRules.merged(opts)
	_gutter = float(o["gutter"])
	var mode_option: Variant = o.get("mode")
	mode = "AUTO" if mode_option == null else str(mode_option)
	follow = (ArenaRules.DEFAULTS["follow"] as Dictionary).duplicate()
	follow.merge(o.get("follow", { }), true)
	pace = float(o["pace"])
	view = ArenaRules.View.of_arena("")
	move = ArenaRules.Move.new()
	move.from_pose = ArenaRules.Pose.new()
	move.to_pose = ArenaRules.Pose.new()
	move.from_view = view


# ---------------------------------------------------------------- what is fed

## An arena opened at time `t`. The first arena that opens is where the camera starts.
func arena_opened(letter: String, t: float) -> void:
	_topology.append({ "t": t, "open": true, "letter": letter })
	if _first_letter == "":
		_first_letter = letter
		_set_start(letter)


## An arena closed at time `t`.
func arena_closed(letter: String, t: float) -> void:
	_topology.append({ "t": t, "open": false, "letter": letter })


func _set_start(letter: String) -> void:
	view = ArenaRules.View.of_arena(letter)
	var still: ArenaRules.Pose = ArenaRules.arena_pose(letter, o)
	move = ArenaRules.Move.new()
	move.from_pose = still
	move.to_pose = still
	move.from_view = view


## Something happened in an arena. `kind` is "activity", "fail", "open", "join", "done" or "approval". An approval
## stays open until `answer()`. Returns the id of the pull (-1 for a kind that is not a pull), for `answer()`.
func feed(kind: String, arena: String, n: Variant, t: float) -> int:
	_last_activity[arena] = maxf(float(_last_activity.get(arena, -INF)), t)
	var key: Variant = _agent_key(n)
	_agent_last[key] = maxf(float(_agent_last.get(key, -INF)), t)
	_drop_superseded(key, t)
	match kind:
		"fail":
			_fail_events.append({ "t": t, "arena": arena, "n": key })
		"done":
			_done_events.append({ "t": t, "arena": arena, "n": key })
	if not ArenaRules.RANK.has(kind):
		return -1
	var p: Pull = Pull.new()
	p.id = _next_pull_id
	_next_pull_id += 1
	p.kind = kind
	p.arena = arena
	p.n = n
	p.t = t
	p.rank = ArenaRules.RANK[kind]
	p.until = INF if kind == "approval" else t + float(o["pull_expiry"])
	_pulls.append(p)
	return p.id


## The approval with this pull id was answered at time `t`.
func answer(pull_id: int, t: float) -> void:
	for p in _pulls:
		if p.id == pull_id and p.kind == "approval":
			p.until = minf(p.until, t)


## Every open approval of an agent was answered at time `t`.
func answer_agent(n: Variant, t: float) -> void:
	var key: Variant = _agent_key(n)
	for p in _pulls:
		if p.kind == "approval" and p.until == INF and _agent_key(p.n) == key:
			p.until = t


## An event that moves the focus inside an arena (`priority`: a failure, an approval or a finished turn).
func feed_focus(arena: String, n: Variant, t: float, priority: bool) -> void:
	if not _focus_queue.has(arena):
		_focus_queue[arena] = []
	(_focus_queue[arena] as Array).append({ "t": t, "n": n, "priority": priority })


## The person clicked a penguin or its card: the focus of that arena goes to the agent `n` in both modes, and in AUTO it stays
## for the focus hold. The batch camera has no such input, so the golden data do not cover it.
func set_focus(arena: String, n: Variant, t: float) -> void:
	focus[arena] = n
	focus_since[arena] = t
	_prio_of[arena] = null


## An input of the person at time `t`, in the form of the batch spec: `{ key }`, `{ toggle }`, `{ manual: true }`,
## `{ pace }` or `{ click: "tab"|"cell"|"page", arena|page }`.
func input(entry: Dictionary, t: float) -> void:
	var queued: Dictionary = entry.duplicate()
	queued["t"] = t
	_inputs.append(queued)


func press(key: String, t: float) -> void:
	input({ "key": key }, t)


func click_tab(arena: String, t: float) -> void:
	input({ "click": "tab", "arena": arena }, t)


func click_cell(arena: String, t: float) -> void:
	input({ "click": "cell", "arena": arena }, t)


func click_page(page: int, t: float) -> void:
	input({ "click": "page", "page": page }, t)


## One line of the follow menu: a kind of `ArenaRules.KINDS` on or off.
func toggle(kind: String, t: float) -> void:
	input({ "toggle": kind }, t)


## The menu line "manual only": the mode is MANUAL, the ticks stay.
func manual_only(t: float) -> void:
	input({ "manual": true }, t)


## The menu line of the pace: moves a second (`INF` for no limit).
func set_pace(moves_per_second: float, t: float) -> void:
	input({ "pace": moves_per_second }, t)


## Reduced motion: every move is a short cut. It applies to the moves that start after this call.
func set_reduced_motion(on: bool) -> void:
	o["reduced_motion"] = on


# ---------------------------------------------------------------- what is asked

## The time of the next step that has not run.
func next_step_time() -> float:
	return float(_next_step) * float(o["step"])


## Runs every step of 1/30 s up to the time `to_time`. Returns how many steps ran.
func advance(to_time: float) -> int:
	var count: int = 0
	var step_length: float = float(o["step"])
	while float(_next_step) * step_length <= to_time + EPS:
		step(_next_step)
		_next_step += 1
		count += 1
	return count


## The pose at any time, smooth between the steps.
func pose_at_time(t: float) -> ArenaRules.Pose:
	return ArenaRules.pose_at(move, t, width)


func is_open_letter(letter: String) -> bool:
	return letters.has(letter)


func arena_shown() -> String:
	return view.arena if view.kind == "arena" else ""


## The page of the view (the page of the arena for a view of an arena).
func page_shown() -> int:
	return _here()


func in_overview() -> bool:
	return view.kind == "page"


## True while the last move has not arrived at `t`.
func moving_at(t: float) -> bool:
	return pose_at_time(t).k < 1.0


## The active pulls: "kind:arena" in the order they came.
func pending() -> Array[String]:
	var out: Array[String] = []
	for p in _pulls:
		if _active(p):
			out.append("%s:%s" % [p.kind, p.arena])
	return out


## The agent that has the focus in an arena, or null.
func focus_of(arena: String) -> Variant:
	return focus.get(arena)


## The whole frame of the batch camera for the last step, with the same keys. `now` and the state must be of a step.
func build_frame() -> Dictionary:
	var pose: ArenaRules.Pose = ArenaRules.pose_at(move, now, width)
	var fv: ArenaRules.View = move.from_view
	var frame_arena: Variant = null
	var frame_from: Variant = null
	var frame_arena_from: Variant = null
	if view.kind == "arena":
		frame_arena = view.arena
	else:
		frame_from = view.origin
	if fv.kind == "arena":
		frame_arena_from = fv.arena
	return {
		"t": now,
		"mode": mode,
		"follow": follow.duplicate(),
		"pace": pace,
		"held": held,
		"letters": letters.duplicate(),
		"pages": pages.duplicate(),
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
		"pending": pending(),
	}


# ---------------------------------------------------------------- one step

## One step of the rules, at the time `s * step`. `advance()` calls this.
func step(s: int) -> void:
	now = float(s) * float(o["step"])
	_apply_topology()
	if s == 0:
		_prev_letters = letters.duplicate()
	_closed_view()
	_prev_letters = letters.duplicate()
	_apply_inputs()
	var arrived: float = move.t0 + move.dur
	_serve(arrived)
	var was_held: bool = held
	held = _auto(arrived)
	if held != was_held:
		held_changed.emit(held)
	_focus_step()
	_prune()
	if record_frames:
		frames.append(build_frame())


## The open arenas at `now`: the changes that came in, whose time has come.
func _apply_topology() -> void:
	var rest: Array[Dictionary] = []
	var due: Array[Dictionary] = []
	for change in _topology:
		if float(change["t"]) <= now + EPS:
			due.append(change)
		else:
			rest.append(change)
	if not due.is_empty():
		_topology = rest
		_topology_dirty = true
		# an earlier time goes first, and equal times keep the order of arrival
		var order: Array = []
		for i in due.size():
			order.append(i)
		order.sort_custom(
			func(a: int, b: int) -> bool:
				var ta: float = float(due[a]["t"])
				var tb: float = float(due[b]["t"])
				return ta < tb or (ta == tb and a < b)
		)
		for index: int in order:
			var letter: String = str(due[index]["letter"])
			if bool(due[index]["open"]):
				_open_set[letter] = true
			else:
				_open_set.erase(letter)
	if _topology_dirty:
		_topology_dirty = false
		var list: Array[String] = []
		for letter: String in _open_set:
			list.append(letter)
		list.sort_custom(ArenaRules.by_name)
		letters = list
		pages = ArenaRules._pages_of(letters, _gutter)
		width = ArenaRules._world_width(pages, _gutter)


func _agent_key(n: Variant) -> Variant:
	if typeof(n) == TYPE_FLOAT and n == floorf(n):
		return int(n)
	return n


func _drop_superseded(key: Variant, t: float) -> void:
	for list: Array[Dictionary] in [_fail_events, _done_events]:
		var i: int = list.size() - 1
		while i >= 0:
			if list[i]["n"] == key and float(list[i]["t"]) < t:
				list.remove_at(i)
			i -= 1


func _page_of(letter: String) -> int:
	return int(ArenaRules._place(letter, _gutter)["page"])


func _idx(letter: String) -> int:
	return letters.find(letter)


func _here() -> int:
	if view.kind == "arena":
		return _page_of(view.arena) if view.arena != "" else 0
	return view.page


func _pose_of(next: ArenaRules.View) -> ArenaRules.Pose:
	return ArenaRules.arena_pose(next.arena, o) if next.kind == "arena" else ArenaRules.page_pose(next.page, o)


func _go(next: ArenaRules.View, kind: String, apart: int, why: String, n: Variant) -> void:
	var p: ArenaRules.Pose = ArenaRules.pose_at(move, now, width)
	var m: ArenaRules.Move = ArenaRules.Move.new()
	m.from_pose = ArenaRules.Pose.new(p.cx, p.cy, p.s)
	m.to_pose = _pose_of(next)
	m.t0 = now
	m.dur = ArenaRules.move_duration(kind, apart, o)
	m.peak = 0.0 if bool(o.get("reduced_motion", false)) else ArenaRules.peak_for(kind, apart, o)
	m.from_view = view
	move = m
	view = next
	cause_n = n
	var to: String = next.arena if next.kind == "arena" else "page %d" % (next.page + 1)
	var entry: Dictionary = { "t": now, "to": to, "why": why }
	move_id += 1
	var widest: float = maxf(m.peak, maxf(m.from_pose.s, m.to_pose.s))
	var detail: Dictionary = entry.duplicate()
	detail.merge({ "id": move_id, "kind": kind, "apart": apart, "dur": m.dur, "peak": m.peak, "wide": widest >= LONG_MOVE_ROOMS })
	log.append(entry)
	moves.append(detail)
	if log.size() > LOG_LIMIT:
		log.pop_front()
		moves.pop_front()
	moved.emit(detail)


func _cut(next: ArenaRules.View) -> void:
	var p: ArenaRules.Pose = _pose_of(next)
	var m: ArenaRules.Move = ArenaRules.Move.new()
	m.from_pose = p
	m.to_pose = p
	m.t0 = now
	m.from_view = next
	move = m
	view = next


## To an arena: a slide on the same page, a fly to another, a zoom in from the overview of its page. `letter` may be null.
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
	_go(ArenaRules.View.of_arena(target), kind, absi(b - a), why, n)


## To a page of the overview: a zoom out from one of its arenas, a scroll from another page. `page` may be null.
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
	_go(ArenaRules.View.of_page(target, origin), kind, absi(target - a), why, null)


func _active(p: Pull) -> bool:
	return now >= p.t and now < p.until and not _served.has(p.id) and letters.has(p.arena)


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
	for p in _pulls:
		if p.kind == "approval" and now >= p.t and now < p.until and others.has(p.arena):
			if oldest == null or p.t < oldest.t:
				oldest = p
	if oldest != null:
		return oldest.arena
	for list: Array[Dictionary] in [_fail_events, _done_events]:
		# the last one in the order of arrival wins
		var i: int = list.size() - 1
		while i >= 0:
			var e: Dictionary = list[i]
			if float(e["t"]) <= now and others.has(e["arena"]):
				return e["arena"]
			i -= 1
	return null


func _tab_target() -> Variant:
	if _idx(view.origin) >= 0:
		return view.origin
	for l in letters:
		if _page_of(l) == view.page:
			return l
	return null


## What is on screen has closed: a cut to the left neighbour (or the right one), or to the nearest page.
func _closed_view() -> void:
	if view.kind == "arena" and view.arena != "" and _idx(view.arena) < 0:
		var old: int = _prev_letters.find(view.arena)
		var next: Variant = null
		var left: Array[String] = _prev_letters.slice(0, maxi(0, old))
		left.reverse()
		for l in left:
			if _idx(l) >= 0:
				next = l
				break
		if next == null:
			for l: String in _prev_letters.slice(old + 1):
				if _idx(l) >= 0:
					next = l
					break
		if next == null and not letters.is_empty():
			next = letters[0]
		if next != null:
			_cut(ArenaRules.View.of_arena(str(next)))
			_log_cut(str(next))
	elif view.kind == "page" and not pages.has(view.page):
		if not pages.is_empty():
			var best: int = pages[0]
			for p in pages:
				if absi(p - view.page) < absi(best - view.page):
					best = p
			_cut(ArenaRules.View.of_page(best, view.origin))
			_log_cut("page %d" % (best + 1))


func _log_cut(to: String) -> void:
	var entry: Dictionary = { "t": now, "to": to, "why": "closed" }
	move_id += 1
	var detail: Dictionary = entry.duplicate()
	detail.merge({ "id": move_id, "kind": "cut", "apart": 0, "dur": 0.0, "peak": 0.0, "wide": false })
	log.append(entry)
	moves.append(detail)
	moved.emit(detail)


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


func _set_mode(next: String) -> void:
	if mode != next:
		mode = next
		mode_changed.emit(mode)


## What the person does: the inputs whose time has come.
func _apply_inputs() -> void:
	if _inputs.is_empty():
		return
	var rest: Array[Dictionary] = []
	var due: Array[Dictionary] = []
	for entry in _inputs:
		if float(entry["t"]) <= now + EPS:
			due.append(entry)
		else:
			rest.append(entry)
	_inputs = rest
	# equal times keep the order of arrival, and an earlier time goes first
	var order: Array = []
	for i in due.size():
		order.append(i)
	order.sort_custom(
		func(a: int, b: int) -> bool:
			var ta: float = float(due[a]["t"])
			var tb: float = float(due[b]["t"])
			return ta < tb or (ta == tb and a < b)
	)
	for index: int in order:
		_apply_input(due[index])


func _apply_input(i: Dictionary) -> void:
	var key: Variant = i.get("key")
	var click: Variant = i.get("click")
	if key == "F":
		_set_mode("MANUAL" if mode == "AUTO" else "AUTO")
	elif _truthy(i.get("toggle")):
		var kind: String = i["toggle"]
		follow[kind] = not bool(follow.get(kind, false))
	elif _truthy(i.get("manual")):
		_set_mode("MANUAL")
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
			var at_page: int = pages.find(view.page) + d
			var page_target: Variant = null
			if at_page >= 0 and at_page < pages.size():
				page_target = pages[at_page]
			_open_page(page_target, "key")
		else:
			_set_mode("MANUAL")
			_move_to(_letter_at(_idx(view.arena) + d), "key")
	elif key == "N":
		_set_mode("MANUAL")
		_move_to(_needs_you(), "N")
	elif click == "tab" or click == "cell":
		_set_mode("MANUAL")
		_move_to(i.get("arena"), "click")
	elif click == "page":
		_open_page(i.get("page"), "click")


## The camera is at an arena: what it shows there has been seen.
func _serve(arrived: float) -> void:
	if view.kind == "arena" and now >= arrived - EPS:
		for p in _pulls:
			if _active(p) and p.arena == view.arena:
				_served[p.id] = true
				if p.kind == "open":
					ribbon = { "arena": p.arena, "t": now }
					ribbon_started.emit(p.arena, now)
		if cause_n != null:
			focus[view.arena] = cause_n
			focus_since[view.arena] = now
			cause_n = null


## Follow AUTO (see `CameraSim._auto` in arena_rules.gd for the rules). Returns true when a move waits for the pace limit.
func _auto(arrived: float) -> bool:
	var is_held: bool = false
	var window: float = float(o["pace_window"])
	while not _auto_moves.is_empty() and _auto_moves[0] <= now - window + EPS:
		_auto_moves.pop_front()
	if mode == "AUTO" and view.kind == "arena" and now >= arrived + float(o["hold_after_move"]) - EPS:
		var reading: bool = false
		for p in _pulls:
			if p.kind == "approval" and p.arena == view.arena and now >= p.t and now < p.until and now - maxf(p.t, arrived) < float(o["hold_approval"]) - EPS:
				reading = true
				break
		if not reading:
			var target: Variant = null
			var why: String = ""
			var n: Variant = null
			var pull: Pull = null
			for p in _pulls:
				if bool(follow[p.kind]) and _active(p) and p.arena != view.arena:
					if pull == null or p.rank < pull.rank or (p.rank == pull.rank and p.t < pull.t):
						pull = p
			if pull != null:
				target = pull.arena
				why = "pull:" + pull.kind
				n = pull.n
			elif bool(follow["activity"]) and now - _activity_of(view.arena) >= float(o["quiet"]) - EPS and now - arrived >= float(o["min_stay"]) - EPS:
				var best: float = -INF
				for l in letters:
					if l == view.arena:
						continue
					var last: float = _activity_of(l)
					if now - last < float(o["quiet"]) and (target == null or last > best):
						target = l
						best = last
				why = "activity"
			if target != null:
				var past_pace: bool = pull != null and pull.kind == "approval"
				if past_pace or float(_auto_moves.size()) < maxf(1.0, ArenaRules.js_round(pace * window)):
					_move_to(target, why, n)
					_auto_moves.append(now)
				else:
					is_held = true
	return is_held


func _activity_of(letter: String) -> float:
	var last: float = float(_last_activity.get(letter, -INF))
	return last if last <= now + EPS else -INF


## The focus inside each arena: in AUTO the newest event, held `focus_hold` s, and a failure, an approval or a finished
## turn at once; in MANUAL it stays where it is.
func _focus_step() -> void:
	var hold: float = float(o["focus_hold"])
	for l in letters:
		var queue: Array = _focus_queue.get(l, [])
		var taken: int = 0
		while taken < queue.size() and float((queue[taken] as Dictionary)["t"]) <= now + EPS:
			var e: Dictionary = queue[taken]
			_newest_of[l] = e
			if bool(e["priority"]):
				_prio_of[l] = e
			taken += 1
		if taken > 0:
			queue = queue.slice(taken)
			_focus_queue[l] = queue
		if mode == "MANUAL" and focus.get(l) != null:
			continue
		var prio: Variant = _prio_of.get(l)
		var newest: Variant = _newest_of.get(l)
		if prio != null:
			_prio_of[l] = null
			if (prio as Dictionary).get("n") != focus.get(l):
				focus[l] = (prio as Dictionary).get("n")
				focus_since[l] = now
			continue
		if newest != null and (newest as Dictionary).get("n") != focus.get(l) and now - float(focus_since.get(l, -INF)) >= hold - EPS:
			focus[l] = (newest as Dictionary).get("n")
			focus_since[l] = now


## Forgets the pulls that can never be active again, so that a long session does not grow without end.
func _prune() -> void:
	if _pulls.is_empty():
		return
	var kept: Array[Pull] = []
	for p in _pulls:
		var over: bool = now >= p.until
		if not over and p.kind != "approval" and _served.has(p.id):
			over = true
		if over:
			_served.erase(p.id)
		else:
			kept.append(p)
	_pulls = kept
