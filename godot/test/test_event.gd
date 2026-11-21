extends GutTest
## Parsing of schema v1 events. The fixtures in test/fixtures/ are the example sessions of
## schema/examples/ after the bridge adapters mapped them (made by `cargo run --example fixtures` in bridge/).

const Event := preload("res://src/core/event.gd")

const FIXTURE_NAMES: Array[String] = ["claude-code", "hermes", "opencode", "pi"]


func _fixture_lines(example: String) -> PackedStringArray:
	var path: String = "res://test/fixtures/%s.events.jsonl" % example
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "fixture exists: %s" % path)
	if file == null:
		return PackedStringArray()
	var lines: PackedStringArray = []
	for line in file.get_as_text().split("\n"):
		if not line.strip_edges().is_empty():
			lines.append(line)
	return lines


func test_every_line_of_every_example_parses() -> void:
	for example in FIXTURE_NAMES:
		var lines: PackedStringArray = _fixture_lines(example)
		assert_gt(lines.size(), 10, "%s has events" % example)
		for line in lines:
			var event: RefCounted = Event.parse(line)
			assert_not_null(event, "%s: %s" % [example, line])


func test_parsed_events_keep_their_order_and_ids() -> void:
	var lines: PackedStringArray = _fixture_lines("claude-code")
	var types: Array[String] = []
	for line in lines:
		var event: RefCounted = Event.parse(line)
		types.append(event.type)
	assert_eq(types[0], "thinking")
	assert_eq(types[2], "tool_start")
	assert_eq(types[types.size() - 1], "done")
	assert_eq(types.count("tool_start"), types.count("tool_end"), "each tool_start has a tool_end")


func test_tool_start_fields() -> void:
	var event: RefCounted = Event.parse(_fixture_lines("claude-code")[2])
	assert_eq(event.framework, "claude-code")
	assert_eq(event.session, "demo-1")
	assert_eq(event.agent, "main")
	assert_eq(event.type, "tool_start")
	assert_eq(event.category, "search")
	assert_eq(event.tool, "Grep")
	assert_eq(event.target, "def test_")
	assert_eq(event.id, "toolu_1")
	assert_eq(event.ok, null, "a tool_start has no outcome")
	assert_true(event.is_known_type())


func test_tool_end_outcome_is_a_bool() -> void:
	var failed: int = 0
	var passed: int = 0
	for example in FIXTURE_NAMES:
		for line in _fixture_lines(example):
			var event: RefCounted = Event.parse(line)
			if event.type != "tool_end":
				continue
			assert_typeof(event.ok, TYPE_BOOL)
			if event.ok:
				passed += 1
			else:
				failed += 1
	assert_gt(passed, 0)
	assert_gt(failed, 0, "the examples hold failed tools")


func test_all_categories_of_the_examples_are_known() -> void:
	for example in FIXTURE_NAMES:
		for line in _fixture_lines(example):
			var event: RefCounted = Event.parse(line)
			if event.type == "tool_start":
				assert_true(Event.CATEGORIES.has(event.category), "%s: %s" % [example, event.category])


func test_unknown_event_type_is_generic_work() -> void:
	var event: RefCounted = Event.parse('{"v":1,"framework":"x","session":"s","agent":"main","type":"juggling","ts":5}')
	assert_not_null(event, "an unknown type is accepted")
	assert_false(event.is_known_type())
	assert_true(event.is_generic_work())
	assert_eq(event.category, "")


func test_unknown_category_becomes_other() -> void:
	var text: String = '{"v":1,"framework":"x","session":"s","agent":"main","type":"tool_start","tool":"T","category":"teleport","ts":5}'
	var event: RefCounted = Event.parse(text)
	assert_not_null(event)
	assert_eq(event.category, "other")


func test_extra_fields_are_allowed() -> void:
	var event: RefCounted = Event.parse('{"v":1,"framework":"x","session":"s","agent":"a","type":"done","ts":5,"future":[1,2]}')
	assert_not_null(event)
	assert_true(event.raw.has("future"))


func test_cost_and_message() -> void:
	var event: RefCounted = Event.parse('{"v":1,"framework":"x","session":"s","agent":"a","type":"done","ts":5,"cost":0.25,"message":"hi"}')
	assert_almost_eq(event.cost, 0.25, 0.0001)
	assert_eq(event.message, "hi")
	var plain: RefCounted = Event.parse('{"v":1,"framework":"x","session":"s","agent":"a","type":"done","ts":5}')
	assert_lt(plain.cost, 0.0, "no cost is -1")


func test_timestamp_keeps_milliseconds() -> void:
	var event: RefCounted = Event.parse('{"v":1,"framework":"x","session":"s","agent":"a","type":"done","ts":1767261600123}')
	assert_eq(int(event.ts), 1767261600123)


func test_rejects_bad_messages() -> void:
	var bad: Array[String] = [
		"not json",
		"[]",
		"42",
		'{"v":2,"framework":"x","session":"s","agent":"a","type":"done","ts":5}',
		'{"framework":"x","session":"s","agent":"a","type":"done","ts":5}',
		'{"v":1,"session":"s","agent":"a","type":"done","ts":5}',
		'{"v":1,"framework":"","session":"s","agent":"a","type":"done","ts":5}',
		'{"v":1,"framework":"x","session":"s","agent":"a","type":"done"}',
		'{"v":1,"framework":"x","session":"s","agent":"a","type":"done","ts":"now"}',
		'{"v":1,"framework":"x","session":"s","agent":7,"type":"done","ts":5}',
	]
	for text in bad:
		assert_null(Event.parse(text), text)


func test_problem_with_names_the_field() -> void:
	var data: Dictionary = { "v": 1, "framework": "x", "session": "s", "type": "done", "ts": 5 }
	assert_eq(Event.problem_with(data), "missing or empty field: agent")
	data["agent"] = "a"
	assert_eq(Event.problem_with(data), "")


func test_hello_is_not_an_event() -> void:
	var hello: Dictionary = { "v": 1, "type": "hello" }
	assert_true(Event.is_hello(hello))
	assert_null(Event.from_dictionary(hello))


func test_describe_is_one_line() -> void:
	var event: RefCounted = Event.parse(_fixture_lines("claude-code")[2])
	assert_eq(event.describe(), "claude-code/demo-1/main tool_start search Grep def test_")
