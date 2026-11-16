extends Node
## Reads the event stream of the bridge over a WebSocket.
##
## The client polls the socket once in each frame and reads at most MAX_EVENTS_PER_FRAME events.
## When the connection is not open, it tries again every RECONNECT_SECONDS.
## A try that does not finish in CONNECT_TIMEOUT_SECONDS is dropped, and the next try starts at once.
## (On Windows, a connect to a port with no listener takes about 30 seconds to fail.)
## The `hello` message that the bridge sends to a new connection is ignored.

const Event := preload("res://src/core/event.gd")

## `state` has one of these values.
enum State { CONNECTING, OPEN, WAITING }

const RECONNECT_SECONDS := 2.0
const CONNECT_TIMEOUT_SECONDS := 4.0
const MAX_EVENTS_PER_FRAME := 64

signal state_changed(state: State)
signal event_received(event: RefCounted)
## A message was not an event. `reason` says why.
signal message_rejected(reason: String)

var url: String = "ws://127.0.0.1:8787/ws"
var state: State = State.WAITING
## The most events that one frame read. The tests check that it stays at or under the cap.
var max_events_in_a_frame: int = 0
var events_received: int = 0
var connection_count: int = 0

var _peer: WebSocketPeer = null
var _wait_left: float = 0.0
var _connecting_for: float = 0.0


func _ready() -> void:
	start()


## Start (or restart) the connection to `url`.
func start() -> void:
	_peer = null
	_connect()


func _process(delta: float) -> void:
	step(delta)


## One frame of work. `_process` calls it. A test may call it too.
func step(delta: float) -> void:
	if _peer == null:
		_wait_left -= delta
		if _wait_left <= 0.0:
			_connect()
		return
	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			_connecting_for += delta
			if _connecting_for >= CONNECT_TIMEOUT_SECONDS:
				_peer.close()
				_connect()
		WebSocketPeer.STATE_OPEN:
			if state != State.OPEN:
				_set_state(State.OPEN)
			_read_available()
		WebSocketPeer.STATE_CLOSING:
			# The socket may still hold packets that arrived before the close.
			_read_available()
		WebSocketPeer.STATE_CLOSED:
			_read_available()
			_wait_for_retry()


func state_name() -> String:
	return State.keys()[state].to_lower()


func _connect() -> void:
	_connecting_for = 0.0
	var peer := WebSocketPeer.new()
	var error: Error = peer.connect_to_url(url)
	connection_count += 1
	if error != OK:
		# The address is not valid, or the system refused the socket. Try again later.
		_wait_for_retry()
		return
	_peer = peer
	_set_state(State.CONNECTING)


## Drop the socket and wait RECONNECT_SECONDS before the next try.
func _wait_for_retry() -> void:
	_peer = null
	_wait_left = RECONNECT_SECONDS
	_set_state(State.WAITING)


func _read_available() -> void:
	var count: int = 0
	while count < MAX_EVENTS_PER_FRAME and _peer.get_available_packet_count() > 0:
		var packet: PackedByteArray = _peer.get_packet()
		count += 1
		handle_message(packet.get_string_from_utf8())
	max_events_in_a_frame = maxi(max_events_in_a_frame, count)


## Handle one text message. Public so that a test can feed messages with no socket.
func handle_message(text: String) -> void:
	var data: Variant = Event.decode(text)
	if typeof(data) != TYPE_DICTIONARY:
		message_rejected.emit("not a JSON object")
		return
	var message: Dictionary = data
	if Event.is_hello(message):
		return
	var event: RefCounted = Event.from_dictionary(message)
	if event == null:
		message_rejected.emit(Event.problem_with(message))
		return
	events_received += 1
	event_received.emit(event)


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(state)
