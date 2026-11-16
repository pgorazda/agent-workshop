extends RefCounted
## The activity log and the cards (docs/2d-view-plan.md, choice 6 and "Several agents"; phase G-6).
##
## The model is built from the events that the director also gets: `tool_start`, `tool_end`, `waiting_permission`, `thinking`,
## `done`, `error` and `subagent_*`. For each agent it keeps the last lines with their state, and the one card that the bar
## shows. It has no drawing and no clock: the caller gives the time.
##
## A line has a state: "run" (a call that is open), "OK", "FAIL", "WAIT" (an approval is needed) or "" (a plain line, such as
## the end of a turn). The card of an agent has the state of its newest event: "run", "OK", "FAIL", "WAIT", "DONE" or "".
##
## Numbers. The director gives each agent a number when it first appears. The number stays until the agent leaves. A helper
## wears the number of its parent, and it adds to the "+N" on the parent's card. The events of a helper do not make lines.
##
## The rules for the cards are in the plan: full cards up to five agents (number, framework, session, icon, target, status) and
## compact cards from six (number, short name, icon, status). Long targets are cleaned here (one line, at most `MAX_TEXT`
## characters) and cut to a width by `TextArt.fit`, because only the art knows the width of a letter.

const Event := preload("res://src/core/event.gd")

## The cards are compact when an arena has more agents than this.
const FULL_CARDS_UP_TO := 5
## The most lines kept for one agent, and the lines that the one-agent bar shows.
const MAX_LINES := 6
const SHOWN_LINES := 3
## A target is cut to this many characters. The art cuts it again to a width.
const MAX_TEXT := 160
## "X joined" shows in the bar for this long, in seconds.
const JOIN_NOTICE_SECONDS := 2.2
## The short names of the compact cards. A framework that is not here gets its own name, cut to SHORT_MAX.
const SHORT_NAMES := { "claude-code": "claude", "opencode": "opencode", "pi": "pi", "hermes": "hermes" }
const SHORT_MAX := 8
## The picture in the atlas ("icon/<name>") of a tool category.
const ICONS := {
	"read": "read", "search": "search", "write": "write", "exec": "exec", "web": "web", "delegate": "delegate",
	"think": "think", "ask_permission": "ask", "other": "other",
}

## key -> the record of an agent: { key, number, arena, framework, session, cord, state, icon, target, tool, helpers, calls,
## joined, last_event, lines, waiting_since, turn_calls, turn_helpers, turn_start }.
var agents: Dictionary = { }
## The number of tool calls that started, in all agents that are here or left.
var calls: int = 0
## The agent that joined last: { key, t }, or an empty Dictionary.
var last_join: Dictionary = { }

var _order: Array[String] = []
var _by_arena: Dictionary = { } # arena -> the keys of its agents, in the order in which they joined (the order of their numbers)
var _helper_parent: Dictionary = { } # helper key -> parent key


# ---------------------------------------------------------------- who is here

## An agent appeared. The director gives its number and its arena.
func agent_joined(key: String, number: int, arena: String, framework: String, session: String, cord: String, now: float) -> void:
	if agents.has(key):
		return
	agents[key] = {
		"key": key, "number": number, "arena": arena, "framework": framework, "session": session, "cord": cord,
		"state": "", "icon": "", "target": "joined", "tool": "", "helpers": 0, "calls": 0, "joined": now, "last_event": now,
		"lines": [], "waiting_since": -1.0, "turn_calls": 0, "turn_helpers": 0, "turn_start": now,
	}
	_order.append(key)
	if not _by_arena.has(arena):
		_by_arena[arena] = [] as Array[String]
	(_by_arena[arena] as Array[String]).append(key)
	last_join = { "key": key, "t": now }


## An agent left the room.
func agent_left(key: String, _now: float) -> void:
	if not agents.has(key):
		return
	var left_arena: String = str((agents[key] as Dictionary)["arena"])
	if _by_arena.has(left_arena):
		(_by_arena[left_arena] as Array[String]).erase(key)
	agents.erase(key)
	_order.erase(key)
	for helper_key: String in _helper_parent.keys():
		if _helper_parent[helper_key] == key:
			_helper_parent.erase(helper_key)
	if last_join.get("key", "") == key:
		last_join = { }


## A helper started. It counts on the card of its parent.
func helper_started(parent_key: String, helper_key: String, now: float) -> void:
	if not agents.has(parent_key) or _helper_parent.has(helper_key):
		return
	_helper_parent[helper_key] = parent_key
	var parent: Dictionary = agents[parent_key]
	parent["helpers"] = int(parent["helpers"]) + 1
	parent["turn_helpers"] = int(parent["turn_helpers"]) + 1
	parent["last_event"] = now


## A helper ended.
func helper_ended(helper_key: String, now: float) -> void:
	var parent_key: Variant = _helper_parent.get(helper_key)
	if parent_key == null:
		return
	_helper_parent.erase(helper_key)
	if agents.has(parent_key):
		var parent: Dictionary = agents[parent_key]
		parent["helpers"] = maxi(0, int(parent["helpers"]) - 1)
		parent["last_event"] = now


# ---------------------------------------------------------------- the events

## An event that went to the actor with this key (an agent, or a helper with its own events).
func note_event(event: RefCounted, key: String, now: float) -> void:
	if _helper_parent.has(key):
		# a helper's own work does not make lines or change the card: it only shows that its parent is busy
		var parent_key: String = _helper_parent[key]
		if agents.has(parent_key):
			(agents[parent_key] as Dictionary)["last_event"] = now
		return
	if not agents.has(key):
		return
	var a: Dictionary = agents[key]
	a["last_event"] = now
	match event.type:
		"tool_start":
			_tool_start(a, event, now)
		"tool_end":
			_tool_end(a, event)
		"waiting_permission":
			_wait(a, event, now)
		"thinking":
			_thinking(a)
		"done":
			_done(a, now)
		"error":
			_error(a, event)
		"session_start", "subagent_start", "subagent_end":
			pass
		_:
			_end_wait(a)
			_close_thinking(a)
			_push(a, _line("other", str(event.type), "", "OK", ""))


func _tool_start(a: Dictionary, event: RefCounted, now: float) -> void:
	_end_wait(a)
	var category: String = event.category if event.category != "" else "other"
	if category == "think":
		_thinking(a)
		return
	_close_thinking(a)
	if int(a["turn_calls"]) == 0 and a["state"] == "DONE":
		a["turn_start"] = now
	var icon: String = str(ICONS.get(category, "other"))
	var line: Dictionary = _line(icon, event.tool, event.target, "run", event.id)
	line["category"] = category
	_push(a, line)
	a["calls"] = int(a["calls"]) + 1
	a["turn_calls"] = int(a["turn_calls"]) + 1
	calls += 1
	a["state"] = "run"
	a["icon"] = icon
	a["target"] = line["target"]
	a["tool"] = event.tool


func _tool_end(a: Dictionary, event: RefCounted) -> void:
	var line: Variant = _open_line(a, event.id)
	var failed: bool = event.ok == false
	if line != null:
		(line as Dictionary)["state"] = "FAIL" if failed else "OK"
	elif not failed:
		# the end of a call that the log has no line for: nothing to change
		_end_wait(a)
		return
	_end_wait(a, line)
	a["waiting_since"] = -1.0
	if failed:
		a["state"] = "FAIL"
		if event.error != "":
			_push(a, _line("", "", event.error, "", "", true))
	else:
		a["state"] = "OK"


func _wait(a: Dictionary, event: RefCounted, now: float) -> void:
	_close_thinking(a)
	var line: Variant = _open_line(a, "")
	if line == null:
		line = _line("ask", event.tool, event.target, "WAIT", "")
		_push(a, line as Dictionary)
	else:
		(line as Dictionary)["state"] = "WAIT"
		(line as Dictionary)["icon"] = "ask"
		if event.target != "" and str((line as Dictionary)["target"]) == "":
			(line as Dictionary)["target"] = clean(event.target)
	if str(a["state"]) != "WAIT":
		a["waiting_since"] = now
	a["state"] = "WAIT"
	a["icon"] = "ask"
	if event.target != "":
		a["target"] = clean(event.target)


func _thinking(a: Dictionary) -> void:
	_end_wait(a)
	var lines: Array = a["lines"]
	if not lines.is_empty() and bool((lines.back() as Dictionary).get("thinking", false)):
		return
	var line: Dictionary = _line("think", "", "Thinking", "run", "")
	line["thinking"] = true
	_push(a, line)
	a["state"] = "run"
	a["icon"] = "think"
	a["target"] = "thinking"
	a["tool"] = ""


func _done(a: Dictionary, now: float) -> void:
	_end_wait(a)
	_close_thinking(a)
	var seconds: int = int(roundf(now - float(a["turn_start"])))
	var helpers: int = int(a["turn_helpers"])
	var detail: String = "%d call%s" % [int(a["turn_calls"]), "" if int(a["turn_calls"]) == 1 else "s"]
	if helpers > 0:
		detail += "  ·  %d helper%s" % [helpers, "" if helpers == 1 else "s"]
	detail += "  ·  %d s" % seconds
	var line: Dictionary = _line("star", "", "Turn complete", "", "")
	line["detail"] = detail
	_push(a, line)
	a["state"] = "DONE"
	a["icon"] = "star"
	a["target"] = "turn complete"
	a["tool"] = ""
	a["turn_calls"] = 0
	a["turn_helpers"] = 0
	a["turn_start"] = now


func _error(a: Dictionary, event: RefCounted) -> void:
	_end_wait(a)
	_close_thinking(a)
	_push(a, _line("exec", "error", event.message if event.message != "" else event.error, "FAIL", ""))
	a["state"] = "FAIL"
	a["icon"] = "exec"
	a["target"] = clean(event.message if event.message != "" else event.error)


# ---------------------------------------------------------------- lines

static func _line(icon: String, tool: String, target: String, state: String, id: String, is_error: bool = false) -> Dictionary:
	return { "icon": icon, "tool": clean(tool), "target": clean(target), "state": state, "id": id, "error": is_error, "thinking": false, "detail": "" }


func _push(a: Dictionary, line: Dictionary) -> void:
	var lines: Array = a["lines"]
	lines.append(line)
	while lines.size() > MAX_LINES:
		lines.pop_front()


## The line of a call that is still open: the one with this id, or the newest open one when the id is empty or unknown.
func _open_line(a: Dictionary, id: String) -> Variant:
	var lines: Array = a["lines"]
	var i: int = lines.size() - 1
	var newest: Variant = null
	while i >= 0:
		var line: Dictionary = lines[i]
		var open: bool = (line["state"] == "run" or line["state"] == "WAIT") and not bool(line["thinking"])
		if open:
			if id != "" and str(line["id"]) == id:
				return line
			if newest == null:
				newest = line
		i -= 1
	if id != "" and newest != null and str((newest as Dictionary)["id"]) != "" and str((newest as Dictionary)["id"]) != id:
		return null
	return newest


## A wait ends with the next event of the agent: a line that waits is running again, unless it is the call that just ended.
func _end_wait(a: Dictionary, except: Variant = null) -> void:
	for line: Dictionary in a["lines"]:
		if line["state"] == "WAIT" and not is_same(line, except):
			line["state"] = "run"
			var category: String = str(line.get("category", ""))
			if category != "":
				line["icon"] = str(ICONS.get(category, "other"))
	if a["state"] == "WAIT":
		a["state"] = "run"
		a["waiting_since"] = -1.0
		# the card keeps the icon of the call that waited: an approval that ended with the call shows "ask" and OK
		var open: Variant = _open_line(a, "")
		if open != null:
			a["icon"] = (open as Dictionary)["icon"]


## A spell of thinking is only on the log while it lasts.
func _close_thinking(a: Dictionary) -> void:
	var lines: Array = a["lines"]
	var i: int = lines.size() - 1
	while i >= 0:
		if bool((lines[i] as Dictionary)["thinking"]):
			lines.remove_at(i)
		i -= 1


# ---------------------------------------------------------------- what the interface reads

## One line of text from a target: no line breaks or control characters, runs of spaces made one, at most MAX_TEXT characters.
static func clean(text: String) -> String:
	var out: String = ""
	var space: bool = false
	for i in mini(text.length(), MAX_TEXT * 2):
		var code: int = text.unicode_at(i)
		if code <= 32 or code == 127:
			space = true
			continue
		if space and not out.is_empty():
			out += " "
		space = false
		out += text[i]
	if out.length() > MAX_TEXT:
		out = out.substr(0, MAX_TEXT)
	return out


## The name that a compact card shows.
static func short_name(framework: String) -> String:
	if SHORT_NAMES.has(framework):
		return str(SHORT_NAMES[framework])
	return framework.substr(0, SHORT_MAX)


## A short form of a session id for a card: ids of 6 characters or less stay, and a longer one shows its last 4 characters
## (ids that are made at random differ at the end, and the number is the real name anyway).
static func short_session(session: String) -> String:
	return session if session.length() <= 6 else session.substr(session.length() - 4)


## The last `count` lines of an agent, oldest first. Each line is { icon, tool, target, state, id, error, thinking, detail }.
func lines_of(key: String, count: int = SHOWN_LINES) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not agents.has(key):
		return out
	var lines: Array = (agents[key] as Dictionary)["lines"]
	for i in range(maxi(0, lines.size() - count), lines.size()):
		out.append(lines[i])
	return out


## The agents that are in an arena, in the order of their numbers. An empty `arena` gives every agent.
func agents_in(arena: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# an arena has a list of its own: the bar asks for the agents of each arena in every frame, and a scene has up to 40 arenas
	var keys: Array[String] = _order if arena == "" else (_by_arena.get(arena, [] as Array[String]) as Array[String])
	for key in keys:
		out.append(agents[key])
	out.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return int(p["number"]) < int(q["number"]))
	return out


func agent_count(arena: String = "") -> int:
	return agents_in(arena).size()


func helper_count(arena: String = "") -> int:
	var total: int = 0
	for a in agents_in(arena):
		total += int(a["helpers"])
	return total


## True when the cards of an arena are compact: more than FULL_CARDS_UP_TO agents.
func is_compact(arena: String = "") -> bool:
	return agent_count(arena) > FULL_CARDS_UP_TO


## The cards of an arena, in the order of the numbers: { key, number, framework, short, session, cord, state, icon, target,
## helpers, compact, waiting_since }.
func cards(arena: String = "") -> Array[Dictionary]:
	var list: Array[Dictionary] = agents_in(arena)
	var compact: bool = list.size() > FULL_CARDS_UP_TO
	var out: Array[Dictionary] = []
	for a in list:
		out.append({
			"key": a["key"], "number": a["number"], "framework": a["framework"], "short": short_name(str(a["framework"])),
			"session": short_session(str(a["session"])), "cord": a["cord"], "state": a["state"], "icon": a["icon"],
			"target": a["target"], "helpers": a["helpers"], "compact": compact, "waiting_since": a["waiting_since"],
		})
	return out


## The agents of an arena that wait for an approval, the oldest first (the notices at the sign post stack in this order).
func waiting(arena: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in agents_in(arena):
		if a["state"] == "WAIT":
			out.append(a)
	out.sort_custom(
		func(p: Dictionary, q: Dictionary) -> bool:
			if float(p["waiting_since"]) != float(q["waiting_since"]):
				return float(p["waiting_since"]) < float(q["waiting_since"])
			return int(p["number"]) < int(q["number"])
	)
	return out


## What the label of the focused agent says: { text, kind }. `kind` is "fail" for a failure (the text starts with the cross),
## "wait" for an approval, "done" for a finished turn and "normal" for the rest.
func focus_label(key: String) -> Dictionary:
	if not agents.has(key):
		return { "text": "", "kind": "normal" }
	var a: Dictionary = agents[key]
	match str(a["state"]):
		"FAIL":
			var detail: String = ""
			var lines: Array = a["lines"]
			if not lines.is_empty() and bool((lines.back() as Dictionary)["error"]):
				detail = str((lines.back() as Dictionary)["target"])
			return { "text": "✗ %s" % (detail if detail != "" else "failed"), "kind": "fail" }
		"WAIT":
			return { "text": "needs approval", "kind": "wait" }
		"DONE":
			return { "text": "turn complete", "kind": "done" }
	return { "text": str(a["target"]), "kind": "normal" }


## The agent that joined less than JOIN_NOTICE_SECONDS ago, or an empty Dictionary.
func recent_join(now: float) -> Dictionary:
	if last_join.is_empty() or now - float(last_join["t"]) >= JOIN_NOTICE_SECONDS or now < float(last_join["t"]):
		return { }
	return agents.get(last_join["key"], { })
