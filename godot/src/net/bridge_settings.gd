extends RefCounted
## The saved setting that starts the bridge (ADR 0014). It lives in `user://settings.cfg`:
##
##   [bridge]
##   start=true
##   path="/path/to/agent-workshop-bridge"
##
## `start` is off when the file or the key is missing. `path` is optional: when it is empty, the launcher looks next to the app and
## on the PATH. The command line wins over the file: `--start-bridge[=<path>]` and `--no-start-bridge` (see `core/options.gd`).

const FILE := "user://settings.cfg"
const SECTION := "bridge"


## The saved values: { "start": bool, "path": String }. A missing or unreadable file gives the defaults.
static func read(file: String = FILE) -> Dictionary:
	var values: Dictionary = { "start": false, "path": "" }
	var config := ConfigFile.new()
	if config.load(file) != OK:
		return values
	values["start"] = bool(config.get_value(SECTION, "start", false))
	values["path"] = str(config.get_value(SECTION, "path", ""))
	return values


## Saves the values. Returns false when the file cannot be written.
static func write(start: bool, path: String, file: String = FILE) -> bool:
	var config := ConfigFile.new()
	config.load(file) # keep the other sections, if there are any
	config.set_value(SECTION, "start", start)
	config.set_value(SECTION, "path", path)
	return config.save(file) == OK


## Puts the saved values in the options, unless the command line already decided.
static func apply(options: RefCounted, file: String = FILE) -> void:
	if options.start_bridge_set:
		return
	var values: Dictionary = read(file)
	options.start_bridge = values["start"]
	if options.bridge_path == "":
		options.bridge_path = values["path"]
