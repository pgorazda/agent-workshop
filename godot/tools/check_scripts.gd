extends SceneTree
## Loads every GDScript file of the project (not the addons). Godot prints the parse errors and the
## warnings while it loads. `check.mjs` reads that output and fails when it finds any.

const ROOTS: Array[String] = ["res://src", "res://art", "res://test", "res://tools"]


func _init() -> void:
	var failed: Array[String] = []
	var count: int = 0
	for folder in ROOTS:
		for path in _scripts_in(folder):
			if path == get_script().resource_path:
				continue
			count += 1
			var script: Resource = ResourceLoader.load(path)
			if script == null:
				failed.append(path)
	print("CHECKED %d scripts" % count)
	for path in failed:
		print("FAILED TO LOAD %s" % path)
	quit(1 if not failed.is_empty() else 0)


func _scripts_in(folder: String) -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return found
	for file in dir.get_files():
		if file.ends_with(".gd"):
			found.append(folder.path_join(file))
	for sub in dir.get_directories():
		found.append_array(_scripts_in(folder.path_join(sub)))
	return found
