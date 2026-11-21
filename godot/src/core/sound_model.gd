extends RefCounted
## The sound model: which event plays which sound, and the sound state. It has no audio call, no node and no clock.
## The player (`src/view/sound_player.gd`) plays what this model says. The rules come from
## `soundCues` and `arenas.js` of the mockup.
##
## The state: one tune of four (or none), the event sounds on or off, and all sound on or off. All sound starts off. Picking a tune,
## or turning the event sounds on or off, also turns all sound on (as in the mockup). The key M turns all sound on or off, and the
## tune and the event setting stay.
##
## The cues. The actors say what happened on the simulation clock: a cue is { name, t, arena }. `offer` takes the cues of a step and
## keeps those that sound. `due(now)` gives the names whose time has come. The rules of `offer`:
##   * a hammer's tink at each stroke at the workbench, the desk bell when work is handed to a helper, a flop for a failed call, a chime
##     when an agent starts to wait for approval, a fanfare for a finished turn (the actors make these cues);
##   * with several arenas, the chime and the fanfare sound from every arena, because an approval or a finished turn needs the person
##     wherever it happens. The other sounds sound only from the arena that the camera rests on (not in the overview, not while it moves);
##   * nothing is kept while sound is off or the event sounds are off;
##   * two cues of one sound less than MIN_GAP apart count as one.
## A cue that is more than STALE_AFTER seconds late is dropped (a window that was not shown, or a long frame). A burst would be noise.

## The four tunes: the file name (`art/sound/<name>.wav`), the label of the menu and its short note. The names equal the tune names of
## `art/sound_src/sound.js`.
const TUNES: Array[Dictionary] = [
	{ "name": "krakowiak", "label": "krakowiak", "about": "lively, 2/4" },
	{ "name": "kujawiak", "label": "kujawiak", "about": "calm, 3/4" },
	{ "name": "oberek", "label": "oberek", "about": "fast, 3/8" },
	{ "name": "goralski", "label": "góralski", "about": "highland" },
]
## The event sounds (`art/sound/<name>.wav`).
const EVENT_SOUNDS: Array[String] = ["tink", "bell", "flop", "chime", "fanfare"]
## These sound from every arena. The others sound only from the arena that the camera rests on.
const EVERYWHERE: Array[String] = ["chime", "fanfare"]
const DEFAULT_TUNE := "krakowiak"
## How long a toast shows, in seconds of wall-clock time.
const TOAST_SECONDS := 2.0
## A cue that is later than this (in seconds of simulation time) is dropped.
const STALE_AFTER := 0.5
## At most this many cues wait. The oldest go first.
const MAX_PENDING := 64
## Two cues of one sound closer than this (in seconds) count as one: a window that was not shown makes its cues in a burst.
const MIN_GAP := 0.05
## The rows of the menu: 0 to 3 are the tunes, 4 is "no music", 5 is the event sounds. -1 is none.
const ROW_NO_MUSIC := 4
const ROW_EVENTS := 5

## All sound is on. It starts off.
var on: bool = false
## The name of the tune, or "" for no music.
var tune: String = DEFAULT_TUNE
## The event sounds are on (they sound only while `on` is true too).
var events: bool = true
var menu_open: bool = false
## The row under the mouse in the open menu (see ROW_*), or -1.
var hover: int = -1
var toast: String = ""
var toast_until: float = 0.0

var _pending: Array[Dictionary] = []
## sound name -> the time of the last cue that was kept.
var _last_kept: Dictionary = { }
## Counts every change that the player must apply (the tune, `on`, `events`). The player compares it with the last one it saw.
var version: int = 0
## Counts every change that shows in the switch or its menu (the state, the menu, the hover, the toast). The view redraws when it changes.
var revision: int = 0


## The label of a tune, or "off" for none.
static func label_of(tune_name: String) -> String:
	for entry in TUNES:
		if entry["name"] == tune_name:
			return str(entry["label"])
	return "off"


static func is_tune(tune_name: String) -> bool:
	for entry in TUNES:
		if entry["name"] == tune_name:
			return true
	return false


## The tune that plays now, or "" when none plays (sound off, or no music chosen).
func tune_playing() -> String:
	return tune if on else ""


## The event sounds sound now.
func events_playing() -> bool:
	return on and events


## Sets the state at the start from a command-line value: "on" (the default tune, all on), "events" (event sounds only), "off", or the
## name of a tune. Returns false for any other value, and then changes nothing.
func start_with(value: String) -> bool:
	if value == "on":
		_set_state(true, tune, events)
	elif value == "events":
		_set_state(true, "", true)
	elif value == "off":
		_set_state(false, tune, events)
	elif is_tune(value):
		_set_state(true, value, true)
	else:
		return false
	return true


func _set_state(new_on: bool, new_tune: String, new_events: bool) -> void:
	if new_on != on or new_tune != tune or new_events != events:
		version += 1
		revision += 1
	on = new_on
	tune = new_tune
	events = new_events
	if not on:
		clear_pending()


# ---------------------------------------------------------------- changes

## Picks a tune ("" for no music). It turns all sound on. `wall` is the wall-clock time in seconds, for the toast.
func pick_tune(tune_name: String, wall: float) -> void:
	if tune_name != "" and not is_tune(tune_name):
		return
	_set_state(true, tune_name, events)
	_say("music: %s" % label_of(tune_name), wall)


## Turns the event sounds on or off. It turns all sound on.
func toggle_events(wall: float) -> void:
	var now_on: bool = not events
	_set_state(true, tune, now_on)
	_say("event sounds: %s" % ("on" if now_on else "off"), wall)


## Turns all sound on or off (the key M).
func toggle_all(wall: float) -> void:
	var now_on: bool = not on
	_set_state(now_on, tune, events)
	_say("all sound %s   (M)" % ("on" if now_on else "off"), wall)


func toggle_menu() -> void:
	set_menu(not menu_open)


func set_menu(open: bool) -> void:
	if open != menu_open or hover != -1:
		revision += 1
	menu_open = open
	hover = -1


func _say(text: String, wall: float) -> void:
	toast = text
	toast_until = wall + TOAST_SECONDS
	revision += 1


## The toast to show at `wall`, or "".
func toast_at(wall: float) -> String:
	return toast if wall < toast_until else ""


# ---------------------------------------------------------------- keys and clicks

## A key press. Returns true when the sound model used it:
##   M          all sound on or off, always
##   S          opens or closes the menu, always
##   Esc        closes the menu (only when it is open: otherwise the key goes on)
##   1 to 4, 0  a tune, or no music (only while the menu is open)
##   E          the event sounds on or off (only while the menu is open)
## 1 to 3 are the speed of a demo while the menu is closed: the caller asks `menu_open` before it uses them.
func key(keycode: Key, wall: float) -> bool:
	match keycode:
		KEY_M:
			toggle_all(wall)
			return true
		KEY_S:
			toggle_menu()
			return true
	if not menu_open:
		return false
	if keycode == KEY_ESCAPE:
		set_menu(false)
		return true
	if keycode == KEY_E:
		toggle_events(wall)
		return true
	var digit: int = -1
	if keycode >= KEY_0 and keycode <= KEY_9:
		digit = keycode - KEY_0
	elif keycode >= KEY_KP_0 and keycode <= KEY_KP_9:
		digit = keycode - KEY_KP_0
	if digit == 0:
		pick_tune("", wall)
		return true
	if digit >= 1 and digit <= TUNES.size():
		pick_tune(str(TUNES[digit - 1]["name"]), wall)
		return true
	return false


## A left click that hit `hit` (see `SoundUiArt.hit`: kind "pill", "tune" with a `tune` name or "", "events", "menu" or "none").
## Returns true when the click was the sound model's. With the menu open, a click anywhere else closes it and does nothing else.
func click(hit: Dictionary, wall: float) -> bool:
	match str(hit.get("kind", "none")):
		"pill":
			toggle_menu()
			return true
		"tune":
			pick_tune(str(hit["tune"]), wall)
			return true
		"events":
			toggle_events(wall)
			return true
		"menu":
			return true
	if menu_open:
		set_menu(false)
		return true
	return false


## The row under the mouse for a hit (the hover of the menu).
func set_hover_from(hit: Dictionary) -> void:
	var row: int = -1
	match str(hit.get("kind", "none")):
		"tune":
			row = ROW_NO_MUSIC
			for i in TUNES.size():
				if TUNES[i]["name"] == str(hit["tune"]):
					row = i
		"events":
			row = ROW_EVENTS
	var new_hover: int = row if menu_open else -1
	if new_hover != hover:
		revision += 1
	hover = new_hover


# ---------------------------------------------------------------- the cues

## Takes the cues of one step. `rest_arena` is the arena that the camera rests on, or "" when it shows the overview or moves. A cue
## that does not sound is dropped. Returns how many were kept.
func offer(cues: Array[Dictionary], rest_arena: String) -> int:
	if not events_playing():
		return 0
	var kept: int = 0
	for cue in cues:
		var cue_name: String = str(cue["name"])
		if not EVENT_SOUNDS.has(cue_name):
			continue
		if not EVERYWHERE.has(cue_name) and (rest_arena == "" or str(cue.get("arena", "")) != rest_arena):
			continue
		var t: float = float(cue["t"])
		if absf(t - float(_last_kept.get(cue_name, -INF))) < MIN_GAP:
			continue
		_last_kept[cue_name] = t
		_insert({ "name": cue_name, "t": t })
		kept += 1
	return kept


## Keeps the list in the order of the times (a new cue is the last or near the last).
func _insert(cue: Dictionary) -> void:
	var at: int = _pending.size()
	while at > 0 and float(_pending[at - 1]["t"]) > float(cue["t"]):
		at -= 1
	_pending.insert(at, cue)
	while _pending.size() > MAX_PENDING:
		_pending.pop_front()


## The sounds whose time has come at `now`, in the order of their times. They leave the list. A cue that is later than STALE_AFTER is
## dropped.
func due(now: float) -> Array[String]:
	var out: Array[String] = []
	while not _pending.is_empty() and float(_pending[0]["t"]) <= now:
		var cue: Dictionary = _pending.pop_front()
		if now - float(cue["t"]) <= STALE_AFTER:
			out.append(str(cue["name"]))
	return out


func pending_count() -> int:
	return _pending.size()


## A new session: no cue waits.
func clear_pending() -> void:
	_pending.clear()
	_last_kept.clear()


## What the sound switch draws and what its hit tests read (`art/sound_ui_art.gd`).
func ui(wall: float) -> Dictionary:
	return {
		"on": on, "tune": tune, "events": events, "open": menu_open, "hover": hover, "toast": toast_at(wall),
		"tunes": TUNES,
	}
