extends SceneTree
## Measures how long the art takes to load, in a fresh process: the script of the atlas data, then each sheet.
## Run it with:  godot --headless --path godot -s res://tools/load_probe.gd
## A headless run has no GPU, so the times do not include the upload of the textures. The gallery prints the time with the upload:
##   godot --path godot res://src/gallery.tscn --quit-after 3


func _initialize() -> void:
	var started: int = Time.get_ticks_usec()
	var data: GDScript = load("res://art/atlas_data.gd") as GDScript
	var data_ms: float = (Time.get_ticks_usec() - started) / 1000.0
	var sheets: Array = data.get("SHEETS")
	var pictures: Dictionary = data.get("PICTURES")
	var total_started: int = Time.get_ticks_usec()
	var bytes: int = 0
	var lines: Array[String] = []
	for path: String in sheets:
		var t0: int = Time.get_ticks_usec()
		var texture: Texture2D = load(path) as Texture2D
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		bytes += texture.get_width() * texture.get_height() * 4
		lines.append("  %-44s %4dx%-4d %6.2f ms" % [path.get_file(), texture.get_width(), texture.get_height(), ms])
	var sheets_ms: float = (Time.get_ticks_usec() - total_started) / 1000.0
	for line in lines:
		print(line)
	print("atlas data: %.2f ms (%d pictures); %d sheets: %.2f ms (%.1f MB of pixels in memory)" % [data_ms, pictures.size(), sheets.size(), sheets_ms, bytes / 1048576.0])
	quit()
