extends SceneTree
## Writes the notices of the Godot engine: its own license, the copyright lines of the parts it includes, and the texts of
## their licenses. The apps are built with the engine, and its license asks that the notice ships with them.
##
##   "$GODOT" --headless --path . -s res://tools/licenses.gd -- --out=THIRD-PARTY-NOTICES.txt
##
## The text comes from the engine itself, so it matches the pinned version (GODOT_VERSION).


func _init() -> void:
	var out_path: String = "THIRD-PARTY-NOTICES.txt"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var version: Dictionary = Engine.get_version_info()
	var lines: PackedStringArray = []
	lines.append("Third-party notices for the Agent Workshop app")
	lines.append("")
	lines.append("The app is made with the Godot Engine %s." % version.get("string", ""))
	lines.append("The engine is under the MIT license. The notices below are those that the engine itself reports.")
	lines.append("The pictures of text in the app are drawn from the fonts Tiny5 and Silkscreen (SIL Open Font License 1.1).")
	lines.append("")
	lines.append("=".repeat(78))
	lines.append("Godot Engine license")
	lines.append("=".repeat(78))
	lines.append(Engine.get_license_text().strip_edges())
	lines.append("")
	lines.append("=".repeat(78))
	lines.append("Parts of the engine and their copyright")
	lines.append("=".repeat(78))
	for component in Engine.get_copyright_info():
		lines.append("")
		lines.append(str(component.get("name", "")))
		for part in component.get("parts", []):
			for file in part.get("files", []):
				lines.append("  files: %s" % file)
			for copyright_line in part.get("copyright", []):
				lines.append("  copyright: %s" % copyright_line)
			lines.append("  license: %s" % part.get("license", ""))
	lines.append("")
	lines.append("=".repeat(78))
	lines.append("License texts")
	lines.append("=".repeat(78))
	var texts: Dictionary = Engine.get_license_info()
	var names: Array = texts.keys()
	names.sort()
	for license_name in names:
		lines.append("")
		lines.append("--- %s" % license_name)
		lines.append(str(texts[license_name]).strip_edges())
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % out_path)
		quit(1)
		return
	file.store_string("\n".join(lines) + "\n")
	file.close()
	print("wrote %s (%d lines)" % [out_path, lines.size()])
	quit(0)
