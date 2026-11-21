extends SceneTree
## A headless program for tools/bridge-link.test.mjs. It runs the real bridge client and prints one line
## for each thing that happens, so that the Node test can read the lines:
##
##   STATE <connecting|open|waiting>
##   EVENT <id> <type>
##   MAXFRAME <most events that one frame read>
##   TRY <number of connection tries so far>
##
## Start it with:  godot --headless --path godot -s res://tools/link_probe.gd -- --bridge=ws://127.0.0.1:PORT/ws

const Options := preload("res://src/core/options.gd")
const BridgeClient := preload("res://src/net/bridge_client.gd")

var _client: Node
var _last_max: int = 0
var _last_tries: int = 0


func _initialize() -> void:
	Engine.max_fps = 60
	var options: RefCounted = Options.parse(OS.get_cmdline_user_args())
	_client = BridgeClient.new()
	_client.url = options.bridge
	_client.state_changed.connect(_on_state_changed)
	_client.event_received.connect(_on_event)
	root.add_child(_client)


func _process(_delta: float) -> bool:
	if _client.max_events_in_a_frame != _last_max:
		_last_max = _client.max_events_in_a_frame
		print("MAXFRAME %d" % _last_max)
	if _client.connection_count != _last_tries:
		_last_tries = _client.connection_count
		print("TRY %d" % _last_tries)
	return false


func _on_state_changed(_state: int) -> void:
	print("STATE %s" % _client.state_name())


func _on_event(event: RefCounted) -> void:
	print("EVENT %s %s" % [event.id, event.type])
