extends Control
## Phase G-0: a text view of the connection and of the events.
##
## The later phases replace this view with the workshop. The link to the bridge stays.

const Options := preload("res://src/core/options.gd")
const BridgeClient := preload("res://src/net/bridge_client.gd")

## The view keeps this many event lines. It shows the newest ones that fit on the screen.
const MAX_LINES := 200
const FONT_SIZE := 8

var _options: RefCounted
var _client: Node
var _lines: PackedStringArray = []
var _notes: PackedStringArray = []

@onready var _label: Label = $Text


func _ready() -> void:
	_options = Options.parse(OS.get_cmdline_user_args())
	_notes = _options.warnings
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_client = BridgeClient.new()
	_client.url = _options.bridge
	_client.state_changed.connect(_on_state_changed)
	_client.event_received.connect(_on_event)
	_client.message_rejected.connect(_on_rejected)
	add_child(_client)
	_refresh()


func _on_state_changed(_state: int) -> void:
	_emit_log("state %s" % _client.state_name())
	_refresh()


func _on_event(event: RefCounted) -> void:
	_lines.append(event.describe())
	if _lines.size() > MAX_LINES:
		_lines.remove_at(0)
	_emit_log("event %s" % event.describe())
	_refresh()


func _on_rejected(reason: String) -> void:
	_emit_log("rejected message: %s" % reason)


func _emit_log(text: String) -> void:
	if _options.log_events:
		print("[main] ", text)


func _refresh() -> void:
	var head: PackedStringArray = [
		"Agent Workshop - phase G-0 (text view)",
		"bridge: %s" % _options.bridge,
		"state: %s   events: %d" % [_client.state_name(), _client.events_received],
	]
	head.append_array(_notes)
	head.append("")
	var fit: int = maxi(1, int((size.y - 4.0) / _label.get_line_height()) - head.size() - 1)
	var shown: PackedStringArray = _lines.slice(maxi(0, _lines.size() - fit))
	_label.text = "\n".join(head) + "\n" + "\n".join(shown)
