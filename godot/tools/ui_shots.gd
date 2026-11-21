extends SceneTree
## Saves stills of the live view for the screenshot pass: one picture of the 480x270 viewport for each shot, all in one
## run. It needs a window (not --headless).
##
##   godot --path godot -s res://tools/ui_shots.gd -- --out=/some/folder --shots="session:12.5,arenas:11.5:menu,arenas:23.2:hover=137,237"
##
## A shot is `scene:seconds` and then actions, each after a colon:
##   `menu`        the follow menu is open
##   `tab`         the key Tab (the overview), and then one second of simulation for the zoom
##   `hover=x,y`   the mouse is at (x, y)
##   `key=NAME`    a key of the camera (F, Tab, Esc, Left, Right, N) and 0.6 s of simulation
##   `ever`        the link was open once (so a link that is not open is "reconnecting")
##   `down=N`      the link has not been open for N seconds
##   `sound=...`   the sound switch, set on the model only, so no sound plays: `on`, `menu`, `toast`, `events-off`,
##                `tune-NAME` (a tune; it also turns sound on), `hover-N` (the row under the mouse in the open menu, 0 to 5)
## The scene "live" is the live view with no bridge (and no events): it shows the state of the link.
## The file is `<scene>-<seconds>[-<action>...].png`. The scene starts as a demo scene does: with the clock paused at the time.

const LiveView := preload("res://src/view/live_view.gd")

var _out: String = "."
var _shots: PackedStringArray = []
var _next: int = 0
var _view: Node = null
var _wait: int = 0
var _name: String = ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=").split(",", false)
	# a hover has a comma in it: join "hover=x" and the number that follows
	var joined: PackedStringArray = []
	for part in _shots:
		if not joined.is_empty() and part.is_valid_int() and joined[joined.size() - 1].contains("hover="):
			joined[joined.size() - 1] += "," + part
		else:
			joined.append(part)
	_shots = joined
	DirAccess.make_dir_recursive_absolute(_out)


func _process(_delta: float) -> bool:
	if _view != null:
		_wait -= 1
		if _wait > 0:
			return false
		var image: Image = root.get_texture().get_image()
		var error: int = image.save_png("%s/%s.png" % [_out, _name])
		print("shot: %s (error %d)" % [_name, error])
		_view.queue_free()
		_view = null
		return false
	if _next >= _shots.size():
		quit()
		return true
	_start(_shots[_next])
	_next += 1
	return false


func _start(spec: String) -> void:
	var parts: PackedStringArray = spec.split(":")
	var scene_name: String = parts[0]
	var seconds: float = float(parts[1])
	_name = "%s-%s" % [scene_name, parts[1]]
	var packed: PackedScene = load("res://src/live.tscn")
	_view = packed.instantiate()
	root.add_child(_view)
	_view.client.set_process(false)
	if scene_name != "live":
		_view.load_scene(scene_name)
	_view.simulate(int(seconds / _view.clock.STEP))
	_view.clock.paused = true
	for i in range(2, parts.size()):
		var action: String = parts[i]
		_name += "-" + action.replace(",", "_").replace("=", "")
		if action == "menu":
			_view.interface.menu_open = true
		elif action == "tab":
			_view.camera.press("Tab", _view.clock.now)
			_view.clock.paused = false
			_view.simulate(60)
			_view.clock.paused = true
		elif action.begins_with("hover="):
			var xy: PackedStringArray = action.trim_prefix("hover=").split(",")
			_view.interface.hover_point = Vector2(float(xy[0]), float(xy[1]))
		elif action == "ever":
			_view._ever_open = true
		elif action.begins_with("down="):
			_view._down_since_msec -= int(float(action.trim_prefix("down=")) * 1000.0)
		elif action.begins_with("sound="):
			_sound(action.trim_prefix("sound="))
		elif action.begins_with("key="):
			_view.camera.press(action.trim_prefix("key="), _view.clock.now)
			_view.simulate(36)
	_view._sound_revision = -1
	_view._refresh()
	_wait = 6


## Changes the sound model for a shot. The players are not told, so nothing plays.
func _sound(what: String) -> void:
	var model: RefCounted = _view.sound_model
	if what == "on":
		model.on = true
	elif what == "menu":
		model.set_menu(true)
	elif what == "toast":
		model.toast = "all sound on   (M)"
		model.toast_until = _view._wall() + 100.0
	elif what == "events-off":
		model.events = false
	elif what.begins_with("tune-"):
		model.on = true
		model.tune = what.trim_prefix("tune-")
	elif what.begins_with("hover-"):
		model.menu_open = true
		model.hover = int(what.trim_prefix("hover-"))
