extends GutTest
## The text view. It must show the connection state and list the events.

const Event := preload("res://src/core/event.gd")

var _main: Control


func before_each() -> void:
	var scene: PackedScene = load("res://src/main.tscn")
	_main = scene.instantiate()
	add_child_autofree(_main)


func test_shows_the_bridge_address_and_a_state() -> void:
	var text: String = _main.get_node("Text").text
	assert_string_contains(text, "ws://127.0.0.1:8787/ws")
	assert_string_contains(text, "state: ")


func test_lists_the_events_it_gets() -> void:
	var event: RefCounted = Event.parse('{"v":1,"framework":"x","session":"s","agent":"main","type":"tool_start","tool":"Read","category":"read","target":"a.py","ts":5}')
	_main._on_event(event)
	var text: String = _main.get_node("Text").text
	assert_string_contains(text, "x/s/main tool_start read Read a.py")
