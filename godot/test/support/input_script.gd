extends RefCounted
## Plays the inputs of a scene through the real input path (phase G-6): a key becomes an `InputEventKey`, a click becomes a mouse
## move and a left click at the place where the interface shows the thing, and a line of the follow menu becomes a click on the
## follow switch and the keys of the menu. The events go to the viewport with `push_input`, so they reach `LiveView`'s
## `_unhandled_key_input` and `_unhandled_input` as a real key or click does. Nothing calls the camera directly.
##
## The inputs are the entries of a timeline file: `{t, key}`, `{t, click: "tab"|"cell", arena}`, `{t, click: "page", page}`,
## `{t, toggle: kind}`, `{t, manual: true}` and `{t, pace: p}`.

const ArenaRules := preload("res://src/core/arena_rules.gd")
const BarLayout := preload("res://src/core/bar_layout.gd")

const KEYS := {
	"F": KEY_F, "Tab": KEY_TAB, "Esc": KEY_ESCAPE, "Left": KEY_LEFT, "Right": KEY_RIGHT, "N": KEY_N,
}

## What was pushed, as text, in order: "key Tab", "click tab B (137, 237)", ... A test can read it.
var pushed: Array[String] = []
## The inputs that could not be turned into an event (for example a tab that is not in the list). A test expects none.
var problems: Array[String] = []

var _view: Node
var _viewport: Viewport


func _init(view: Node) -> void:
	_view = view
	_viewport = view.get_viewport()
	_let_the_mouse_through(view.get_tree().root)


## The panel of GUT is a tree of controls that take the mouse before the unhandled stage, so a pushed click would never reach
## `_unhandled_input`. A real window has no such panel. The test makes the controls ignore the mouse.
func _let_the_mouse_through(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_let_the_mouse_through(child)


## Plays the scene for `seconds` of simulation time, one step at a time. The entries of `script` are pushed when the clock
## reaches their time. Returns the number of steps.
func play(script: Array, seconds: float) -> int:
	var next: int = 0
	var steps: int = int(seconds / _view.clock.STEP) + 1
	for _i in steps:
		while next < script.size() and float((script[next] as Dictionary)["t"]) <= _view.clock.now + 1e-9:
			push_entry(script[next] as Dictionary)
			next += 1
		_view.simulate(1)
	return steps


func push_entry(entry: Dictionary) -> void:
	if entry.has("key"):
		_close_menu()
		push_key(KEYS[str(entry["key"])])
	elif entry.get("click") == "tab":
		_close_menu()
		_click_rect(_tab_rect(str(entry["arena"])), "tab %s" % entry["arena"])
	elif entry.get("click") == "cell":
		_close_menu()
		_click_rect(_cell_rect(str(entry["arena"])), "cell %s" % entry["arena"])
	elif entry.get("click") == "page":
		_close_menu()
		_click_rect(_page_rect(int(entry["page"])), "page %d" % int(entry["page"]))
	elif entry.has("toggle"):
		_open_menu()
		push_key((KEY_1 + ArenaRules.KINDS.find(str(entry["toggle"]))) as Key)
	elif entry.has("manual"):
		_open_menu()
		push_key(KEY_0)
	elif entry.has("pace"):
		_open_menu()
		_set_pace(float(entry["pace"]))


func push_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		_viewport.push_input(event, true)
	pushed.append("key %s" % OS.get_keycode_string(keycode))


func move_mouse(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	_viewport.push_input(event, true)


func click_at(point: Vector2) -> void:
	move_mouse(point)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		_viewport.push_input(event, true)
	pushed.append("click (%d, %d)" % [int(point.x), int(point.y)])


func _click_rect(rect: Variant, what: String) -> void:
	if rect == null:
		problems.append("no %s on screen at %.2f s" % [what, _view.clock.now])
		return
	var r: Rect2i = rect
	var centre: Vector2 = Vector2(r.position) + Vector2(r.size) / 2.0
	click_at(centre)
	pushed.append(what)


func _ui() -> Dictionary:
	_view.interface.build(_view.director, _view.camera, _view.clock.now)
	return _view.interface.ui


func _tab_rect(letter: String) -> Variant:
	for tab: Dictionary in _ui()["tabs"]:
		if tab["letter"] == letter:
			return tab["rect"]
	return null


func _cell_rect(letter: String) -> Variant:
	var overview: Variant = _ui()["overview"]
	if overview == null:
		return null
	for cell: Dictionary in (overview as Dictionary)["cells"]:
		if cell["letter"] == letter and not cell["free"]:
			return cell["rect"]
	return null


func _page_rect(page: int) -> Variant:
	for item: Dictionary in (_ui()["pages"] as Dictionary)["items"]:
		if item["kind"] == "box" and int(item["page"]) == page:
			return item["rect"]
	return null


func _open_menu() -> void:
	if _view.interface.menu_open:
		return
	var follow: Dictionary = _ui()["follow"]
	_click_rect(follow["rect"], "follow switch")


func _close_menu() -> void:
	if _view.interface.menu_open:
		push_key(KEY_ESCAPE)


## Sets the pace with `[` and `]` in the open menu, from where it is to `target` moves a second.
func _set_pace(target: float) -> void:
	var window: float = float(_view.camera.o["pace_window"])
	var wanted: int = int(roundf(target * window))
	var level: int = int(roundf(float(_view.camera.pace) * window))
	var key: Key = KEY_BRACKETLEFT if wanted < level else KEY_BRACKETRIGHT
	for _i in absi(wanted - level):
		push_key(key)
