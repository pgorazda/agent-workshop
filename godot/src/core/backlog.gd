extends RefCounted
## The backlog rule (choice 10 of the plan, choice 7 of the browser client plan).
##
## A window can be hidden, or the app can be busy, while events keep coming in. A penguin may then come back to a long
## queue. When a queue is longer than LIMIT events, this rule drops the oldest events that no longer matter and keeps:
##   * the last KEEP_LAST events,
##   * every `done` event,
##   * a prompt for a permission that is still open (no later call or end of a turn in the queue),
##   * a call that is still open (a `tool_start` without its `tool_end`).
## What it drops: finished calls (the `tool_start` and its `tool_end`, always together), `thinking` events,
## prompts that were answered, `error` events and events of an unknown type. It drops the oldest first, and stops as
## soon as the queue is short enough. It may leave a queue longer than LIMIT when everything left must stay.

## "About 20" events.
const LIMIT := 20
const KEEP_LAST := 6

## The event types that the rule knows by name. Any other type is "unknown" and can be dropped.
const KNOWN_TYPES: Array[String] = ["tool_start", "tool_end", "done", "waiting_permission", "thinking", "error", "session_start", "subagent_start", "subagent_end"]


## Trims `queue` (an Array of events, the oldest first) in place. Returns the number of events that were dropped.
static func trim(queue: Array, limit: int = LIMIT, keep_last: int = KEEP_LAST) -> int:
	if queue.size() <= limit:
		return 0
	var count: int = queue.size()
	var protected_from: int = maxi(0, count - keep_last)
	# units that can go: an Array of Arrays of indices, in the order of their first index
	var units: Array = []
	var open_start: Dictionary = { }
	var pair_end: Dictionary = { }
	for i in count:
		var event: RefCounted = queue[i]
		if event.type == "tool_start":
			open_start[event.id] = i
		elif event.type == "tool_end":
			if open_start.has(event.id):
				pair_end[open_start[event.id]] = i
				open_start.erase(event.id)
	for i in count:
		var event: RefCounted = queue[i]
		match event.type:
			"tool_start":
				if pair_end.has(i):
					units.append([i, pair_end[i]])
			"tool_end":
				pass # a part of a pair, or an end with no start: it stays with its start
			"done":
				pass
			"waiting_permission":
				if _is_answered(queue, i):
					units.append([i])
			"thinking", "error", "session_start", "subagent_start", "subagent_end":
				units.append([i])
			_:
				if not KNOWN_TYPES.has(event.type):
					units.append([i])
	units.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var drop: Dictionary = { }
	for unit: Array in units:
		if count - drop.size() <= limit:
			break
		var last: int = unit[unit.size() - 1]
		if last >= protected_from:
			continue
		for index: int in unit:
			drop[index] = true
	var indices: Array = drop.keys()
	indices.sort()
	indices.reverse()
	for index: int in indices:
		queue.remove_at(index)
	return indices.size()


## True when a later event shows that the prompt at `index` is over: a call, an end, an error or the end of a turn.
static func _is_answered(queue: Array, index: int) -> bool:
	for i in range(index + 1, queue.size()):
		var later: RefCounted = queue[i]
		if ["tool_start", "tool_end", "done", "error"].has(later.type):
			return true
	return false

