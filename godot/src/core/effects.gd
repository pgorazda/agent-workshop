extends RefCounted
## The effect cues: what the actors say happened, so that the art can draw dust, sparks, smoke and confetti.
##
## A cue is a Dictionary:
##   "kind"   one of LIFE's keys
##   "t0"     the simulation time at which it starts, in seconds. It can be in the future (the sparkles of a cheer)
##   "x","y"  the point in room pixels (the foot of a penguin, or the chimney of the forge)
##   "scale"  1.0, or less for a helper
##   "seed"   a number for the seeded random numbers (the art uses `rng.gd`, so a run looks the same every time)
##
## The art draws a cue from its age (`now - t0`) alone, as the mockup draws every frame from the time. This class holds
## no drawing and reads no clock. It also keeps the shake of the room.

## How long each kind of cue lives, in seconds.
const LIFE: Dictionary = {
	"puff": 0.35,
	"dust": 0.4,
	"spark": 0.65,
	"smoke": 2.0,
	"tink": 0.1,
	"bell": 0.18,
	"confetti": 4.0,
	"sparkle": 0.5,
}

## A failure shakes the room for this long, at most once in SHAKE_GAP seconds (`shakeAt` of the JavaScript mockup, removed).
const SHAKE_TIME := 0.4
const SHAKE_GAP := 1.0

## True when the person asks for less motion: the room does not shake.
var reduced_motion: bool = false

var _cues: Array[Dictionary] = []
var _last_shake: float = -9.0


## Adds a cue. An unknown kind is ignored.
func add(kind: String, t0: float, x: float, y: float, scale: float = 1.0, seed_value: int = 0) -> void:
	if not LIFE.has(kind):
		return
	_cues.append({"kind": kind, "t0": t0, "x": x, "y": y, "scale": scale, "seed": seed_value})


## The cues that are alive at `now` (some may not have started: their age is below 0). Do not change the list.
func active() -> Array[Dictionary]:
	return _cues


## Removes the cues that are over at `now`.
func prune(now: float) -> void:
	var kept: Array[Dictionary] = []
	for cue in _cues:
		if now < float(cue["t0"]) + float(LIFE[cue["kind"]]):
			kept.append(cue)
	_cues = kept


## How many cues of a kind are in the list.
func count_of(kind: String) -> int:
	var count: int = 0
	for cue in _cues:
		if cue["kind"] == kind:
			count += 1
	return count


func clear() -> void:
	_cues.clear()
	_last_shake = -9.0


## A failure happened at `now`. It starts a shake unless one started less than a second ago.
func note_failure(now: float) -> void:
	if now - _last_shake >= SHAKE_GAP:
		_last_shake = now


## The sideways shift of the room in pixels at `now`: a decaying wave for 0.4 s after a failure.
func shake_offset(now: float) -> int:
	if reduced_motion:
		return 0
	var age: float = now - _last_shake
	if age < 0.0 or age >= SHAKE_TIME:
		return 0
	return int(floorf(sin(age * 70.0) * 2.5 * (1.0 - age / SHAKE_TIME) + 0.5))
