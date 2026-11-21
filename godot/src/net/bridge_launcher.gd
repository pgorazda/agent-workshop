extends Node
## Starts the bridge program when the person asked for it (ADR 0014). The rules:
##
## * Only for a local address (127.0.0.1, localhost or ::1 with ws://). The program gets the loopback host of the address (`::1` for `::1`,
##   else `127.0.0.1`) and the port of the address.
## * Only when no bridge answers `GET /health` there. A bridge that already runs is used, and never stopped.
## * The program is the configured path, or `agent-workshop-bridge` next to the app, or on the PATH. It is never downloaded.
## * One start for each run of the app. If it fails, one short note says why (`note` signal) and the client goes on reconnecting.
## * The app stops only the bridge that it started, when it quits. The bridge also ends by itself when the app crashes: the app holds
##   the pipe to its standard input, and `--exit-when-stdin-closes` makes the bridge stop when that pipe closes.
##
## The program is started without a shell, with an argument list. Its output is read all the time by two threads, so that a bridge
## that writes a lot can never block on a full pipe.

signal note(text: String)

enum State { IDLE, CHECKING, STARTING, RUNNING, USING_EXISTING, FAILED }

const PROGRAM := "agent-workshop-bridge"
## How long the check of `GET /health` may take.
const HEALTH_TIMEOUT_SECONDS := 0.5
## How long the program may take to say that it listens.
const START_TIMEOUT_SECONDS := 5.0
## After the program ended, the time to collect its error text from the pipe.
const EXIT_GRACE_SECONDS := 0.4
const MAX_ERROR_LINES := 10
const MAX_NOTE_CHARACTERS := 90

var state: State = State.IDLE
var pid: int = -1
## The notes that were sent, for tests.
var notes: PackedStringArray = []

var _port: int = 0
## The loopback host that the program listens on and that the health check asks: "::1" or "127.0.0.1".
var _host: String = "127.0.0.1"
var _configured_path: String = ""
var _program: String = ""
var _stdio: FileAccess = null
var _stderr: FileAccess = null
var _threads: Array[Thread] = []
var _mutex := Mutex.new()
var _first_line: String = ""
var _error_lines: PackedStringArray = []
var _waited: float = 0.0
var _gone_for: float = -1.0
var _http: HTTPRequest = null
## True after `start()` until the first frame: the check of `/health` needs the node to be in the tree.
var _begin_pending: bool = false
## Set when the program is gone. The reader threads stop on it (a pipe at its end may give empty lines for ever). Guarded by the mutex.
var _gone: bool = false


# ---------------------------------------------------------------- pure helpers (tested alone)

## The parts of a bridge address such as `ws://127.0.0.1:8787/ws`: { "host", "port", "local" }.
## `local` is true only for ws:// (not wss://) and a host of this computer.
static func parse_address(url: String) -> Dictionary:
	var secure: bool = url.begins_with("wss://")
	var rest: String = url.trim_prefix("wss://").trim_prefix("ws://")
	var authority: String = rest.split("/")[0]
	var host: String = authority
	var port: int = 443 if secure else 80
	if authority.begins_with("["):
		var close: int = authority.find("]")
		host = authority.substr(1, close - 1) if close > 0 else authority
		var after: String = authority.substr(close + 1) if close > 0 else ""
		if after.begins_with(":") and after.substr(1).is_valid_int():
			port = int(after.substr(1))
	elif authority.count(":") == 1:
		var parts: PackedStringArray = authority.split(":")
		host = parts[0]
		if parts[1].is_valid_int():
			port = int(parts[1])
		else:
			port = -1
	var local: bool = not secure and host in ["127.0.0.1", "localhost", "::1"] and port >= 0 and port <= 65535
	return { "host": host, "port": port, "local": local }


## The file name of the bridge program on a system (`OS.get_name()` gives "Windows", "macOS", "Linux").
static func program_name(os_name: String) -> String:
	return PROGRAM + ".exe" if os_name == "Windows" else PROGRAM


## Where the program may be, in order. A configured path is the only candidate: it never falls back to another one.
static func candidate_paths(configured: String, exe_dir: String, path_env: String, os_name: String) -> PackedStringArray:
	if configured != "":
		return PackedStringArray([configured])
	var file_name: String = program_name(os_name)
	var found: PackedStringArray = [exe_dir.path_join(file_name)]
	if os_name == "macOS":
		# The app is `Name.app/Contents/MacOS/Name`. Look in the folder that holds the .app too.
		found.append(exe_dir.path_join("../../..").simplify_path().path_join(file_name))
	var separator: String = ";" if os_name == "Windows" else ":"
	for dir in path_env.split(separator, false):
		found.append(dir.path_join(file_name))
	return found


## The first candidate that is a file, or "".
static func find_program(candidates: PackedStringArray) -> String:
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""


## The loopback host of an address: "::1" for ::1, and "127.0.0.1" for the others (also for `localhost`).
static func loopback_host(address_host: String) -> String:
	return "::1" if address_host == "::1" else "127.0.0.1"


## The arguments of the program: only a loopback host, the port, and the end with the pipe.
static func serve_arguments(host: String, port: int) -> PackedStringArray:
	return PackedStringArray(["serve", "--host", host, "--port", str(port), "--exit-when-stdin-closes"])


## The address of `GET /health` for a loopback host.
static func health_url(host: String, port: int) -> String:
	return "http://[%s]:%d/health" % [host, port] if host.contains(":") else "http://%s:%d/health" % [host, port]


## A short text for one line of the program's error output ("error: could not listen on ...").
static func short_message(line: String) -> String:
	var text: String = line.strip_edges().trim_prefix("error: ")
	if text.length() > MAX_NOTE_CHARACTERS:
		text = text.substr(0, MAX_NOTE_CHARACTERS - 1) + "…"
	return "Bridge: " + text


# ---------------------------------------------------------------- the launcher

## Starts the work. `bridge_url` is the address that the client reads. `configured_path` may be "".
func start(bridge_url: String, configured_path: String) -> void:
	_configured_path = configured_path
	var address: Dictionary = parse_address(bridge_url)
	if not address["local"]:
		_fail("Bridge not started: its address is not on this computer")
		return
	_port = address["port"]
	_host = loopback_host(address["host"])
	state = State.CHECKING
	_begin_pending = true


## Asks `GET /health` of the address. It runs in the first frame, when the node is in the tree.
func _begin() -> void:
	_http = HTTPRequest.new()
	_http.timeout = HEALTH_TIMEOUT_SECONDS
	add_child(_http)
	_http.request_completed.connect(_on_health)
	if _http.request(health_url(_host, _port)) != OK:
		_spawn()


func _on_health(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY and parsed.get("ok", false) == true:
			state = State.USING_EXISTING # a bridge runs: use it, and never stop it
			return
	_spawn()


func _spawn() -> void:
	_program = find_program(candidate_paths(_configured_path, OS.get_executable_path().get_base_dir(), OS.get_environment("PATH"), OS.get_name()))
	if _program == "":
		var where: String = _configured_path if _configured_path != "" else PROGRAM
		_fail("Bridge program not found: %s" % where)
		return
	var info: Dictionary = OS.execute_with_pipe(_program, serve_arguments(_host, _port))
	if info.is_empty():
		_fail("Bridge program could not be started")
		return
	pid = int(info["pid"])
	# These references keep the pipe to the standard input of the program open. If they go, the program ends.
	_stdio = info["stdio"]
	_stderr = info["stderr"]
	state = State.STARTING
	_waited = 0.0
	_gone_for = -1.0
	_start_reader(_stdio, true)
	_start_reader(_stderr, false)


func _start_reader(file: FileAccess, is_output: bool) -> void:
	var thread := Thread.new()
	thread.start(_read_lines.bind(file, is_output))
	_threads.append(thread)


## Runs in a thread: reads every line until the pipe closes or the program is gone. The first line of the output says where the bridge
## listens. The rest of the output is thrown away, only read. The first lines of the error output are kept for the note.
func _read_lines(file: FileAccess, is_output: bool) -> void:
	while true:
		var line: String = file.get_line()
		if line == "":
			_mutex.lock()
			var finished: bool = _gone
			_mutex.unlock()
			if finished or file.eof_reached():
				break
			OS.delay_msec(5) # an empty line, or the end of the pipe that the program has not yet been seen to leave
			continue
		_mutex.lock()
		if is_output:
			if _first_line == "":
				_first_line = line
		elif _error_lines.size() < MAX_ERROR_LINES:
			_error_lines.append(line)
		_mutex.unlock()


func _process(delta: float) -> void:
	if _begin_pending:
		_begin_pending = false
		_begin()
		return
	match state:
		State.STARTING:
			_waited += delta
			_mutex.lock()
			var first: String = _first_line
			_mutex.unlock()
			if first.contains("listening on"):
				state = State.RUNNING
			elif not OS.is_process_running(pid):
				_gone_for = maxf(_gone_for, 0.0) + delta
				_mutex.lock()
				var lines: PackedStringArray = _error_lines.duplicate()
				_mutex.unlock()
				# The text of the error may still be on its way from the pipe: wait a little for it.
				if not lines.is_empty() or _gone_for >= EXIT_GRACE_SECONDS:
					_fail(short_message(lines[0]) if not lines.is_empty() else "Bridge program ended at once")
					_release(true)
			elif _waited >= START_TIMEOUT_SECONDS:
				stop()
				_fail("Bridge program did not start in %d seconds" % int(START_TIMEOUT_SECONDS))
		State.RUNNING:
			if not OS.is_process_running(pid):
				_fail("Bridge program ended")
				_release(true)


## Stops the bridge that this node started. It never touches one that the node did not start.
func stop() -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
		# Wait a moment until the system says that it is gone, so that the reader threads see the end of the pipes.
		var waited: int = 0
		while OS.is_process_running(pid) and waited < 1000:
			OS.delay_msec(10)
			waited += 10
	_release(true)


## Lets go of the pipes and waits for the reader threads. `gone` tells them that the program is gone, so they stop.
func _release(gone: bool = false) -> void:
	if gone:
		_mutex.lock()
		_gone = true
		_mutex.unlock()
	_stdio = null
	_stderr = null
	for thread in _threads:
		if thread.is_started():
			thread.wait_to_finish()
	_threads.clear()


func _exit_tree() -> void:
	if state == State.STARTING or state == State.RUNNING:
		stop()


func _fail(text: String) -> void:
	state = State.FAILED
	notes.append(text)
	note.emit(text)
