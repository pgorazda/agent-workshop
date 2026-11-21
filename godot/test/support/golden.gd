extends RefCounted
## Helpers for the golden-data tests: read a fixture of the JavaScript mockup (a fixed snapshot, see test/fixtures/README.md), turn the JavaScript
## names and numbers into the GDScript ones, and compare two values with a tolerance for floats.

const TOLERANCE := 1e-9


## The parsed JSON of a fixture, or `null` when the file is missing or broken.
static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return JSON.parse_string(file.get_as_text())


## The fixture files in `res://test/fixtures/` whose name starts with `prefix`, sorted.
static func fixture_files(prefix: String) -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open("res://test/fixtures")
	if dir == null:
		return found
	for file in dir.get_files():
		if file.begins_with(prefix) and file.ends_with(".json"):
			found.append("res://test/fixtures/".path_join(file))
	found.sort()
	return found


## JSON has no Infinity. The tool writes "Infinity", "-Infinity" and "NaN" as strings. This puts the numbers back.
static func decode(value: Variant) -> Variant:
	match typeof(value):
		TYPE_STRING:
			if value == "Infinity":
				return INF
			if value == "-Infinity":
				return -INF
			if value == "NaN":
				return NAN
			return value
		TYPE_ARRAY:
			var list: Array = []
			for item: Variant in (value as Array):
				list.append(decode(item))
			return list
		TYPE_DICTIONARY:
			var dict: Dictionary = { }
			for key: Variant in (value as Dictionary):
				dict[key] = decode((value as Dictionary)[key])
			return dict
	return value


## `holdAfterMove` -> `hold_after_move`.
static func snake(key: String) -> String:
	var out: String = ""
	for i in key.length():
		var c: String = key[i]
		if i > 0 and c != c.to_lower() and key[i - 1] == key[i - 1].to_lower() and key[i - 1] != "_":
			out += "_"
		out += c.to_lower()
	return out


## The keys of a dictionary in snake_case. Only the top level changes.
static func snake_keys(dict: Dictionary) -> Dictionary:
	var out: Dictionary = { }
	for key: Variant in dict:
		out[snake(str(key))] = dict[key]
	return out


## A camera spec of the JavaScript (`focusEvents`, `opts.reducedMotion`) as a spec for `simulate_camera`.
static func camera_spec(spec: Dictionary) -> Dictionary:
	var out: Dictionary = snake_keys(decode(spec))
	if out.has("opts"):
		out["opts"] = snake_keys(out["opts"])
	return out


## The frames of a camera case: the first frame whole, every other frame as the keys that changed.
## This puts the whole frames back, with `t` and the snake_case keys.
static func expand_frames(expected: Dictionary) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	var step: float = expected["step"]
	var current: Dictionary = { }
	var index: int = 0
	for delta: Dictionary in expected["frames"]:
		current = current.duplicate()
		current.merge(snake_keys(decode(delta)), true)
		var frame: Dictionary = current.duplicate()
		frame["t"] = float(index) * step
		frames.append(frame)
		index += 1
	return frames


## The first difference between two values, as text, or "" when they agree. Numbers (int or float) agree
## within `tolerance`. Dictionaries need the same keys. Typed and untyped arrays are the same.
static func diff(expected: Variant, actual: Variant, path: String = "$", tolerance: float = TOLERANCE) -> String:
	var expected_type: int = typeof(expected)
	var actual_type: int = typeof(actual)
	var expected_number: bool = expected_type == TYPE_INT or expected_type == TYPE_FLOAT
	var actual_number: bool = actual_type == TYPE_INT or actual_type == TYPE_FLOAT
	if expected_number and actual_number:
		var e: float = expected
		var a: float = actual
		if e == a or (is_nan(e) and is_nan(a)) or absf(e - a) <= tolerance:
			return ""
		return "%s: expected %s, got %s" % [path, e, a]
	if expected_type != actual_type:
		return "%s: expected %s (%s), got %s (%s)" % [path, str(expected), type_string(expected_type), str(actual), type_string(actual_type)]
	if expected_type == TYPE_ARRAY:
		var expected_list: Array = expected
		var actual_list: Array = actual
		if expected_list.size() != actual_list.size():
			return "%s: expected %d items, got %d (expected %s, got %s)" % [path, expected_list.size(), actual_list.size(), str(expected_list), str(actual_list)]
		for i in expected_list.size():
			var found: String = diff(expected_list[i], actual_list[i], "%s[%d]" % [path, i], tolerance)
			if found != "":
				return found
		return ""
	if expected_type == TYPE_DICTIONARY:
		var expected_dict: Dictionary = expected
		var actual_dict: Dictionary = actual
		for key: Variant in expected_dict:
			if not actual_dict.has(key):
				return "%s: the key %s is missing" % [path, str(key)]
			var found: String = diff(expected_dict[key], actual_dict[key], "%s.%s" % [path, str(key)], tolerance)
			if found != "":
				return found
		for key: Variant in actual_dict:
			if not expected_dict.has(key):
				return "%s: the key %s is extra" % [path, str(key)]
		return ""
	if expected != actual:
		return "%s: expected %s, got %s" % [path, str(expected), str(actual)]
	return ""
