extends GutTest
## The sound cues of the actors (phase G-7): a hammer's tink at each stroke at the workbench, the desk bell when work is handed to a
## helper, a flop for a failed call, a chime when an agent starts to wait for approval, a fanfare for a finished turn. The actors say
## when, on the simulation clock. `core/sound_model.gd` decides whether a cue sounds (see `test_sound_model.gd`).
## The expected times come from `soundCues` of the JavaScript mockup (removed).

const Director := preload("res://src/core/director.gd")
const Clock := preload("res://src/core/clock.gd")
const SoundModel := preload("res://src/core/sound_model.gd")
const Trace := preload("res://test/support/trace.gd")

var director: RefCounted
var clock: RefCounted
## Every cue that the director gave, with its arena, in the order of the steps.
var cues: Array[Dictionary] = []


func before_each() -> void:
	director = Director.new()
	director.record_sounds = true
	clock = Clock.new()
	cues = []


## Runs the director for `seconds` and collects the cues after every step, as the view does.
func _run(seconds: float) -> void:
	var end: float = clock.now + seconds
	while clock.now < end - 1e-9:
		clock.tick()
		director.step(clock.now)
		cues.append_array(director.take_sound_cues())


func _times(sound_name: String) -> Array[float]:
	var out: Array[float] = []
	for cue in cues:
		if cue["name"] == sound_name:
			out.append(float(cue["t"]))
	return out


func _count(sound_name: String) -> int:
	return _times(sound_name).size()


func test_no_cue_is_kept_unless_the_director_records() -> void:
	director = Director.new()
	director.handle_event(Trace.tool_start("write"))
	director.handle_event(Trace.tool_end(false))
	_run(8.0)
	assert_eq(cues.size(), 0, "a run with no sound collects nothing")
	assert_eq((director.world.sounds).size(), 0, "and the world keeps nothing either")


func test_the_hammer_tinks_at_each_stroke_at_the_workbench() -> void:
	director.handle_event(Trace.tool_start("write"))
	_run(6.0)
	var tinks: Array[float] = _times("tink")
	assert_gt(tinks.size(), 4, "a tink at each stroke")
	for i in range(1, tinks.size()):
		assert_almost_eq(tinks[i] - tinks[i - 1], 0.44, 0.02, "a stroke every two frames of 0.22 s, as the mockup's period")
	assert_eq(_count("bell") + _count("flop") + _count("chime") + _count("fanfare"), 0, "no other sound")


func test_the_first_tink_comes_one_frame_after_the_penguin_arrives() -> void:
	director.handle_event(Trace.tool_start("write"))
	var penguin: RefCounted = director.penguins()[0]
	var arrived_at: float = -1.0
	while clock.now < 8.0 and _count("tink") == 0:
		_run(Clock.STEP)
		if arrived_at < 0.0 and penguin.activity == "work" and penguin.station != "":
			arrived_at = clock.now
	assert_gt(arrived_at, 0.0, "the penguin arrived")
	assert_almost_eq(_times("tink")[0], arrived_at + 0.22, 0.03)


func test_the_desk_bell_sounds_once_when_work_is_handed_to_a_helper() -> void:
	director.handle_event(Trace.tool_start("delegate", "explore", "t1"))
	_run(8.0)
	assert_eq(_count("bell"), 1, "once, however long the penguin rings")


func test_a_failed_call_gives_a_flop() -> void:
	director.handle_event(Trace.tool_start("exec", "make"))
	_run(3.0)
	assert_eq(_count("flop"), 0, "no flop while the call runs")
	director.handle_event(Trace.tool_end(false))
	var failed_at: float = clock.now
	_run(2.0)
	assert_eq(_count("flop"), 1)
	assert_almost_eq(_times("flop")[0], failed_at, 0.1, "at the moment of the failure")


func test_a_call_that_ends_well_gives_no_flop() -> void:
	director.handle_event(Trace.tool_start("exec", "make"))
	_run(3.0)
	director.handle_event(Trace.tool_end(true))
	_run(3.0)
	assert_eq(_count("flop"), 0)


func test_an_error_event_gives_a_flop() -> void:
	director.handle_event(Trace.ev("error"))
	_run(2.0)
	assert_eq(_count("flop"), 1)


func test_a_chime_when_an_agent_starts_to_wait_for_approval() -> void:
	director.handle_event(Trace.tool_start("exec", "rm"))
	_run(3.0)
	var asked_at: float = clock.now
	director.handle_event(Trace.ev("waiting_permission", { "target": "rm" }))
	_run(1.0)
	assert_eq(_count("chime"), 1)
	assert_almost_eq(_times("chime")[0], asked_at, 0.1, "at the request, not when the penguin reaches the sign post")


func test_a_second_prompt_while_waiting_gives_no_second_chime() -> void:
	director.handle_event(Trace.ev("waiting_permission", { "target": "rm" }))
	_run(2.0)
	director.handle_event(Trace.ev("waiting_permission", { "target": "rm" }))
	_run(2.0)
	assert_eq(_count("chime"), 1)


func test_a_fanfare_for_a_finished_turn_a_little_after_the_cheer_starts() -> void:
	director.handle_event(Trace.tool_start("read"))
	_run(2.0)
	director.handle_event(Trace.tool_end(true))
	_run(1.0)
	director.handle_event(Trace.ev("done"))
	var penguin: RefCounted = director.penguins()[0]
	var cheer_at: float = -1.0
	while clock.now < 20.0 and _count("fanfare") == 0:
		_run(Clock.STEP)
		if cheer_at < 0.0 and penguin.activity == "cheer":
			cheer_at = clock.now
	assert_gt(cheer_at, 0.0, "the penguin cheers")
	assert_eq(_count("fanfare"), 1)
	assert_almost_eq(_times("fanfare")[0], cheer_at + 0.15, 0.03, "0.15 s after the cheer starts, as the mockup")
	_run(6.0)
	assert_eq(_count("fanfare"), 1, "once")


func test_a_helper_makes_no_sound() -> void:
	director.handle_event(Trace.tool_start("delegate", "explore", "t1"))
	director.handle_event(Trace.ev("subagent_start", { "id": "sub1" }))
	director.handle_event(Trace.tool_start("write", "a.py", "w1", "sub1"))
	director.handle_event(Trace.tool_end(false, "w1", "sub1"))
	director.handle_event(Trace.ev("done", { }, "sub1"))
	_run(10.0)
	assert_eq(_count("tink"), 0, "the helper's hammer is silent")
	assert_eq(_count("flop"), 0, "and so is its flop")
	assert_eq(_count("fanfare"), 0, "and its cheer")
	assert_eq(_count("bell"), 1, "only the penguin's own bell sounds")


func test_a_cue_has_the_letter_of_its_arena() -> void:
	director.set_arena_size(2)
	for agent: String in ["a", "b", "c"]:
		director.handle_event(Trace.ev("thinking", { }, agent))
	_run(1.0)
	director.handle_event(Trace.ev("waiting_permission", { "target": "x" }, "c"))
	_run(3.0)
	assert_eq(_count("chime"), 1)
	for cue in cues:
		if cue["name"] == "chime":
			assert_eq(cue["arena"], "B", "the third agent lives in the second arena")


func test_the_model_keeps_the_chime_of_another_arena_but_not_its_tink() -> void:
	director.set_arena_size(2)
	for agent: String in ["a", "b", "c"]:
		director.handle_event(Trace.ev("thinking", { }, agent))
	_run(1.0)
	director.handle_event(Trace.tool_start("write", "x", "w1", "c"))
	director.handle_event(Trace.ev("waiting_permission", { "target": "x" }, "b"))
	_run(4.0)
	var model: SoundModel = SoundModel.new()
	model.start_with("on")
	var kept: Array[String] = []
	for cue in cues:
		# the view offers the cues of each step as they come, and takes the sounds that are due then
		model.offer([cue] as Array[Dictionary], "A")
		kept.append_array(model.due(float(cue["t"])))
	assert_has(kept, "chime", "the chime of arena A sounds")
	assert_does_not_have(kept, "tink", "the hammer of arena B does not sound while the camera rests on A")
