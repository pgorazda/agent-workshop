extends RefCounted
## What the actors share in one room: the time, the spots and queues of the stations, the effect cues and the actors.
##
## An actor does not keep a reference to the world. Each call that needs it takes it as an argument, so that no
## reference cycle forms (a reference cycle of `RefCounted` objects is never freed in GDScript).

const Spots := preload("res://src/core/spots.gd")
const Effects := preload("res://src/core/effects.gd")

## The simulation time in seconds. The director sets it before each step.
var now: float = 0.0
var spots: RefCounted = Spots.new()
var effects: RefCounted = Effects.new()
## key (String) -> actor. Penguins and helpers.
var actors: Dictionary = { }
## The sound cues that the actors made since the director took them last: [{ name, t }] (phase G-7). Nothing is kept unless
## `record_sounds` is true, so a run with no sound collects nothing.
var sounds: Array[Dictionary] = []
var record_sounds: bool = false


## An actor says that a sound is due at the simulation time `t` ("tink", "bell", "flop", "chime" or "fanfare"). `core/sound_model.gd`
## decides whether it plays.
func add_sound(sound_name: String, t: float) -> void:
	if record_sounds:
		sounds.append({ "name": sound_name, "t": t })


## An actor leaves its station or its line. The placements that change as a result go to their actors, so that the next
## penguin in the line walks to the free spot and the others move up.
func leave_station(key: String) -> void:
	var changed: Array[Dictionary] = spots.leave(key)
	for placement in changed:
		var actor: Variant = actors.get(placement["agent"])
		if actor != null:
			actor.placement_changed(placement, self)
