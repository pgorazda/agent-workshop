extends SceneTree
## A headless program for tools/launcher.test.mjs. It runs the real bridge launcher (ADR 0014) and prints one line for each thing that
## happens, so that the Node test can read the lines:
##
##   STATE <idle|checking|starting|running|using_existing|failed>
##   NOTE <text>
##   PID <process id of the bridge that the launcher started>
##
## Start it with:
##   godot --headless --path godot -s res://tools/launcher_probe.gd -- --bridge=ws://127.0.0.1:PORT/ws --start-bridge=<program> [--probe-quit-after=3]
## With `--probe-quit-after`, it leaves the tree of nodes and quits after that many seconds, as a normal quit of the app does.

const Options := preload("res://src/core/options.gd")
const BridgeLauncher := preload("res://src/net/bridge_launcher.gd")

var _launcher: Node
var _last_state: int = -1
var _quit_after: float = -1.0
var _elapsed: float = 0.0
var _pid_printed: bool = false


func _initialize() -> void:
	Engine.max_fps = 60
	var options: RefCounted = Options.parse(OS.get_cmdline_user_args())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-quit-after="):
			_quit_after = float(arg.trim_prefix("--probe-quit-after="))
	_launcher = BridgeLauncher.new()
	_launcher.note.connect(func(text: String) -> void: print("NOTE %s" % text))
	root.add_child(_launcher)
	_launcher.start(options.bridge, options.bridge_path)


func _process(delta: float) -> bool:
	if _launcher.state != _last_state:
		_last_state = _launcher.state
		print("STATE %s" % BridgeLauncher.State.keys()[_last_state].to_lower())
	if _launcher.pid > 0 and not _pid_printed:
		_pid_printed = true
		print("PID %d" % _launcher.pid)
	_elapsed += delta
	if _quit_after >= 0.0 and _elapsed >= _quit_after:
		root.remove_child(_launcher)
		_launcher.free()
		quit()
	return false
