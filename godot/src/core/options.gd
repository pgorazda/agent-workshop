extends RefCounted
## Command-line options of the client. They come after `--` on the command line:
##
##   godot --path godot -- --bridge=ws://127.0.0.1:8787/ws
##   godot --path godot -- --demo=session --speed=2

const DEFAULT_BRIDGE := "ws://127.0.0.1:8787/ws"
## The frame rate of a window that has no focus (choice 13 of the plan).
const DEFAULT_UNFOCUSED_FPS := 30
## The frame rate of a window with focus (the rate of the simulation).
const DEFAULT_FOCUSED_FPS := 60
## The most penguins. The view with arenas raises the limit of the director (12) so that ten pages of arenas fit (phase G-5).
const DEFAULT_PENGUIN_LIMIT := 200
## The agents in an arena, and the seconds after which a quiet agent leaves (the plan's starting values).
const DEFAULT_ARENA_SIZE := 4
const DEFAULT_LEAVE_AFTER := 600.0

var bridge: String = DEFAULT_BRIDGE
## Start the bridge program when none runs (ADR 0014). Off by default. The saved setting (`net/bridge_settings.gd`) may turn it on, unless the
## command line decided: `--start-bridge[=<path>]` or `--no-start-bridge`.
var start_bridge: bool = false
var start_bridge_set: bool = false
## The bridge program to start. Empty means: next to the app, then on the PATH.
var bridge_path: String = ""
## Print each event line to standard output too. For tests and for checks without a screen.
var log_events: bool = false
## The name of a scene in `res://demo/` to play instead of reading the bridge ("" for the bridge).
var demo: String = ""
## The path of a timeline file to play (for example one in `user://`). It wins over `demo`.
var timeline: String = ""
## The speed of the simulation: 1.0 is real time.
var speed: float = 1.0
## Start with the clock paused.
var paused: bool = false
## Hide the status line, as for a recording.
var clean: bool = false
## Run the simulation this many seconds before the first frame (for screenshots).
var at: float = 0.0
## The most penguins in all arenas.
var penguin_limit: int = DEFAULT_PENGUIN_LIMIT
## The agents in an arena. 0 is one room for everyone. A scene may ask for its own (`options` of the timeline) unless this was set.
var arena_size: int = DEFAULT_ARENA_SIZE
var arena_size_set: bool = false
## Seconds after which a quiet agent leaves its arena. 0 is off.
var leave_after: float = DEFAULT_LEAVE_AFTER
## Start the camera in MANUAL (the 2D mockup's `?follow=manual`).
var follow_manual: bool = false
## Play this scene in real time with no interface, write one line for each frame to `benchmark_out` and quit (see
## `src/view/benchmark.gd`). Empty for a normal run.
var benchmark: String = ""
var benchmark_out: String = ""
## Play the benchmark at the speed of the scene's real time but with vsync off, to see the headroom.
var vsync_off: bool = false
## Write the times of the start-up to this file after the first frames and quit (see `startup_report.gd`). Empty for a normal run.
var startup_report: String = ""
## Print the average cost of a frame to standard output every five seconds (see `LiveView._print_frame_stats`).
var frame_stats: bool = false
## Treat the window as if it had the focus (1) or not (0), whatever the system says. -1 follows the system. For `tools/cost.mjs`, when a
## window cannot be put in the background (the system keeps the foreground window).
var forced_focus: int = -1
## The frame cap of a window with focus. 0 means no cap.
var focused_fps: int = DEFAULT_FOCUSED_FPS
## The frame cap of an unfocused window. 0 means no cap.
var unfocused_fps: int = DEFAULT_UNFOCUSED_FPS
## The room does not shake after a failure.
var reduced_motion: bool = false
## Start with sound on: "on", "events" (event sounds only), "off", or the name of a tune. Empty for the default: all sound off.
var sound: String = ""
## Recording mode (phase G-8): the frame rate of the recording, or 0 for a normal run. `tools/record.mjs` sets it together with
## the engine's own `--write-movie` and `--fixed-fps`. In this mode frame number `i` shows the story at the time `i / record_fps`, the
## window policy and the keys and the mouse are off, a scene is played once, and the client quits after the last frame.
var record_fps: int = 0
## The times (in seconds of the clip) of the pictures to save: the simulation runs with no drawing up to each time, draws one frame, and
## saves the 480x270 viewport as a PNG file in `stills_out`. The client quits after the last one.
var stills: PackedFloat64Array = []
var stills_out: String = ""
## The sound menu is open for the first seconds of a recording.
var menu_seconds: float = 0.0
## Turn the event sounds off (the tune keeps playing): the mockup's `--events 0`.
var events_off: bool = false
## Do not draw the sound switch (for a clip that must not show it).
var hide_switch: bool = false
## Print a line "[trace] <who>: <station>" each time a penguin begins to visit a station (see `core/trace_log.gd`). For tests and for checks
## without a screen, for example `tools/replay.test.mjs`.
var trace: bool = false
## Problems found while reading the arguments. The client shows them.
var warnings: PackedStringArray = []


## The frame rate of a recording when `--record` has no rate.
const DEFAULT_RECORD_FPS := 30

## The arguments of tools/shot.gd. The tool reads them and the scene sees them too, so they are not a mistake.
const TOOL_ARGUMENTS: Array[String] = ["--scene=", "--out=", "--frames=", "--count=", "--shots="]


static func _is_tool_argument(arg: String) -> bool:
	for prefix in TOOL_ARGUMENTS:
		if arg.begins_with(prefix):
			return true
	return false


## Read the user arguments (the ones after `--`). `OS.get_cmdline_user_args()` gives them.
static func parse(args: PackedStringArray) -> RefCounted:
	var options: RefCounted = new()
	for arg in args:
		if arg.begins_with("--bridge="):
			var url: String = arg.trim_prefix("--bridge=")
			if url.begins_with("ws://") or url.begins_with("wss://"):
				options.bridge = url
			else:
				options.warnings.append("Ignored --bridge: the address must start with ws:// or wss://")
		elif arg == "--start-bridge":
			options.start_bridge = true
			options.start_bridge_set = true
		elif arg.begins_with("--start-bridge="):
			options.start_bridge = true
			options.start_bridge_set = true
			options.bridge_path = arg.trim_prefix("--start-bridge=")
		elif arg == "--no-start-bridge":
			options.start_bridge = false
			options.start_bridge_set = true
		elif arg == "--log-events":
			options.log_events = true
		elif arg.begins_with("--demo="):
			options.demo = arg.trim_prefix("--demo=")
		elif arg.begins_with("--timeline="):
			options.timeline = arg.trim_prefix("--timeline=")
		elif arg.begins_with("--speed="):
			var value: String = arg.trim_prefix("--speed=")
			if value.is_valid_float() and float(value) > 0.0:
				options.speed = float(value)
			else:
				options.warnings.append("Ignored --speed: it must be a number above 0")
		elif arg == "--paused":
			options.paused = true
		elif arg == "--clean":
			options.clean = true
		elif arg.begins_with("--at="):
			var seconds: String = arg.trim_prefix("--at=")
			if seconds.is_valid_float() and float(seconds) >= 0.0:
				options.at = float(seconds)
			else:
				options.warnings.append("Ignored --at: it must be a number of seconds")
		elif arg.begins_with("--limit="):
			var count: String = arg.trim_prefix("--limit=")
			if count.is_valid_int() and int(count) >= 1:
				options.penguin_limit = int(count)
			else:
				options.warnings.append("Ignored --limit: it must be a whole number above 0")
		elif arg.begins_with("--arena-size="):
			var size: String = arg.trim_prefix("--arena-size=")
			if size.is_valid_int() and int(size) >= 0:
				options.arena_size = int(size)
				options.arena_size_set = true
			else:
				options.warnings.append("Ignored --arena-size: it must be a whole number, 0 or more")
		elif arg.begins_with("--leave-after="):
			var seconds_text: String = arg.trim_prefix("--leave-after=")
			if seconds_text.is_valid_float() and float(seconds_text) >= 0.0:
				options.leave_after = float(seconds_text)
			else:
				options.warnings.append("Ignored --leave-after: it must be a number of seconds, 0 or more")
		elif arg == "--follow=manual":
			options.follow_manual = true
		elif arg == "--follow=auto":
			options.follow_manual = false
		elif arg.begins_with("--benchmark="):
			options.benchmark = arg.trim_prefix("--benchmark=")
		elif arg.begins_with("--benchmark-out="):
			options.benchmark_out = arg.trim_prefix("--benchmark-out=")
		elif arg == "--force-focus=true":
			options.forced_focus = 1
		elif arg == "--force-focus=false":
			options.forced_focus = 0
		elif arg == "--frame-stats":
			options.frame_stats = true
		elif arg.begins_with("--startup-report="):
			options.startup_report = arg.trim_prefix("--startup-report=")
		elif arg == "--vsync=off":
			options.vsync_off = true
		elif arg == "--vsync=on":
			options.vsync_off = false
		elif arg.begins_with("--focused-fps="):
			var focused: String = arg.trim_prefix("--focused-fps=")
			if focused.is_valid_int() and int(focused) >= 0:
				options.focused_fps = int(focused)
			else:
				options.warnings.append("Ignored --focused-fps: it must be a whole number, 0 or more")
		elif arg.begins_with("--unfocused-fps="):
			var fps: String = arg.trim_prefix("--unfocused-fps=")
			if fps.is_valid_int() and int(fps) >= 0:
				options.unfocused_fps = int(fps)
			else:
				options.warnings.append("Ignored --unfocused-fps: it must be a whole number, 0 or more")
		elif arg.begins_with("--sound="):
			options.sound = arg.trim_prefix("--sound=")
		elif arg == "--reduced-motion":
			options.reduced_motion = true
		elif arg == "--record":
			options.record_fps = DEFAULT_RECORD_FPS
		elif arg.begins_with("--record-fps="):
			var rate: String = arg.trim_prefix("--record-fps=")
			if rate.is_valid_int() and int(rate) >= 1 and int(rate) <= 240:
				options.record_fps = int(rate)
			else:
				options.warnings.append("Ignored --record-fps: it must be a whole number from 1 to 240")
		elif arg.begins_with("--stills="):
			options.stills = parse_times(arg.trim_prefix("--stills="))
			if options.stills.is_empty():
				options.warnings.append("Ignored --stills: give seconds, for example --stills=7,22.5")
		elif arg.begins_with("--stills-out="):
			options.stills_out = arg.trim_prefix("--stills-out=")
		elif arg.begins_with("--menu="):
			var menu_text: String = arg.trim_prefix("--menu=")
			if menu_text.is_valid_float() and float(menu_text) >= 0.0:
				options.menu_seconds = float(menu_text)
			else:
				options.warnings.append("Ignored --menu: it must be a number of seconds")
		elif arg == "--events=0":
			options.events_off = true
		elif arg == "--events=1":
			options.events_off = false
		elif arg == "--no-switch":
			options.hide_switch = true
		elif arg == "--trace":
			options.trace = true
		elif _is_tool_argument(arg):
			pass
		else:
			options.warnings.append("Ignored unknown argument: %s" % arg)
	return options


## "7,22.5,40" as a list of seconds. Items that are not numbers, or are below 0, are left out.
static func parse_times(text: String) -> PackedFloat64Array:
	var times: PackedFloat64Array = []
	for part in text.split(",", false):
		var item: String = part.strip_edges()
		if item.is_valid_float() and float(item) >= 0.0:
			times.append(float(item))
	return times


## True in recording mode (frames or stills for a file) and false in a normal run.
func recording() -> bool:
	return record_fps > 0 or not stills.is_empty()
