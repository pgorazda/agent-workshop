extends SceneTree
## Saves pictures of a scene: the 480x270 viewport after a few frames.
##
##   godot --path godot -s res://tools/shot.gd -- --scene=res://src/room.tscn --out=/path/to/room.png [--frames=6] [scene options]
##   godot --path godot -s res://tools/shot.gd -- --scene=res://src/live.tscn --out=/path/to/shot_%d.png --frames=120 --count=5
##
## It needs a window (not --headless). `--frames` is the number of frames before the first picture (and between pictures).
## `--count` is the number of pictures. An `--out` with `%d` in it gets the number of the picture (from 1). The arguments
## that it does not know go to the scene, as `--rug=cobalt`.

var _frames_left: int = 6
var _interval: int = 6
var _count: int = 1
var _taken: int = 0
var _out: String = ""


func _initialize() -> void:
	var scene_path: String = "res://src/room.tscn"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scene_path = arg.trim_prefix("--scene=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--frames="):
			_interval = int(arg.trim_prefix("--frames="))
			_frames_left = _interval
		elif arg.begins_with("--count="):
			_count = maxi(1, int(arg.trim_prefix("--count=")))
	var packed: PackedScene = load(scene_path)
	root.add_child(packed.instantiate())


func _process(_delta: float) -> bool:
	_frames_left -= 1
	if _frames_left > 0:
		return false
	if _out.is_empty():
		push_error("shot.gd: --out=<file> is missing")
		quit(1)
		return true
	var image: Image = root.get_texture().get_image()
	_taken += 1
	var path: String = _out % _taken if _out.contains("%d") else _out
	var error: int = image.save_png(path)
	print("shot: %dx%d to %s (error %d)" % [image.get_width(), image.get_height(), path, error])
	if error != OK or _taken >= _count:
		quit(error)
		return true
	_frames_left = _interval
	return false
