extends Node
## Spike S-6: the runner. It plays each case for some seconds and writes one line of numbers to a CSV file.
## A case is a way (see s6_world.gd), a number of rooms, and a scale (a number, "fit", or "zoom").
##
## godot --path godot res://spikes/s6/s6_runner.tscn -- --s6-out=results.csv [options]
##
## Options (after "--"):
##   --s6-out=FILE        the CSV file. The runner adds lines to it, and writes the header when the file is new.
##   --s6-vsync=on|off|both   vsync of the window (default both: off first, then on)
##   --s6-seconds=N       the length of the measured part of a run (default 10)
##   --s6-methods=A,B     only these ways (default all of them)
##   --s6-counts=1,4      only these room counts (default 1,4,9,16)
##   --s6-scales=1,0.5,fit,zoom   only these scales (default all four; "fit" is skipped for 1 room)
##   --s6-shots=DIR       take pictures and compare them, instead of measuring (see _run_shots)
##   --s6-snap=off        turn off the project's pixel snapping of 2D transforms and vertices
##   --s6-quit-after=N    stop after N runs (a test of the runner)

const World := preload("res://spikes/s6/s6_world.gd")
const Stats := preload("res://spikes/s6/s6_stats.gd")

const WARMUP_SECONDS := 1.0
## The zoom goes from scale 1 to the fit scale (to 0.5 for one room) and back. One round trip takes this long.
const ZOOM_PERIOD := 4.0
const HEADER := "way,rooms,scale,vsync,seconds,frames,mean_ms,median_ms,p95_ms,p99_ms,worst_ms,over_16_7_pct,fps_mean,process_ms_median,draw_calls_median,rooms_in_view_min,rooms_in_view_max,gpu_ms_median,mem_mb,static_mem_mb,video_mem_mb"

var _out_path: String = "user://s6.csv"
var _seconds: float = 10.0
var _vsync_values: Array[bool] = [false, true]
var _methods: Array[String] = []
var _counts: Array[int] = [1, 4, 9, 16]
var _scales: Array[String] = ["1", "0.5", "fit", "zoom"]
var _runs: Array[Dictionary] = []
var _run_index: int = 0
var _world: Node2D
var _run: Dictionary = {}
var _last_usec: int = 0
var _run_start_usec: int = 0
var _frame_ms: PackedFloat64Array = PackedFloat64Array()
var _process_ms: PackedFloat64Array = PackedFloat64Array()
var _draw_calls: PackedFloat64Array = PackedFloat64Array()
var _gpu_ms: PackedFloat64Array = PackedFloat64Array()
var _in_view_min: int = 0
var _in_view_max: int = 0
var _quit_after: int = -1
var _finished_runs: int = 0
var _shots_dir: String = ""


func _ready() -> void:
	_methods.assign(World.METHODS)
	var snap_off: bool = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--s6-out="):
			_out_path = arg.trim_prefix("--s6-out=")
		elif arg.begins_with("--s6-vsync="):
			var value: String = arg.trim_prefix("--s6-vsync=")
			_vsync_values.clear()
			if value == "both":
				_vsync_values.append(false)
				_vsync_values.append(true)
			else:
				_vsync_values.append(value == "on")
		elif arg.begins_with("--s6-seconds="):
			_seconds = float(arg.trim_prefix("--s6-seconds="))
		elif arg.begins_with("--s6-methods="):
			_methods.assign(Array(arg.trim_prefix("--s6-methods=").split(",")))
		elif arg.begins_with("--s6-counts="):
			_counts.clear()
			for part in arg.trim_prefix("--s6-counts=").split(","):
				_counts.append(int(part))
		elif arg.begins_with("--s6-scales="):
			_scales.assign(Array(arg.trim_prefix("--s6-scales=").split(",")))
		elif arg.begins_with("--s6-shots="):
			_shots_dir = arg.trim_prefix("--s6-shots=")
		elif arg == "--s6-snap=off":
			snap_off = true
		elif arg.begins_with("--s6-quit-after="):
			_quit_after = int(arg.trim_prefix("--s6-quit-after="))
	if snap_off:
		get_viewport().snap_2d_transforms_to_pixel = false
		get_viewport().snap_2d_vertices_to_pixel = false
	RenderingServer.set_default_clear_color(Color("#1b2236"))
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if not _shots_dir.is_empty():
		_run_shots()
		return
	for vsync in _vsync_values:
		for way in _methods:
			for count in _counts:
				for scale_name in _scales:
					if scale_name == "fit" and count == 1:
						continue
					_runs.append({"way": way, "rooms": count, "scale": scale_name, "vsync": vsync})
	print("s6: %d runs of %.0f s each, output %s" % [_runs.size(), _seconds + WARMUP_SECONDS, _out_path])
	print("s6: cpu=%s gpu=%s (%s) refresh=%.0f Hz screen=%s window=%s" % [OS.get_processor_name(), RenderingServer.get_video_adapter_name(), _adapter_type(), DisplayServer.screen_get_refresh_rate(), DisplayServer.screen_get_size(), DisplayServer.window_get_size()])


func _adapter_type() -> String:
	match RenderingServer.get_video_adapter_type():
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			return "integrated"
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			return "discrete"
		RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU:
			return "virtual"
		RenderingDevice.DEVICE_TYPE_CPU:
			return "cpu"
	return "other"


func _process(delta: float) -> void:
	if not _shots_dir.is_empty():
		return
	var now: int = Time.get_ticks_usec()
	if _world == null:
		if _run_index >= _runs.size() or (_quit_after >= 0 and _finished_runs >= _quit_after):
			print("s6: done")
			get_tree().quit()
			return
		_start_run()
		_last_usec = Time.get_ticks_usec()
		return
	var frame_ms: float = float(now - _last_usec) / 1000.0
	_last_usec = now
	var t: float = float(now - _run_start_usec) / 1e6
	_apply_zoom(t)
	_world.tick(minf(delta, 0.05))
	if t >= WARMUP_SECONDS:
		_frame_ms.append(frame_ms)
		_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_draw_calls.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		var in_view: int = _world.visible_rooms()
		_in_view_min = mini(_in_view_min, in_view)
		_in_view_max = maxi(_in_view_max, in_view)
	if t >= WARMUP_SECONDS + _seconds:
		_finish_run()


func _start_run() -> void:
	_run = _runs[_run_index]
	var vsync: bool = _run["vsync"]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	_world = World.new()
	add_child(_world)
	_world.build(_run["way"], _run["rooms"])
	_frame_ms.clear()
	_process_ms.clear()
	_draw_calls.clear()
	_gpu_ms.clear()
	_apply_zoom(0.0)
	_in_view_min = _world.count
	_in_view_max = 0
	_run_start_usec = Time.get_ticks_usec()


## The scale of a run at time t: a fixed number, the fit scale, or a zoom between 1 and the fit scale.
func _scale_at(t: float) -> float:
	var scale_name: String = _run["scale"]
	var fit: float = _world.fit_scale()
	if scale_name == "fit":
		return fit
	if scale_name == "zoom":
		var low: float = 0.5 if _run["rooms"] == 1 else fit
		var phase: float = 0.5 + 0.5 * cos(TAU * t / ZOOM_PERIOD)
		return low + (1.0 - low) * phase
	return float(scale_name)


func _apply_zoom(t: float) -> void:
	_world.set_view_scale(_scale_at(t))


func _finish_run() -> void:
	var summary: Dictionary = Stats.summarize(_frame_ms)
	var process: Dictionary = Stats.summarize(_process_ms)
	var calls: Dictionary = Stats.summarize(_draw_calls)
	var gpu: Dictionary = Stats.summarize(_gpu_ms)
	var mean: float = summary["mean"]
	var line: String = "%s,%d,%s,%s,%.0f,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.2f,%.1f,%.3f,%.0f,%d,%d,%.3f,%.1f,%.1f,%.1f" % [
		_run["way"], _run["rooms"], _run["scale"], "on" if _run["vsync"] else "off", _seconds,
		summary["count"], summary["mean"], summary["median"], summary["p95"], summary["p99"], summary["worst"],
		summary["over_share"], 1000.0 / mean if mean > 0.0 else 0.0, process["median"], calls["median"],
		_in_view_min, _in_view_max, gpu["median"], _process_memory_mb(), float(OS.get_static_memory_usage()) / 1048576.0,
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0,
	]
	_append_line(line)
	print("s6: %s" % line)
	_world.queue_free()
	_world = null
	_run_index += 1
	_finished_runs += 1


## The working set of this process in MB, read with tasklist (Windows). Zero when it is not available.
func _process_memory_mb() -> float:
	if OS.get_name() != "Windows":
		return 0.0
	var output: Array = []
	var code: int = OS.execute("tasklist", ["/FI", "PID eq %d" % OS.get_process_id(), "/FO", "CSV", "/NH"], output)
	if code != 0 or output.is_empty():
		return 0.0
	var fields: PackedStringArray = String(output[0]).strip_edges().split("\",\"")
	if fields.size() < 5:
		return 0.0
	var digits: String = ""
	for ch in fields[4]:
		if ch >= "0" and ch <= "9":
			digits += ch
	return float(digits) / 1024.0


func _append_line(line: String) -> void:
	var is_new: bool = not FileAccess.file_exists(_out_path)
	var file: FileAccess = FileAccess.open(_out_path, FileAccess.READ_WRITE if not is_new else FileAccess.WRITE)
	if file == null:
		push_error("s6: cannot open %s" % _out_path)
		return
	file.seek_end()
	if is_new:
		file.store_line(HEADER)
	file.store_line(line)
	file.close()


## Pictures. For each way, the same rooms are drawn at fixed scales with the same moves (40 steps of 1/60 s), and
## the picture is saved as it is (480x270) and four times larger (nearest). Then the pictures of a single room at the
## scales 0.5 and 0.25 are compared with the mean of the blocks of the picture at scale 1 (what a perfect shrink
## gives). The result is a line for each picture in `metrics.csv` in the same folder.
func _run_shots() -> void:
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	var shots: Array[Dictionary] = [
		{"id": "n1_s100", "rooms": 1, "scale": 1.0, "anchor": Vector2(0, 0)},
		{"id": "n1_s050", "rooms": 1, "scale": 0.5, "anchor": Vector2(120, 60)},
		{"id": "n1_s025", "rooms": 1, "scale": 0.25, "anchor": Vector2(180, 90)},
		{"id": "n4_s050", "rooms": 4, "scale": 0.5, "anchor": null},
		{"id": "n9_s037", "rooms": 9, "scale": 0.37, "anchor": null},
		{"id": "n16_fit", "rooms": 16, "scale": -1.0, "anchor": null},
	]
	var metrics: Array[String] = ["way,picture,mean_abs_diff_0_255"]
	var references: Dictionary = {}
	for way in _methods:
		var images: Dictionary = {}
		for shot in shots:
			_world = World.new()
			add_child(_world)
			_world.build(way, shot["rooms"])
			var s: float = float(shot["scale"])
			if s < 0.0:
				s = _world.fit_scale()
			_world.set_view_scale(s, shot["anchor"])
			for step in 40:
				_world.tick(1.0 / 60.0)
			for frame in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var image: Image = get_viewport().get_texture().get_image()
			image.convert(Image.FORMAT_RGBA8)
			var id: String = shot["id"]
			images[id] = image
			image.save_png("%s/%s_%s.png" % [_shots_dir, way, id])
			var big: Image = image.duplicate()
			big.resize(image.get_width() * 4, image.get_height() * 4, Image.INTERPOLATE_NEAREST)
			big.save_png("%s/%s_%s_x4.png" % [_shots_dir, way, id])
			_world.queue_free()
			_world = null
			await get_tree().process_frame
		if way == "B-nearest":
			references["n1_s100"] = images["n1_s100"]
		var reference: Image = references.get("n1_s100", images["n1_s100"]) as Image
		for pair: Array in [["n1_s050", 2, Vector2i(120, 60), Vector2i(240, 116)], ["n1_s025", 4, Vector2i(180, 90), Vector2i(120, 58)]]:
			var diff: float = Stats.mean_diff_to_box_reference(images[pair[0]], pair[2], reference, pair[1], pair[3])
			metrics.append("%s,%s,%.3f" % [way, pair[0], diff])
			print("s6 shots: %s %s mean abs diff %.3f" % [way, pair[0], diff])
		print("s6 shots: image size %s" % images["n1_s100"].get_size())
	var file: FileAccess = FileAccess.open("%s/metrics.csv" % _shots_dir, FileAccess.WRITE)
	for line in metrics:
		file.store_line(line)
	file.close()
	print("s6 shots: done")
	get_tree().quit()
