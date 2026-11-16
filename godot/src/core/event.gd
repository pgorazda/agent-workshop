extends RefCounted
## One Agent Workshop event, schema v1 (see schema/event.schema.json in the repository root).
##
## The client reads only schema fields. It picks a station by `category`, never by tool name.
## An event type that is not in KNOWN_TYPES is accepted: it counts as generic work.

## The tool categories. A test compares this list with the enum in the schema.
const CATEGORIES: Array[String] = [
	"read",
	"search",
	"write",
	"exec",
	"web",
	"delegate",
	"think",
	"ask_permission",
	"other",
]

## The event types that the schema names. Other types are valid.
const KNOWN_TYPES: Array[String] = [
	"session_start",
	"tool_start",
	"tool_end",
	"subagent_start",
	"subagent_end",
	"thinking",
	"waiting_permission",
	"error",
	"done",
]

const SCHEMA_VERSION := 1

var framework: String = ""
var session: String = ""
var agent: String = ""
var type: String = ""
## Epoch milliseconds.
var ts: float = 0.0
## One of CATEGORIES, or "" when the event has none. An unknown category becomes "other".
var category: String = ""
var tool: String = ""
var target: String = ""
## `null` when the event has no outcome. Otherwise a bool.
var ok: Variant = null
var error: String = ""
var id: String = ""
var message: String = ""
## Cost in USD, or -1.0 when it is not known.
var cost: float = -1.0
## The decoded message, as the bridge sent it.
var raw: Dictionary = { }


## Parse one JSON text. Returns `null` when the text is not a valid event.
static func parse(text: String) -> RefCounted:
	var data: Variant = decode(text)
	if typeof(data) != TYPE_DICTIONARY:
		return null
	return from_dictionary(data as Dictionary)


## Decode a JSON text. Returns `null` when the text is not JSON. It prints no engine error.
static func decode(text: String) -> Variant:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


## Build an event from a decoded message. Returns `null` when the message is not a valid event.
static func from_dictionary(data: Dictionary) -> RefCounted:
	if not problem_with(data).is_empty():
		return null
	var event: RefCounted = new()
	event.raw = data
	event.framework = str(data["framework"])
	event.session = str(data["session"])
	event.agent = str(data["agent"])
	event.type = str(data["type"])
	event.ts = float(data["ts"])
	if data.has("category"):
		var wanted: String = str(data["category"])
		event.category = wanted if CATEGORIES.has(wanted) else "other"
	event.tool = _text(data, "tool")
	event.target = _text(data, "target")
	event.error = _text(data, "error")
	event.id = _text(data, "id")
	event.message = _text(data, "message")
	if typeof(data.get("ok")) == TYPE_BOOL:
		event.ok = data["ok"]
	if _is_number(data.get("cost")):
		event.cost = float(data["cost"])
	return event


## Why a message is not a valid event. Returns "" when it is valid.
static func problem_with(data: Dictionary) -> String:
	if not _is_number(data.get("v")) or int(data["v"]) != SCHEMA_VERSION:
		return "unsupported schema version"
	for key: String in ["framework", "session", "agent", "type"]:
		var value: Variant = data.get(key)
		if typeof(value) != TYPE_STRING or (value as String).is_empty():
			return "missing or empty field: %s" % key
	if not _is_number(data.get("ts")):
		return "missing or bad field: ts"
	return ""


## True for the greeting that the bridge sends to each new connection. It is not an event.
static func is_hello(data: Dictionary) -> bool:
	return data.get("type") == "hello"


## True when the event type is one that the schema names.
func is_known_type() -> bool:
	return KNOWN_TYPES.has(type)


## True for an event type that the client does not know. It shows as generic work.
func is_generic_work() -> bool:
	return not is_known_type()


## One line of text for a log or a text view.
func describe() -> String:
	var parts: PackedStringArray = ["%s/%s/%s" % [framework, session, agent], type]
	if category != "":
		parts.append(category)
	if tool != "":
		parts.append(tool)
	if target != "":
		parts.append(target)
	if ok != null:
		parts.append("ok" if ok else "failed")
	return " ".join(parts)


static func _text(data: Dictionary, key: String) -> String:
	var value: Variant = data.get(key)
	return value if typeof(value) == TYPE_STRING else ""


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
