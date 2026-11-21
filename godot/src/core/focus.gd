extends RefCounted
## The focus of one room: which penguin has the ring and the label.
## The ring and the label are drawn elsewhere. This class only decides who has the focus.
##
## Two modes:
##   AUTO    the focus follows the newest event, held for at least HOLD seconds so that it does not flicker. A failure,
##           a request for an approval and a finished turn take it at once. Such a priority event is used up even when its
##           agent has the focus already, so that it does not pin the focus (as in `simulateCamera` of arena-rules.js).
##   MANUAL  the focus moves only when the person clicks a penguin or its card. New events do not move it. (It has no
##           focus until the first event or click: the first event gives it one.)
##
## `step()` is the same rule as one pass of `simulateCamera` for one arena. The mockup runs it every 1/30 s and this
## client every 1/60 s, so a switch can come up to 1/60 s earlier.
## An agent is a String key (see `director.gd`). The class does not know penguins.

enum Mode { AUTO, MANUAL }

## The shortest time that a focus stays, in seconds.
const HOLD := 1.5
const EPSILON := 1e-9

var mode: Mode = Mode.AUTO
## The key of the agent with the focus, or "".
var focused: String = ""

var _since: float = -1.0e9
var _newest: String = ""
var _priority: String = ""


## An event of agent `key` came in. `priority` is true for a failure, a request for an approval and a finished turn.
func note(key: String, priority: bool) -> void:
	_newest = key
	if priority:
		_priority = key


## Moves the focus when the rules say so. Call it once in each simulation step.
func step(now: float) -> void:
	if mode == Mode.MANUAL and focused != "":
		_priority = ""
		return
	if _priority != "":
		var wanted: String = _priority
		_priority = ""
		if wanted != focused:
			focused = wanted
			_since = now
		return
	if _newest != "" and _newest != focused and now - _since >= HOLD - EPSILON:
		focused = _newest
		_since = now


## The person clicked a penguin or its card. The focus goes there in both modes. In AUTO it stays for HOLD seconds at least.
func click(key: String, now: float) -> void:
	focused = key
	_since = now
	_priority = ""


## The key F: AUTO becomes MANUAL and the other way round. Returns the new mode.
func toggle_mode() -> Mode:
	mode = Mode.MANUAL if mode == Mode.AUTO else Mode.AUTO
	_priority = ""
	return mode


func mode_name() -> String:
	return "AUTO" if mode == Mode.AUTO else "MANUAL"


## An agent left the room. If it had the focus, the focus is free: the next step gives it to the newest event.
func remove(key: String) -> void:
	if _newest == key:
		_newest = ""
	if _priority == key:
		_priority = ""
	if focused == key:
		focused = ""
		_since = -1.0e9
