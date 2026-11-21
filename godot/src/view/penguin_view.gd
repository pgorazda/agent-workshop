extends RefCounted
## Turns what an actor exposes into the dictionary that the art node of the room draws (`art/room_stage_art.gd`).
##
## The actor knows position, facing and pose, and nothing about pictures. This is the one place that maps them: a facing of
## "left" is the sideways picture, mirrored. It has no drawing call, so it lives in `src/view/`.

const LogModel := preload("res://src/core/log_model.gd")

## The helper's shadow: smaller and flatter than a penguin's (`shadow(x, y - 1, 5.5, 1.8)` in the mockup).
const HELPER_SHADOW_HEIGHT := 1.8


## The penguin of an actor for the room stage. An actor that is hidden gives `{}`.
static func penguin_of(actor: RefCounted) -> Dictionary:
	if actor.hidden:
		return { }
	var dir: String = "front"
	var flip: bool = false
	match actor.facing:
		"back":
			dir = "back"
		"left":
			dir = "side"
			flip = true
		"right":
			dir = "side"
	var penguin: Dictionary = {
		"x": actor.position.x, "y": actor.position.y, "cord": actor.cord,
		"dir": dir, "pose": actor.pose, "flip": flip, "blink": actor.blink,
		"y_off": actor.y_off, "shadow": actor.shadow,
		"flop": actor.flop_age, "think_age": actor.think_age, "think_in_place": actor.think_in_place,
		"number": actor.number, "activity": actor.activity, "age": float(actor.current_segment().get("age", 0.0)),
	}
	if actor.is_helper:
		penguin["small"] = true
		penguin["shadow_ry"] = HELPER_SHADOW_HEIGHT
	return penguin


## The penguins of all actors of a director, helpers last (the stage sorts them by depth anyway). `focus_number` is the number of the
## agent with the focus, or null: its penguin gets `focused` (a helper never does).
static func crowd_of(actors: Array[RefCounted], focus_number: Variant = null) -> Array[Dictionary]:
	var crowd: Array[Dictionary] = []
	for actor in actors:
		var penguin: Dictionary = penguin_of(actor)
		if not penguin.is_empty():
			penguin["focused"] = focus_number != null and not actor.is_helper and actor.number == int(focus_number)
			crowd.append(penguin)
	return crowd


## The main actor (not a helper) that wears a number, or null.
static func actor_with_number(actors: Array[RefCounted], number: int) -> RefCounted:
	for actor in actors:
		if not actor.is_helper and actor.number == number:
			return actor
	return null


## The first main actor (not a helper) of a list, or null.
static func main_actor(actors: Array[RefCounted]) -> RefCounted:
	for actor in actors:
		if not actor.is_helper:
			return actor
	return null


## The notices of the agents that wait for an approval in an arena, the oldest first, for the stage (see `art/crowd_art.gd`). An
## agent whose approval was just answered (its penguin is in the small cheer) is first, with `approved`. The notice of an agent
## shows from its request on, as its card does. `x` is where the tail of the notice points: the foot of its penguin.
static func notices_of(actors: Array[RefCounted], activity_log: RefCounted, letter: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for actor: RefCounted in actors:
		if actor.is_helper or actor.activity != "approve":
			continue
		var record: Variant = activity_log.agents.get(actor.key)
		if record != null:
			list.append(_notice(record as Dictionary, actor.position.x, true))
	for record: Dictionary in activity_log.waiting(letter):
		var actor: RefCounted = actor_with_number(actors, int(record["number"]))
		list.append(_notice(record, actor.position.x if actor != null else SIGN_X, false))
	return list


## Where the sign post stands: the tail of a notice points here when its penguin is not in the room yet.
const SIGN_X := 236.0


static func _notice(record: Dictionary, x: float, approved: bool) -> Dictionary:
	return {
		"number": record["number"], "cord": record["cord"], "framework": record["framework"],
		"session": LogModel.short_session(str(record["session"])), "target": record["target"], "x": x, "approved": approved,
	}
