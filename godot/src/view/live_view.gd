extends Node
## The live view (phases G-4 and G-5): the rooms of the arenas, seen through the camera, with the penguins of the director. It is
## fed by the bridge or by a timeline file.
##
##   godot --path godot                                  the bridge (ws://127.0.0.1:8787/ws)
##   godot --path godot -- --demo=session                a scene of `res://demo/` (demo mode: no bridge)
##   godot --path godot -- --timeline=user://my.json     a timeline file of your own
##   godot --path godot -- --benchmark=ten --benchmark-out=run.csv    play a scene in real time and log each frame
##
## The frame code is small. It gives the frame time to the clock, runs the steps that the clock answers with (the source
## hands on its events, the director and the actors step, the camera advances), and then gives the result to the view. The
## simulation step is 1/60 s, so a frame rate of 30 or 144 shows the same story (choice 4 of the plan). Nothing here reads the
## wall clock for the picture: the frame time only decides how many steps run.
##
## Keys (phase G-6): F switches between AUTO and MANUAL, Tab opens and closes the overview, Esc leaves it, Left and Right go to the previous
## or next arena (a page in the overview), N goes to the arena that needs you. In demo mode Space pauses, 1 to 3 set the speed (1x, 2x, 4x)
## and `[` and `]` change it; while the follow menu is open, 1 to 6, `[`, `]` and 0 are the menu's (see `ui_input.gd`). R starts the
## scene again, D opens the list of scenes (Up, Down, Enter, Esc), C hides or shows the bar. The mouse: a click on a tab, a box of
## the list of pages, an arena in the overview, a penguin or a card; the follow switch opens its menu; a hover over a tab shows that
## arena's cards. The hit tests are in `interface_model.gd`, in the 480x270 pixels of the viewport.
##
## Sound (phase G-7): M turns all sound on or off, S opens the sound menu (1 to 4 pick a tune, 0 none, E the event sounds, Esc closes it).
## While the menu is open these keys are the menu's, so 1 to 3 are the speed of a demo only while it and the follow menu are closed.
## All sound starts off. `--sound=<tune>|on|events` starts with sound on.
##
## The frame cap without focus and the stop when the window is minimized are in `core/frame_policy.gd`; this node applies them.
##
## Recording (phase G-8, `--record-fps=<n>` or `--stills=<seconds,...>`, started by `tools/record.mjs`): the engine's Movie Maker calls
## `_process` once for each frame of the clip. Frame `i` shows the story at the time `i / fps` (`core/recording.gd`): the view runs the
## simulation up to that time and draws. The window policy, the keys and the mouse are off, a scene plays once, the scripted pointer, key
## caps and follow menu of the scene are drawn, and the client quits after the last frame. `--stills` runs with no drawing up to each time,
## draws one frame and saves the viewport as a PNG file. The scene `tour` (`core/tour.gd`) runs on a clip clock that goes on during a stop
## while the scene clock stands still; in a window it plays the same way.

const Options := preload("res://src/core/options.gd")
const Clock := preload("res://src/core/clock.gd")
const Director := preload("res://src/core/director.gd")
const Camera := preload("res://src/core/camera.gd")
const BenchLog := preload("res://src/core/bench_log.gd")
const StartupReport := preload("res://src/core/startup_report.gd")
const FramePolicy := preload("res://src/core/frame_policy.gd")
const BridgeClient := preload("res://src/net/bridge_client.gd")
const BridgeLauncher := preload("res://src/net/bridge_launcher.gd")
const BridgeSettings := preload("res://src/net/bridge_settings.gd")
const TimelinePlayer := preload("res://src/net/timeline_player.gd")
const ArenaView := preload("res://src/view/arena_view.gd")
const InterfaceModel := preload("res://src/view/interface_model.gd")
const UiInput := preload("res://src/view/ui_input.gd")
const SoundModel := preload("res://src/core/sound_model.gd")
const SoundPlayer := preload("res://src/view/sound_player.gd")
const Atlas := preload("res://art/atlas.gd")
const RoomStageArt := preload("res://art/room_stage_art.gd")
const StatusArt := preload("res://art/status_art.gd")
const BarArt := preload("res://art/bar_art.gd")
const OverviewArt := preload("res://art/overview_art.gd")
const SoundUiArt := preload("res://art/sound_ui_art.gd")
const PointerArt := preload("res://art/pointer_art.gd")
const TourArt := preload("res://art/tour_art.gd")
const Recording := preload("res://src/core/recording.gd")
const Tour := preload("res://src/core/tour.gd")
const TourHoles := preload("res://src/view/tour_holes.gd")
const TraceLog := preload("res://src/core/trace_log.gd")

## The colour behind the viewport where the room does not reach: the background of the log.
const BACKGROUND := Color("#1b2236")
## When a scene ends, the room waits this long and then starts it again.
const LOOP_PAUSE := 2.5
const LIVE_ENTRY := "live (bridge)"
## How often the window state is read, in seconds of frame time.
const WINDOW_CHECK_SECONDS := 0.5

var options: RefCounted
var clock: RefCounted = Clock.new()
var director: RefCounted
var camera: Camera
var arena_view: ArenaView
## What the interface shows and where (the hit tests), and the nodes that draw it.
var interface: InterfaceModel = InterfaceModel.new()
var bar: Node2D
var overview_art: Node2D
## The sound (phase G-7): the state, the players that play the files, and the switch with its menu (top right). All sound starts off.
var sound_model: SoundModel = SoundModel.new()
var sound_player: SoundPlayer
var sound_ui: Node2D
## The scripted pointer and key caps of a scene (demo mode and recording), and the dim and callout of a stop of the tour.
var pointer_art: Node2D
var tour_art: Node2D
## The room of the arena that the camera shows (the room of A before the camera starts).
var stage: RoomStageArt:
	get:
		var shown: String = camera.arena_shown() if camera != null else ""
		return arena_view.stage_of(shown if shown != "" else Director.FIRST_ARENA)
var status: Node2D
## The list of scenes of the demo mode (the key D), over everything.
var scene_list: Node2D
var client: Node = null
## Starts the bridge program when the person asked for it (ADR 0014). Null when it was not asked or no live source was chosen.
var launcher: Node = null
## The timeline that plays, or null when the events come from the bridge.
var player: RefCounted = null
var scene_name: String = ""
var scenes: Array[Dictionary] = []

## How many times the scene started again (the end of a scene, or the key R).
var restarts: int = 0

var _notes: PackedStringArray = []
var _menu_open: bool = false
var _menu_index: int = 0
var _focused: bool = true
var _sound_version: int = -1
var _sound_revision: int = -1
var _sound_toast: String = ""
var _sound_paused: bool = false
var _minimized: bool = false
var _window_check: float = 0.0
var _show_status: bool = true
## The link to the bridge, for the light of the bar: whether it was open once, and the wall-clock time (ms) since it was last not open.
var _ever_open: bool = false
var _down_since_msec: int = 0
## The start-up report (`--startup-report=<file>`), or null.
var _startup: StartupReport = null
## The time at which `_ready` began and the time that the atlases took, in microseconds. Cheap: they are always kept.
var _ready_began_usec: int = 0
var _atlas_usec: int = 0
## What the status art was told last (see `_refresh`).
var _status_shown: Dictionary = { }
## The steps that the actors have not moved on yet in a window that is not shown (see `simulate`).
var _coarse_steps: int = 0
## `--frame-stats`: the sums since the last line.
var _stats_since_msec: int = 0
var _stats_frames: int = 0
var _stats_steps: int = 0
var _stats_simulate_usec: int = 0
var _stats_refresh_usec: int = 0
var _stats_other_usec: int = 0
## The benchmark (`--benchmark=<scene>`): the log.
var _bench: BenchLog = null
var _benchmarking: bool = false
## Recording mode: the frame to draw next, the frames in the clip, and the penguins found on one spot (see `_record_frame`).
var _recording: bool = false
var _frame_index: int = 0
var _frame_total: int = 0
var _conflicts: Array[String] = []
var _conflict_count: int = 0
## The time of the clip in seconds: the time of the frame in a recording, the time that has passed in a tour that plays in a window.
var _clip_time: float = 0.0
## The tour of the scene `tour` (null for the other scenes), the number of its stop that has its holes worked out, and those holes.
var _tour: Tour = null
var _tour_index: int = -1
var _tour_holes: Array[Dictionary] = []
## Whether the follow menu was open in the script at the last frame (the script opens and closes it at the edges).
var _scripted_menu: bool = false
## `--trace`: the visits of the penguins, printed as they begin.
var _trace: TraceLog = TraceLog.new()


func _ready() -> void:
	_ready_began_usec = Time.get_ticks_usec()
	RenderingServer.set_default_clear_color(BACKGROUND)
	Atlas.load_all()
	_atlas_usec = Time.get_ticks_usec() - _ready_began_usec
	options = Options.parse(OS.get_cmdline_user_args())
	if not options.recording() and options.benchmark == "":
		BridgeSettings.apply(options)
	if options.startup_report != "":
		_startup = StartupReport.new()
		_startup.mark("ready_begin", _ready_began_usec)
		_startup.mark("atlas_loaded", _ready_began_usec + _atlas_usec)
		RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	_notes = options.warnings
	_recording = options.recording()
	if options.sound != "" and not sound_model.start_with(options.sound):
		_notes.append("Ignored --sound: use on, events, off or the name of a tune")
	if options.events_off:
		sound_model.events = false
	clock.speed = options.speed
	clock.paused = options.paused
	_show_status = not options.clean
	arena_view = ArenaView.new()
	add_child(arena_view)
	status = StatusArt.new()
	add_child(status)
	overview_art = OverviewArt.new()
	add_child(overview_art)
	bar = BarArt.new()
	add_child(bar)
	tour_art = TourArt.new()
	add_child(tour_art)
	sound_ui = SoundUiArt.new()
	add_child(sound_ui)
	pointer_art = PointerArt.new()
	add_child(pointer_art)
	sound_player = SoundPlayer.new()
	add_child(sound_player)
	scene_list = StatusArt.new()
	scene_list.layer = "menu"
	add_child(scene_list)
	_down_since_msec = Time.get_ticks_msec()
	scenes = TimelinePlayer.scenes()
	_new_session()
	var window: Window = get_window()
	if window != null:
		window.focus_entered.connect(_on_focus_changed.bind(true))
		window.focus_exited.connect(_on_focus_changed.bind(false))
		# A window that starts in the background never gets a focus signal, so ask it now.
		_focused = window.has_focus() if options.forced_focus < 0 else options.forced_focus == 1
		if _recording:
			_focused = true
		if options.forced_focus >= 0 and options.log_events:
			print("[live] focus ", _focused, " (forced)")
	if options.benchmark != "":
		_start_benchmark()
	else:
		_choose_source()
	if options.at > 0.0:
		simulate(int(options.at / Clock.STEP))
	_apply_window_policy()
	_sound_changed()
	sound_ui.visible = not options.hide_switch
	_refresh()
	if _startup != null:
		_startup.mark("ready_end")
	if _recording:
		_begin_recording()


func _exit_tree() -> void:
	# a test or a scene change must not leave the engine capped or silent
	Engine.max_fps = 0
	RenderingServer.render_loop_enabled = true


func _process(delta: float) -> void:
	if _recording:
		if options.stills.is_empty():
			_record_frame()
		return
	var started: int = Time.get_ticks_usec()
	if _startup != null:
		_startup.mark("first_process", started)
		if _startup.process_deltas.size() < 5:
			_startup.process_deltas.append(delta * 1000.0)
	_window_check += delta
	if _window_check >= WINDOW_CHECK_SECONDS:
		_window_check = 0.0
		var minimized: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
		if minimized != _minimized:
			if options.log_events:
				print("[live] minimized ", minimized)
			_minimized = minimized
			_apply_window_policy()
	if _tour != null and not _benchmarking:
		_tour_frame(delta)
		return
	var steps: int = clock.advance(delta, FramePolicy.MINIMIZED_MAX_FRAME if _minimized else Clock.MAX_FRAME)
	var after_clock: int = Time.get_ticks_usec()
	simulate(steps, _minimized)
	var after_simulate: int = Time.get_ticks_usec()
	if FramePolicy.should_draw(_minimized):
		_refresh()
	if _benchmarking:
		_bench_frame(delta, started)
	if options.frame_stats:
		_frame_stats(started, after_clock, after_simulate, steps)


## `--frame-stats`: the average cost of the parts of a frame, printed every five seconds. The times are those of the client's own
## code (they do not include what the engine does to draw afterwards), in milliseconds for each frame.
func _frame_stats(started: int, after_clock: int, after_simulate: int, steps: int) -> void:
	var done: int = Time.get_ticks_usec()
	_stats_frames += 1
	_stats_steps += steps
	_stats_simulate_usec += after_simulate - after_clock
	_stats_refresh_usec += done - after_simulate
	_stats_other_usec += after_clock - started
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _stats_since_msec < 5000:
		return
	var frames: float = float(_stats_frames)
	print("[stats] %.1f frames/s, %.2f steps/frame, simulate %.3f ms, refresh %.3f ms, other %.3f ms, draw calls %d, objects %d" % [
		frames / (float(now_msec - _stats_since_msec) / 1000.0), float(_stats_steps) / frames, float(_stats_simulate_usec) / frames / 1000.0,
		float(_stats_refresh_usec) / frames / 1000.0, float(_stats_other_usec) / frames / 1000.0,
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)),
	])
	_stats_since_msec = now_msec
	_stats_frames = 0
	_stats_steps = 0
	_stats_simulate_usec = 0
	_stats_refresh_usec = 0
	_stats_other_usec = 0


func _on_frame_drawn() -> void:
	_startup.frame_drawn()
	if not _startup.is_complete():
		return
	RenderingServer.frame_post_draw.disconnect(_on_frame_drawn)
	var file: FileAccess = FileAccess.open(options.startup_report, FileAccess.WRITE)
	if file != null:
		file.store_string(_startup.to_json())
		file.close()
	get_tree().quit()


## Runs `count` steps of the simulation. A test calls this with no frames. With `coarse` (a window that is not shown) the actors
## move on in pieces of `FramePolicy.COARSE_STEPS` steps: the events, the clock and the camera still run at every step, and nobody
## sees the actors, so the picture is the same when the window shows again, up to a small shift in time.
func simulate(count: int, coarse: bool = false) -> void:
	for _i in count:
		if player != null:
			for event: RefCounted in player.due_events(clock.now):
				_handle(event)
			for input: Dictionary in player.due_inputs(clock.now):
				_apply_input(input)
		clock.tick()
		if coarse:
			_coarse_steps += 1
			if _coarse_steps >= FramePolicy.COARSE_STEPS:
				director.step(clock.now, float(_coarse_steps) * Clock.STEP)
				_coarse_steps = 0
			else:
				director.step(clock.now, Clock.STEP, false)
		else:
			if _coarse_steps > 0:
				director.step(clock.now, float(_coarse_steps) * Clock.STEP)
				_coarse_steps = 0
			director.step(clock.now)
		camera.advance(clock.now)
		if options.trace:
			_print_trace()
		if sound_model.events_playing():
			_sound_step()
		if player != null and not _benchmarking and not _recording and _tour == null and player.finished(clock.now) and clock.now >= player.duration + LOOP_PAUSE:
			restart()
	if coarse and _coarse_steps > 0:
		director.step(clock.now, float(_coarse_steps) * Clock.STEP)
		_coarse_steps = 0


## `--trace`: the visits that began in this step, one line each.
func _print_trace() -> void:
	var actors: Array[RefCounted] = director.penguins()
	actors.append_array(director.helpers())
	for line in _trace.changes(actors):
		print("[trace] ", line)


## The sounds of one step: the cues of the actors go to the model, which keeps those that sound, and the sounds that are due start.
func _sound_step() -> void:
	var cues: Array[Dictionary] = director.take_sound_cues()
	if not cues.is_empty():
		sound_model.offer(cues, rest_arena())
	for sound_name in sound_model.due(clock.now):
		sound_player.play_event(sound_name)


## The arena that the camera rests on, or "" while it moves or shows the overview. Only the sounds of this arena sound (the chime and the
## fanfare sound from every arena).
func rest_arena() -> String:
	if camera.view.kind == "arena" and not camera.moving_at(clock.now):
		return camera.arena_shown()
	return ""


## The sound state changed: tell the players, and tell the director whether to collect cues. Nothing is collected while event sounds
## are off.
func _sound_changed() -> void:
	if sound_model.version != _sound_version:
		_sound_version = sound_model.version
		sound_player.apply(sound_model)
		sound_player.set_paused(clock.paused)
		_sound_paused = clock.paused
		if options != null and options.log_events:
			print("[live] sound ", "on" if sound_model.on else "off", " tune=", sound_model.tune_playing(), " events=", sound_model.events_playing(),
					" player=", sound_player.running(), " playing=", sound_player.music_playing(), " driver=", AudioServer.get_driver_name())
	director.record_sounds = sound_model.events_playing()


## Starts the scene again: no penguins, the clock at its start, the timeline from its first item.
func restart() -> void:
	restarts += 1
	_clip_time = 0.0
	_new_session()
	if player != null:
		player.rewind()
		_run_preroll()


## Plays the scene of `res://demo/` with this name. Returns false when there is none.
func load_scene(wanted: String) -> bool:
	for entry in scenes:
		if entry["name"] == wanted:
			return load_timeline(str(entry["path"]), wanted)
	_notes.append("No scene named %s" % wanted)
	return false


## Plays a timeline file. Returns false when it cannot be read.
func load_timeline(path: String, scene: String = "") -> bool:
	var loaded: RefCounted = TimelinePlayer.load_file(path)
	if loaded == null:
		_notes.append("Cannot read the timeline %s" % path)
		return false
	_stop_client()
	player = loaded
	_tour = Tour.from_dictionary(loaded.tour) if not loaded.tour.is_empty() else null
	_tour_index = -1
	_clip_time = 0.0
	scene_name = scene if scene != "" else path.get_file().get_basename()
	_new_session()
	_run_preroll()
	return true


## Reads the bridge again, with no timeline.
func load_live() -> void:
	player = null
	_tour = null
	scene_name = ""
	_new_session()
	if options.start_bridge and launcher == null:
		launcher = BridgeLauncher.new()
		launcher.note.connect(_on_bridge_note)
		add_child(launcher)
		launcher.start(options.bridge, options.bridge_path)
	if client == null:
		client = BridgeClient.new()
		client.url = options.bridge
		client.event_received.connect(_handle)
		client.message_rejected.connect(_on_rejected)
		add_child(client)


## One short message from the launcher (ADR 0014): the bridge could not be started. It shows with the other notes.
func _on_bridge_note(text: String) -> void:
	_notes.append(text)
	_refresh()


func _new_session() -> void:
	director = Director.new()
	_trace = TraceLog.new()
	director.record_sounds = sound_model.events_playing()
	sound_model.clear_pending()
	var scene_options: Dictionary = player.options if player != null else { }
	director.set_arena_size(options.arena_size if options.arena_size_set else int(scene_options.get("arena_size", options.arena_size)))
	director.limit = options.penguin_limit
	director.leave_after = options.leave_after
	director.reduced_motion = options.reduced_motion
	var camera_options: Dictionary = { "reduced_motion": options.reduced_motion }
	if options.follow_manual or str(scene_options.get("mode", "")) == "MANUAL":
		camera_options["mode"] = "MANUAL"
	if typeof(scene_options.get("follow")) == TYPE_DICTIONARY:
		camera_options["follow"] = scene_options["follow"]
	if scene_options.has("pace"):
		camera_options["pace"] = float(scene_options["pace"])
	camera = Camera.new(camera_options)
	var cards_bar: bool = str(scene_options.get("bar", "")) == "cards"
	interface.force_cards = cards_bar
	arena_view.force_cards = cards_bar
	_scripted_menu = false
	_tour_index = -1
	director.attach_camera(camera)
	clock.reset(player.start_time() if player != null else 0.0)
	director.sync_time(clock.now)
	arena_view.clear()


## A scene may start before time 0, with the agents that were there before the story. They arrive before the first frame.
func _run_preroll() -> void:
	if clock.now < 0.0:
		simulate(int(roundf(-clock.now / Clock.STEP)))


func _choose_source() -> void:
	if options.timeline != "":
		if not load_timeline(options.timeline):
			load_live()
	elif options.demo != "":
		if not load_scene(options.demo):
			load_live()
	else:
		load_live()


func _stop_client() -> void:
	if client != null:
		client.queue_free()
		client = null


func _handle(event: RefCounted) -> void:
	if options.log_events:
		print("[live] event ", event.describe())
	director.handle_event(event)


func _on_rejected(reason: String) -> void:
	if options.log_events:
		print("[live] rejected message: ", reason)


## An input of a timeline: a key of the camera, a click on the penguin with a number, a click on a tab, a cell or a page box, or
## a line of the follow menu. The camera applies it at its next step.
func _apply_input(input: Dictionary) -> void:
	if typeof(input.get("click")) == TYPE_DICTIONARY:
		var penguin: RefCounted = director.penguin_with_number(int((input["click"] as Dictionary).get("number", 0)))
		if penguin != null:
			camera.set_focus(penguin.arena, penguin.number, clock.now)
		return
	var entry: Dictionary = input.duplicate()
	entry.erase("t")
	camera.input(entry, clock.now)


# ---------------------------------------------------------------- the window

func _on_focus_changed(has_focus: bool) -> void:
	if options.forced_focus >= 0:
		return
	if options.log_events:
		print("[live] focus ", has_focus)
	_focused = has_focus
	_apply_window_policy()


func _apply_window_policy() -> void:
	if _recording:
		# a recording has no real-time pacing: the engine's Movie Maker sets the pace of the frames, and no window state changes it
		Engine.max_fps = 0
		RenderingServer.render_loop_enabled = true
		return
	if _benchmarking:
		# a measurement must not be capped, whatever the window does
		Engine.max_fps = 0
		RenderingServer.render_loop_enabled = true
		return
	Engine.max_fps = FramePolicy.fps_cap(_focused, _minimized, options.unfocused_fps, options.focused_fps)
	RenderingServer.render_loop_enabled = FramePolicy.should_draw(_minimized)


# ---------------------------------------------------------------- the keys

func _unhandled_key_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if _recording or key_event == null or not key_event.pressed or key_event.echo:
		return
	if _menu_open:
		_menu_key(key_event.keycode)
		return
	if sound_model.key(key_event.keycode, _wall()):
		# one menu at a time: the sound menu and the follow menu share the right side of the room
		if sound_model.menu_open:
			interface.menu_open = false
		_sound_changed()
		_refresh()
		return
	if interface.menu_open and UiInput.menu_key(key_event.keycode, camera, interface, clock.now):
		_refresh()
		return
	var demo: bool = player != null
	match key_event.keycode:
		KEY_SPACE:
			if demo:
				clock.paused = not clock.paused
		KEY_1:
			if demo:
				clock.speed = 1.0
		KEY_2:
			if demo:
				clock.speed = 2.0
		KEY_3:
			if demo:
				clock.speed = 4.0
		KEY_BRACKETRIGHT:
			if demo:
				clock.faster()
		KEY_BRACKETLEFT:
			if demo:
				clock.slower()
		KEY_R:
			restart()
		KEY_D:
			_menu_open = true
			_menu_index = 0
			if scene_name != "":
				for i in scenes.size():
					if scenes[i]["name"] == scene_name:
						_menu_index = i + 1
		KEY_F:
			camera.press("F", clock.now)
		KEY_TAB:
			camera.press("Tab", clock.now)
		KEY_ESCAPE:
			camera.press("Esc", clock.now)
		KEY_LEFT:
			camera.press("Left", clock.now)
		KEY_RIGHT:
			camera.press("Right", clock.now)
		KEY_N:
			camera.press("N", clock.now)
		KEY_C:
			_show_status = not _show_status
	_refresh()


func _menu_key(keycode: Key) -> void:
	var count: int = scenes.size() + 1
	match keycode:
		KEY_UP:
			_menu_index = posmod(_menu_index - 1, count)
		KEY_DOWN:
			_menu_index = posmod(_menu_index + 1, count)
		KEY_ESCAPE, KEY_D:
			_menu_open = false
		KEY_ENTER, KEY_KP_ENTER:
			_menu_open = false
			if _menu_index == 0:
				load_live()
			else:
				load_scene(str(scenes[_menu_index - 1]["name"]))
	_refresh()


## The mouse. A move keeps the hover point (a hover over a tab shows that arena's cards) and sets the pointer. A left click goes to
## what is under it (`InterfaceModel.hit`): a tab, a box of the list of pages, an arena in the overview, a penguin or a card, or the
## follow switch and its menu. The hit tests are in the 480x270 pixels of the viewport.
func _unhandled_input(event: InputEvent) -> void:
	if _menu_open or _recording:
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		interface.hover_point = motion.position
		var sound_over: Dictionary = SoundUiArt.hit(motion.position, sound_model.ui(_wall()))
		sound_model.set_hover_from(sound_over)
		var over: Dictionary = interface.hit(motion.position)
		var sound_hand: bool = ["pill", "tune", "events"].has(str(sound_over["kind"]))
		var covered: bool = sound_model.menu_open and str(sound_over["kind"]) != "none"
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if sound_hand or (over["kind"] != "none" and not covered) else Input.CURSOR_ARROW)
		_refresh_sound()
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	interface.hover_point = button.position
	if sound_model.click(SoundUiArt.hit(button.position, sound_model.ui(_wall())), _wall()):
		if sound_model.menu_open:
			interface.menu_open = false
		_sound_changed()
		_refresh()
		return
	interface.build(director, camera, clock.now)
	var hit: Dictionary = interface.hit(button.position)
	if options.log_events:
		print("[live] click at ", button.position, " hit ", hit)
	if UiInput.click(hit, camera, interface, clock.now):
		_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		interface.hover_point = Vector2(-100.0, -100.0)


# ---------------------------------------------------------------- what the view gets

func _refresh() -> void:
	_refresh_scripted()
	_refresh_sound()
	arena_view.update_view(director, camera, clock.now)
	status.visible = _show_status
	bar.visible = _show_status
	overview_art.visible = _show_status or interface.menu_open
	if _show_status or interface.menu_open:
		interface.connection = _connection()
		var ui: Dictionary = interface.build(director, camera, clock.now)
		bar.set_ui(ui)
		overview_art.set_ui(ui)
	# the status art draws only the key cap, the notes and the list of scenes: it is told when one of them changes
	var shown: Dictionary = { "speed": "paused" if clock.paused else "%sx" % str(clock.speed), "notes": Array(_notes) }
	if _menu_open:
		var names: Array[String] = [LIVE_ENTRY]
		for entry in scenes:
			names.append(str(entry["name"]))
		shown["menu"] = names
		shown["menu_index"] = _menu_index
	if shown != _status_shown:
		_status_shown = shown
		status.set_info(shown)
		scene_list.set_info(shown)
	_refresh_tour()


## Tells the switch what to draw, when something that it shows has changed (the state, the menu, the hover, the toast). The players
## follow the pause of the clock.
func _refresh_sound() -> void:
	if _recording and options.menu_seconds > 0.0:
		sound_model.set_menu(_clip_time < options.menu_seconds)
	var toast: String = sound_model.toast_at(_wall())
	if sound_model.revision != _sound_revision or toast != _sound_toast:
		_sound_revision = sound_model.revision
		_sound_toast = toast
		sound_ui.set_state(sound_model.ui(_wall()))
	if clock.paused != _sound_paused:
		_sound_paused = clock.paused
		sound_player.set_paused(clock.paused)


## Wall-clock seconds, for the toast of the sound switch (it belongs to the screen, not to the story).
func _wall() -> float:
	# a recording must not depend on the wall clock: its frames have their own time
	if _recording:
		return _clip_time
	return float(Time.get_ticks_msec()) / 1000.0


## The state of the link for the light of the bar (see `InterfaceModel.connection_of`).
func _connection() -> Dictionary:
	var open: bool = client != null and client.state == BridgeClient.State.OPEN
	if open:
		_ever_open = true
		_down_since_msec = Time.get_ticks_msec()
	return InterfaceModel.connection_of(player != null, open, _ever_open, float(Time.get_ticks_msec() - _down_since_msec) / 1000.0)


## What the status bar shows. Public for tests.
func status_info() -> Dictionary:
	var info: Dictionary = {
		"source": "demo" if player != null else "live",
		"state": (player.title if player.title != "" else scene_name) if player != null else (client.state_name() if client != null else "waiting"),
		"counts": "%d agent%s, %d helper%s" % [
			director.penguin_count(), "" if director.penguin_count() == 1 else "s",
			director.helpers().size(), "" if director.helpers().size() == 1 else "s",
		],
		"follow": camera.mode,
		"view": view_text(),
		"speed": "paused" if clock.paused else "%sx" % str(clock.speed),
		"time": clock.now,
		"notes": Array(_notes),
	}
	var focus_number: Variant = camera.focus_of(camera.arena_shown())
	var focused: RefCounted = director.penguin_with_number(int(focus_number)) if focus_number != null else null
	if focused != null:
		info["focus"] = "focus: %d %s" % [focused.number, focused.framework]
	if _menu_open:
		var names: Array[String] = [LIVE_ENTRY]
		for entry in scenes:
			names.append(str(entry["name"]))
		info["menu"] = names
		info["menu_index"] = _menu_index
	return info


## What the camera shows, in words: "arena B, page 1 of 3", or "overview, page 2 of 3". Empty with one arena.
func view_text() -> String:
	if camera.letters.size() <= 1:
		return ""
	var page: String = "page %d of %d" % [camera.pages.find(camera.page_shown()) + 1, camera.pages.size()]
	if camera.in_overview():
		return "overview, %s" % page
	return "arena %s, %s" % [camera.arena_shown(), page]


# ---------------------------------------------------------------- recording and the tour

## Starts a recording: the number of frames of the clip, or the pictures of a still run. A recording needs a scene.
func _begin_recording() -> void:
	if player == null:
		push_error("Recording needs a scene: give --demo=<name>")
		get_tree().quit.call_deferred(1)
		return
	var duration: float = _tour.clip_duration() if _tour != null else player.duration
	_frame_total = Recording.frame_count(duration, maxi(options.record_fps, 1))
	print("[record] scene=%s fps=%d frames=%d duration=%.3f" % [scene_name, options.record_fps, _frame_total, duration])
	if not options.stills.is_empty():
		_run_stills.call_deferred()


## The scene time that a clip time shows (the tour stops the scene, a scene without a tour does not).
func _scene_time_of(clip: float) -> float:
	return float(_tour.at(clip)["t"]) if _tour != null else clip


## Runs the simulation up to what the clip time shows, and draws it when `draw` is true. The steps run with no drawing.
func _show_clip(clip: float, draw: bool = true) -> void:
	_clip_time = clip
	var need: int = Recording.steps_at_time(_scene_time_of(clip)) - clock.steps
	if need > 0:
		simulate(need)
	if draw:
		_refresh()


## One frame of a recording. The engine calls `_process` once for each frame, so the frame number is the clock.
func _record_frame() -> void:
	if _frame_index >= _frame_total:
		return
	_show_clip(Recording.time_of_frame(_frame_index, options.record_fps))
	for sentence in Recording.spot_conflicts(director, clock.now):
		_conflict_count += 1
		if _conflicts.size() < 20 and not _conflicts.has(sentence):
			_conflicts.append(sentence)
			print("[record] conflict ", sentence)
	_frame_index += 1
	if _frame_index >= _frame_total:
		_finish_recording.call_deferred()


func _finish_recording() -> void:
	print("[record] done frames=%d conflicts=%d" % [_frame_index, _conflict_count])
	get_tree().quit(1 if _conflict_count > 0 else 0)


## `--stills=<seconds,...>`: the simulation runs with no drawing up to each time, one frame is drawn, and the viewport is saved as
## `still-<n>.png` (n is the position of the time in the list) in `--stills-out`.
func _run_stills() -> void:
	var folder: String = options.stills_out if options.stills_out != "" else "."
	DirAccess.make_dir_recursive_absolute(folder)
	var order: Array[int] = []
	for i: int in options.stills.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return options.stills[a] < options.stills[b] or (options.stills[a] == options.stills[b] and a < b))
	var failed: bool = false
	for index in order:
		_show_clip(options.stills[index])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = folder.path_join("still-%d.png" % index)
		if image == null or image.save_png(path) != OK:
			push_error("Cannot save %s" % path)
			failed = true
		else:
			print("[record] still ", index, " t=", options.stills[index], " ", path)
	get_tree().quit(1 if failed else 0)


## A tour that plays in a window: the clip clock runs with the time of the frames, and the scene stands still during a stop.
func _tour_frame(delta: float) -> void:
	if not clock.paused:
		_clip_time += minf(delta, Clock.MAX_FRAME) * clock.speed
	if _clip_time >= _tour.clip_duration() + LOOP_PAUSE:
		restart()
	_show_clip(_clip_time, FramePolicy.should_draw(_minimized))


## What a scene scripts for a person: the pointer, the key caps and the follow menu. Drawn in recording mode and in demo mode. In a
## recording the pointer also sets the point of the hover (a hover over a tab shows that arena's cards). The menu opens and closes at the
## edges of its windows of time, so a person's own click on the switch is not undone.
func _refresh_scripted() -> void:
	if player == null:
		pointer_art.set_state({ })
		return
	var t: float = _clip_time if _recording else clock.now
	pointer_art.set_state({ "pointers": Recording.pointers_at(t, player.paths), "keys": Recording.key_caps_at(t, player.keys) })
	var want: bool = Recording.menu_open_at(t, player.menus)
	if want != _scripted_menu:
		_scripted_menu = want
		interface.menu_open = want
	if _recording:
		interface.hover_point = Recording.hover_point_at(t, player.paths)


## The dim and the callout of a stop of the tour. The holes of a stop are worked out when it begins, from the scene that stands still.
func _refresh_tour() -> void:
	if _tour == null:
		tour_art.set_state({ })
		return
	var at: Dictionary = _tour.at(_clip_time)
	var index: int = int(at["index"])
	if index < 0:
		_tour_index = -1
		tour_art.set_state({ })
		return
	var stop: Dictionary = at["stop"]
	if index != _tour_index:
		_tour_index = index
		_tour_holes = TourHoles.resolve(stop, director, camera, interface.ui)
	tour_art.set_state({ "stop": stop, "holes": _tour_holes, "age": float(at["age"]), "step": index + 1, "steps": _tour.stops.size() })


# ---------------------------------------------------------------- the benchmark

## `--benchmark=<scene>`: plays the scene once in real time, with no interface, and writes the log (see `core/bench_log.gd`).
func _start_benchmark() -> void:
	_benchmarking = true
	_bench = BenchLog.new()
	_show_status = not options.clean
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if options.vsync_off else DisplayServer.VSYNC_ENABLED)
	if not load_scene(options.benchmark):
		_benchmarking = false
		get_tree().quit.call_deferred(1)


func _bench_frame(delta: float, started: int) -> void:
	var process_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	var moving: bool = camera.moving_at(clock.now)
	_bench.add(clock.now, delta * 1000.0, process_ms, camera.move_id if moving else 0)
	if player != null and player.finished(clock.now) and clock.now >= player.duration:
		_finish_benchmark()


func _finish_benchmark() -> void:
	_benchmarking = false
	var path: String = options.benchmark_out if options.benchmark_out != "" else "benchmark.csv"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(_bench.csv())
		file.close()
	var moves: FileAccess = FileAccess.open(path.get_basename() + ".camera.json", FileAccess.WRITE)
	if moves != null:
		moves.store_string(BenchLog.moves_json(camera.moves))
		moves.close()
	print("benchmark: %d frames to %s (vsync %s)" % [_bench.frame_count(), path, "off" if options.vsync_off else "on"])
	get_tree().quit()
