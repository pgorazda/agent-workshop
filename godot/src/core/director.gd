extends RefCounted
## The director: one penguin for each framework + session + agent, and the helpers.
##
## It reads events and gives each one to the right actor (`penguin_actor.gd`). The rules:
##   * the `hello` greeting of the bridge is not an event and is ignored;
##   * the first event of an agent makes its penguin. The director has a limit on penguins (`limit`, 12 by default). An agent
##     over the limit gets no penguin and its events are dropped (`dropped_agents` counts them);
##   * a `subagent_start` makes a helper, and the helper goes after `subagent_end`. The helper is keyed by the framework,
##     the session and the subagent id (the `id` of the event). Events that carry this id as their `agent` go to the helper;
##   * the cap cord comes from the framework (`cord_of`);
##   * a queue that is too long is cut by the backlog rule (`backlog.gd`).
##
## Arenas. The director places each new penguin in an arena with the rules of
## `ArenaRules.create_arenas`: an arena holds `arena_size` agents, helpers stay with their parent, a new agent goes to the
## first arena with room, and an agent never changes arena while it is present. Each arena is a room with its own world
## (spots, queues, effect cues and actors). Two penguins in different arenas can stand on the same floor position.
## The settings are off by default, so the director on its own behaves as before (one room, no limit on the arena):
##   * `arena_size`    0 is one room for everyone. A number above 0 is the size of an arena (4 by default);
##   * `leave_after`   0 is off. A number is the seconds after which an agent with no event leaves (600 by default), unless one
##                     of its calls or an approval is open. It walks out through the door, and its place is freed at once;
##   * `limit`         the most penguins, 12 by default. A view with arenas raises it.
## An arena closes `close_after` seconds after its last agent left, unless it is the only one.
##
## A camera (`camera.gd`) may be attached with `attach_camera`. The director then feeds it with what happens: the arenas that
## open and close, and each event as activity, a failure, an approval, a finished turn, a new arena or a new agent.
## An approval is open until the next event of the agent. With a camera the focus of each arena is the camera's.

const Event := preload("res://src/core/event.gd")
const Clock := preload("res://src/core/clock.gd")
const World := preload("res://src/core/world.gd")
const PenguinActor := preload("res://src/core/penguin_actor.gd")
const Backlog := preload("res://src/core/backlog.gd")
const Focus := preload("res://src/core/focus.gd")
const ArenaRules := preload("res://src/core/arena_rules.gd")
const Camera := preload("res://src/core/camera.gd")
const LogModel := preload("res://src/core/log_model.gd")

## The frameworks that have their own cap cord. Any other framework gets "default" (grey). A test compares this list
## with `CORDS` in `art/atlas_data.gd`.
const KNOWN_FRAMEWORKS: Array[String] = ["claude-code", "opencode", "pi", "hermes"]
const DEFAULT_LIMIT := 12
## Where a new penguin pops in, near the rug (the starting points of the scenes in multi-agent.js). The sixth is followed by the first.
const SPAWNS: Array[Vector2] = [
	Vector2(226, 150), Vector2(256, 154), Vector2(236, 146), Vector2(244, 148), Vector2(232, 150), Vector2(248, 152),
]
## Where a helper pops in: the helper desk.
const HELPER_SPAWN := Vector2(434, 214)
## How often the director looks for agents that should leave, in seconds.
const LEAVE_CHECK_SECONDS := 0.5
## The letter of the first arena.
const FIRST_ARENA := "A"
## How long a closed arena stays in `recently_closed`, in seconds.
const CLOSED_KEEP := 2.0

## The most penguins in all arenas. Helpers do not count.
var limit: int = DEFAULT_LIMIT
## The events a queue may hold before the backlog rule cuts it.
var backlog_limit: int = Backlog.LIMIT
## The number of agents in an arena. 0 is one room for everyone.
var arena_size: int = 0
## The seconds after which a quiet agent leaves. 0 is off.
var leave_after: float = 0.0
## An empty arena closes after this long.
var close_after: float = float(ArenaRules.DEFAULTS["close_after"])
## The first penguin of a new arena pops in this long after the arena opens.
var new_penguin_delay: float = float(ArenaRules.DEFAULTS["new_penguin"])
## The world of the first arena. In a director with one room it is the only world.
var world: RefCounted = World.new()
## The focus of the one room. With a camera, the focus of each arena is the camera's (`Camera.focus_of`).
var focus: RefCounted = Focus.new()
## The camera that the director feeds, or null.
var camera: Camera = null
## The activity log and the cards, built from the same events (`log_model.gd`).
var activity_log: LogModel = LogModel.new()
## No shake and no stars in the effects of every room.
var reduced_motion: bool = false:
	set(value):
		reduced_motion = value
		for room: RefCounted in rooms.values():
			room.effects.reduced_motion = value

## Collect the sound cues of the actors (`take_sound_cues`). The view turns it on only while event sounds sound, so a run
## with no sound collects nothing.
var record_sounds: bool = false:
	set(value):
		record_sounds = value
		for room: RefCounted in rooms.values():
			room.record_sounds = value

## The number of events that went to an actor.
var routed: int = 0
## The number of events of agents that got no penguin because of the limit.
var dropped_agents: int = 0
## The number of events that the backlog rule dropped.
var dropped_events: int = 0
## The number of penguins that left because their agent was quiet.
var left_count: int = 0
## letter -> the time at which the arena opened. An arena that was there from the start of a scene has no entry.
var arena_opened_at: Dictionary = { }
## The arenas that closed lately: [{ letter, t }]. The bar lets a closed tab shrink away for a short time (`CLOSED_KEEP`).
var recently_closed: Array[Dictionary] = []

## letter -> World. The arenas that are open, in the order in which they opened.
var rooms: Dictionary = { }
## The arena model (`ArenaRules.Arenas`): who is in which arena.
var arenas: ArenaRules.Arenas = ArenaRules.create_arenas({ "arena_size": INF })

var _by_key: Dictionary = { } # key -> actor, for the actors that count (not the ones that are leaving)
var _next_number: int = 1
var _spawned: int = 0
var _now: float = 0.0
var _next_leave_check: float = 0.0
var _left_serial: int = 0
var _unplaced: Dictionary = { } # agent key -> the time of its last try: agents that got no penguin


func _init() -> void:
	rooms[FIRST_ARENA] = world


## Sets the size of an arena. Call it before the first event: it starts a new arena model.
func set_arena_size(size: int) -> void:
	arena_size = size
	arenas = ArenaRules.create_arenas({ "arena_size": float(size) if size > 0 else INF, "close_after": close_after })


## The key of an agent: framework, session and agent id.
static func key_of(framework: String, session: String, agent: String) -> String:
	return "%s|%s|%s" % [framework, session, agent]


## The cap cord of a framework: the framework itself when it has one, and "default" otherwise.
static func cord_of(framework: String) -> String:
	return framework if KNOWN_FRAMEWORKS.has(framework) else "default"


## Feeds a camera from now on. The arenas that are open now are told to it.
func attach_camera(new_camera: Camera) -> void:
	camera = new_camera
	for letter in arenas.letters():
		camera.arena_opened(letter, 0.0)


## Sets the simulation time before the first step (a scene may start before time 0, with the agents that were there before).
func sync_time(now: float) -> void:
	_now = now
	for room: RefCounted in rooms.values():
		room.now = now
	_next_leave_check = now


## Handles a decoded message of the bridge. It ignores the greeting and what is not an event. Returns true when an
## actor got an event.
func handle_message(data: Dictionary) -> bool:
	if Event.is_hello(data):
		return false
	var event: RefCounted = Event.from_dictionary(data)
	if event == null:
		return false
	return handle_event(event)


## Handles one event. Returns true when it went to an actor (or made one).
func handle_event(event: RefCounted) -> bool:
	if event.type == "hello":
		return false
	match event.type:
		"subagent_start":
			return _start_helper(event)
		"subagent_end":
			return _end_helper(event)
		_:
			pass
	var actor: Variant = _by_key.get(key_of(event.framework, event.session, event.agent))
	if actor == null:
		actor = _make_penguin(event.framework, event.session, event.agent)
	if actor == null:
		dropped_agents += 1
		_unplaced[key_of(event.framework, event.session, event.agent)] = _now
		return false
	var room: RefCounted = world_of(actor.arena)
	actor.last_event_time = _now
	if event.type == "session_start":
		# the penguin pops in, and there is nothing else to do
		_note_focus(actor, false)
		_feed_camera(actor, event)
		activity_log.note_event(event, actor.key, _now)
		return true
	_feed_camera(actor, event)
	activity_log.note_event(event, actor.key, _now)
	actor.enqueue(event, room)
	routed += 1
	if actor.queue.size() > backlog_limit:
		dropped_events += Backlog.trim(actor.queue, backlog_limit)
	_note_focus(actor, _is_priority(event))
	return true


## The sound cues that the actors made since the last call: [{ name, t, arena }]. The list is emptied.
func take_sound_cues() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for letter: String in rooms:
		var room: RefCounted = rooms[letter]
		for cue: Dictionary in room.sounds:
			out.append({ "name": cue["name"], "t": cue["t"], "arena": letter })
		room.sounds.clear()
	return out


## One step of the simulation. `now` is the time of the clock after the step. `dt` is how much time the actors move on (a step of the
## clock, or several steps together: a window that is not shown steps in larger pieces, see `LiveView.simulate`). With `step_actors`
## false the actors stay as they are: only the time moves on, so that an event that comes in has the right time.
func step(now: float, dt: float = Clock.STEP, step_actors: bool = true) -> void:
	_now = now
	for room: RefCounted in rooms.values():
		room.now = now
		var gone: Array[String] = []
		if step_actors:
			for key: String in room.actors:
				var actor: RefCounted = room.actors[key]
				actor.step(room, dt)
				if actor.gone:
					gone.append(key)
		for key in gone:
			room.actors.erase(key)
			_by_key.erase(key)
		room.effects.prune(now)
	while not recently_closed.is_empty() and now - float(recently_closed[0]["t"]) > CLOSED_KEEP:
		recently_closed.pop_front()
	if leave_after > 0.0 and now >= _next_leave_check:
		_next_leave_check = now + LEAVE_CHECK_SECONDS
		_leave_quiet_agents()
	_close_empty_arenas()
	if camera == null:
		focus.step(now)


## The penguins (not the helpers) of all arenas, in the order in which they came.
func penguins() -> Array[RefCounted]:
	var list: Array[RefCounted] = []
	for actor: RefCounted in _by_key.values():
		if not actor.is_helper:
			list.append(actor)
	return list


## The helpers of all arenas, in the order in which they came.
func helpers() -> Array[RefCounted]:
	var list: Array[RefCounted] = []
	for actor: RefCounted in _by_key.values():
		if actor.is_helper:
			list.append(actor)
	return list


## The actor of a key, or null.
func actor_of(key: String) -> RefCounted:
	return _by_key.get(key)


## The penguin that wears a number, or null. A click on a chip or a card gives the number.
func penguin_with_number(number: int) -> RefCounted:
	for actor in penguins():
		if actor.number == number:
			return actor
	return null


func penguin_count() -> int:
	var count: int = 0
	for actor: RefCounted in _by_key.values():
		if not actor.is_helper:
			count += 1
	return count


## The letters of the open arenas, in the order of their names.
func letters() -> Array[String]:
	return arenas.letters()


## The world of an arena. An arena that is not open gives the first world, so that a caller never gets null.
func world_of(letter: String) -> RefCounted:
	return rooms.get(letter, world)


## Every actor of one arena that is on the stage: penguins and helpers, and the penguins that are leaving.
func actors_in(letter: String) -> Array[RefCounted]:
	var list: Array[RefCounted] = []
	var room: Variant = rooms.get(letter)
	if room == null:
		return list
	for actor: RefCounted in (room as RefCounted).actors.values():
		list.append(actor)
	return list


## The agents that sent events but got no penguin, because every arena is full and no more may open. An agent counts for
## `leave_after` seconds after its last try (for ever when that is 0).
func unplaced_count() -> int:
	var count: int = 0
	for last: float in _unplaced.values():
		if leave_after <= 0.0 or _now - last < leave_after:
			count += 1
	return count


## The time at which an arena opened, or a very early time for an arena that was there from the start.
func opened_at_of(letter: String) -> float:
	return float(arena_opened_at.get(letter, -1.0e9))


## The number of penguins (not helpers) that are in an arena and stay.
func agent_count_in(letter: String) -> int:
	var count: int = 0
	for actor: RefCounted in _by_key.values():
		if not actor.is_helper and actor.arena == letter:
			count += 1
	return count


# ---------------------------------------------------------------- inside

func _make_penguin(framework: String, session: String, agent: String) -> RefCounted:
	if penguin_count() >= limit:
		return null
	var number: int = _next_number
	var letter: Variant = arenas.place(number, _now)
	if letter == null:
		return null
	_next_number += 1
	_unplaced.erase(key_of(framework, session, agent))
	var opened: bool = not rooms.has(str(letter))
	if opened:
		arena_opened_at[str(letter)] = _now if _now > 0.0 else -1.0e9
		var room: RefCounted = World.new()
		room.now = _now
		room.effects.reduced_motion = reduced_motion
		room.record_sounds = record_sounds
		rooms[str(letter)] = room
		if camera != null:
			camera.arena_opened(str(letter), _now)
	var actor: RefCounted = PenguinActor.new()
	actor.key = key_of(framework, session, agent)
	actor.framework = framework
	actor.session = session
	actor.agent = agent
	actor.number = number
	actor.cord = cord_of(framework)
	actor.arena = str(letter)
	actor.last_event_time = _now
	var spawn: Vector2 = SPAWNS[_spawned % SPAWNS.size()]
	_spawned += 1
	actor.rest_point = spawn
	var home: RefCounted = world_of(actor.arena)
	home.actors[actor.key] = actor
	_by_key[actor.key] = actor
	activity_log.agent_joined(actor.key, number, actor.arena, framework, session, actor.cord, _now)
	# The first penguin of a new arena pops in a little later, when a camera that slides there arrives (not before time 0:
	# a scene may start with agents that are there already).
	var delay: float = new_penguin_delay if opened and _now > 0.0 else 0.0
	actor.start(home, spawn, delay)
	if camera != null and _now > 0.0:
		camera.feed("open" if opened else "join", actor.arena, number, _now)
	return actor


func _start_helper(event: RefCounted) -> bool:
	var parent: Variant = _by_key.get(key_of(event.framework, event.session, event.agent))
	if parent == null:
		parent = _make_penguin(event.framework, event.session, event.agent)
	if parent == null:
		dropped_agents += 1
		_unplaced[key_of(event.framework, event.session, event.agent)] = _now
		return false
	var helper_key: String = key_of(event.framework, event.session, event.id)
	if _by_key.has(helper_key):
		return false
	var room: RefCounted = world_of(parent.arena)
	var helper: RefCounted = PenguinActor.new()
	helper.key = helper_key
	helper.framework = event.framework
	helper.session = event.session
	helper.agent = event.id
	helper.is_helper = true
	helper.parent_key = parent.key
	helper.number = parent.number
	helper.cord = parent.cord
	helper.arena = parent.arena
	room.actors[helper_key] = helper
	_by_key[helper_key] = helper
	helper.start(room, HELPER_SPAWN)
	activity_log.helper_started(parent.key, helper_key, _now)
	parent.last_event_time = _now
	routed += 1
	_note_focus(parent, false)
	_feed_camera(parent, event)
	return true


func _end_helper(event: RefCounted) -> bool:
	var helper: Variant = _by_key.get(key_of(event.framework, event.session, event.id))
	if helper == null or not helper.is_helper:
		return false
	helper.finish(world_of(helper.arena))
	activity_log.helper_ended(helper.key, _now)
	routed += 1
	var parent: Variant = _by_key.get(helper.parent_key)
	if parent != null:
		parent.last_event_time = _now
		_feed_camera(parent, event)
	return true


## A failure, a request for an approval and a finished turn take the focus at once.
func _is_priority(event: RefCounted) -> bool:
	match event.type:
		"waiting_permission", "done", "error":
			return true
		"tool_end":
			return event.ok == false
	return false


func _note_focus(actor: RefCounted, priority: bool) -> void:
	var main: RefCounted = actor
	if actor.is_helper:
		var found: Variant = _by_key.get(actor.parent_key)
		if found != null:
			main = found
	if camera != null:
		camera.feed_focus(main.arena, main.number, _now, priority)
		return
	focus.note(main.key, priority)


## What the camera sees of an event of an agent (see `Camera.feed`). An approval is open until the next event of the agent.
func _feed_camera(actor: RefCounted, event: RefCounted) -> void:
	if camera == null:
		return
	var kind: String = "activity"
	match event.type:
		"waiting_permission":
			kind = "approval"
		"done":
			# a helper that finishes its work never pulls the camera
			kind = "activity" if actor.is_helper else "done"
		"error":
			kind = "fail"
		"tool_end":
			if event.ok == false:
				kind = "fail"
	var answers: bool = kind != "approval" and event.type != "session_start" and event.type != "subagent_start" and event.type != "subagent_end"
	if answers:
		camera.answer_agent(actor.number, _now)
	camera.feed(kind, actor.arena, actor.number, _now)


## An agent that was quiet for `leave_after` seconds, with no call or approval open, leaves.
func _leave_quiet_agents() -> void:
	var going: Array[RefCounted] = []
	for actor: RefCounted in _by_key.values():
		if actor.is_helper:
			continue
		var info: Dictionary = { "last_event": actor.last_event_time, "open_calls": 1 if actor.has_call() else 0, "waiting": actor.is_asking() }
		if ArenaRules.leaves(info, _now, { "leave_after": leave_after }):
			going.append(actor)
	for actor in going:
		_leave(actor)


func _leave(actor: RefCounted) -> void:
	var room: RefCounted = world_of(actor.arena)
	arenas.leave(actor.number, _now)
	if camera != null:
		camera.answer_agent(actor.number, _now)
	for helper in helpers():
		if helper.parent_key == actor.key:
			helper.finish(room)
	actor.leave(room)
	activity_log.agent_left(actor.key, _now)
	focus.remove(actor.key)
	# The key is free at once: a new event of the same agent makes a new penguin (with a new number). The old one walks out
	# under another key, so that the two do not meet in the dictionary.
	_by_key.erase(actor.key)
	room.actors.erase(actor.key)
	_left_serial += 1
	actor.key = "%s~left%d" % [actor.key, _left_serial]
	room.actors[actor.key] = actor
	left_count += 1


## An arena that has been empty for `close_after` seconds closes, but never the last one.
func _close_empty_arenas() -> void:
	if rooms.size() < 2:
		return
	for letter in arenas.tick(_now):
		rooms.erase(letter)
		arena_opened_at.erase(letter)
		recently_closed.append({ "letter": letter, "t": _now })
		if camera != null:
			camera.arena_closed(letter, _now)
