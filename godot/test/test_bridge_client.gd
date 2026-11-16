extends GutTest
## The message handling of the bridge client. The socket itself is tested by tools/bridge-link.test.mjs.

const BridgeClient := preload("res://src/net/bridge_client.gd")

var _client: Node
var _events: Array = []
var _rejected: Array[String] = []


func before_each() -> void:
	_client = autofree(BridgeClient.new())
	_events = []
	_rejected = []
	_client.event_received.connect(func(event: RefCounted) -> void: _events.append(event))
	_client.message_rejected.connect(func(reason: String) -> void: _rejected.append(reason))


func test_hello_message_is_ignored() -> void:
	_client.handle_message('{"v":1,"type":"hello"}')
	assert_eq(_events.size(), 0)
	assert_eq(_rejected.size(), 0, "hello is not an error")
	assert_eq(_client.events_received, 0)


func test_valid_event_is_emitted() -> void:
	_client.handle_message('{"v":1,"framework":"x","session":"s","agent":"main","type":"tool_start","tool":"T","category":"read","ts":5}')
	assert_eq(_events.size(), 1)
	assert_eq(_events[0].category, "read")
	assert_eq(_client.events_received, 1)


func test_events_keep_their_order() -> void:
	for i in 5:
		_client.handle_message('{"v":1,"framework":"x","session":"s","agent":"main","type":"thinking","ts":%d}' % i)
	var stamps: Array[int] = []
	for event: RefCounted in _events:
		stamps.append(int(event.ts))
	assert_eq(stamps, [0, 1, 2, 3, 4] as Array[int])


func test_bad_messages_are_rejected_not_emitted() -> void:
	_client.handle_message("not json")
	_client.handle_message('{"v":1,"type":"done"}')
	assert_eq(_events.size(), 0)
	assert_eq(_rejected.size(), 2)


func test_unknown_event_type_is_emitted_as_generic_work() -> void:
	_client.handle_message('{"v":1,"framework":"x","session":"s","agent":"main","type":"juggling","ts":5}')
	assert_eq(_events.size(), 1)
	assert_true(_events[0].is_generic_work())


func test_constants_follow_the_plan() -> void:
	assert_eq(BridgeClient.RECONNECT_SECONDS, 2.0)
	assert_eq(BridgeClient.MAX_EVENTS_PER_FRAME, 64)




func test_a_client_that_lost_its_connection_waits_before_it_tries_again() -> void:
	_client._wait_for_retry()
	assert_eq(_client.state, BridgeClient.State.WAITING)
	assert_eq(_client.connection_count, 0)
	_client.step(1.0)
	assert_eq(_client.connection_count, 0, "no new try before 2 s")
	_client.step(1.1)
	assert_eq(_client.connection_count, 1, "a new try after 2 s")


func test_a_try_that_does_not_finish_is_dropped_and_started_again() -> void:
	# A server that listens but never answers keeps the try open on every system.
	var server: TCPServer = TCPServer.new()
	assert_eq(server.listen(0, "127.0.0.1"), OK)
	_client.url = "ws://127.0.0.1:%d/ws" % server.get_local_port()
	_client.start()
	assert_eq(_client.state, BridgeClient.State.CONNECTING)
	assert_eq(_client.connection_count, 1)
	_client.step(BridgeClient.CONNECT_TIMEOUT_SECONDS - 0.1)
	assert_eq(_client.connection_count, 1, "no new try before the timeout")
	_client.step(0.2)
	assert_eq(_client.connection_count, 2, "a new try after the timeout")
	assert_eq(_client.state, BridgeClient.State.CONNECTING)
	server.stop()
