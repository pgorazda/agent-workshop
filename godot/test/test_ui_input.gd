extends GutTest
## What a key of the open follow menu and a click do to the camera. The calls are queued on the camera with the time.

const UiInput := preload("res://src/view/ui_input.gd")
const InterfaceModel := preload("res://src/view/interface_model.gd")
const Camera := preload("res://src/core/camera.gd")

var camera: Camera
var interface: InterfaceModel


func before_each() -> void:
	camera = Camera.new()
	camera.arena_opened("A", 0.0)
	camera.arena_opened("B", 0.0)
	interface = InterfaceModel.new()
	interface.menu_open = true


## Runs the camera two steps so that it applies the inputs queued at time 0.
func _apply() -> void:
	camera.advance(0.1)


func test_the_keys_one_to_six_tick_and_untick_the_kinds() -> void:
	assert_true(UiInput.menu_key(KEY_2, camera, interface, 0.0), "failures")
	assert_true(UiInput.menu_key(KEY_1, camera, interface, 0.0), "approvals")
	_apply()
	assert_true(camera.follow["fail"], "failures were off, now on")
	assert_false(camera.follow["approval"], "approvals were on, now off")
	assert_true(UiInput.menu_key(KEY_6, camera, interface, 0.1))
	camera.advance(0.2)
	assert_false(camera.follow["activity"])


func test_zero_is_manual_only_and_keeps_the_ticks() -> void:
	UiInput.menu_key(KEY_0, camera, interface, 0.0)
	_apply()
	assert_eq(camera.mode, "MANUAL")
	assert_true(camera.follow["approval"], "the ticks stay")


func test_the_brackets_lower_and_raise_the_pace() -> void:
	assert_almost_eq(camera.pace, 0.3, 1e-9)
	UiInput.menu_key(KEY_BRACKETLEFT, camera, interface, 0.0)
	_apply()
	assert_almost_eq(camera.pace, 0.2, 1e-9)
	UiInput.menu_key(KEY_BRACKETRIGHT, camera, interface, 0.2)
	camera.advance(0.3)
	assert_almost_eq(camera.pace, 0.3, 1e-9)
	UiInput.menu_key(KEY_BRACKETRIGHT, camera, interface, 0.4)
	camera.advance(0.5)
	assert_almost_eq(camera.pace, 0.4, 1e-9)


func test_escape_closes_the_menu_and_another_key_is_not_used() -> void:
	assert_false(UiInput.menu_key(KEY_F, camera, interface, 0.0), "F is not a key of the menu")
	assert_false(UiInput.menu_key(KEY_N, camera, interface, 0.0))
	assert_true(interface.menu_open)
	assert_true(UiInput.menu_key(KEY_ESCAPE, camera, interface, 0.0))
	assert_false(interface.menu_open)


func test_a_click_on_a_line_of_the_menu_ticks_it_and_a_click_elsewhere_closes_it() -> void:
	assert_true(UiInput.click({ "kind": "menu_line", "index": 3, "line": "join", "direction": 0 }, camera, interface, 0.0))
	assert_true(UiInput.click({ "kind": "menu_line", "index": 7, "line": "manual", "direction": 0 }, camera, interface, 0.0))
	_apply()
	assert_true(camera.follow["join"])
	assert_eq(camera.mode, "MANUAL")
	assert_true(UiInput.click({ "kind": "close_menu" }, camera, interface, 0.1))
	assert_false(interface.menu_open)


func test_a_click_on_the_pace_arrows_changes_the_pace_by_one_level() -> void:
	UiInput.click({ "kind": "menu_line", "index": 6, "line": "pace", "direction": 1 }, camera, interface, 0.0)
	_apply()
	assert_almost_eq(camera.pace, 0.4, 1e-9)


func test_a_click_on_a_tab_a_page_or_a_cell_calls_the_camera() -> void:
	assert_true(UiInput.click({ "kind": "tab", "arena": "B" }, camera, interface, 0.0))
	_apply()
	assert_eq(camera.arena_shown(), "B")
	assert_eq(camera.mode, "MANUAL", "choosing an arena takes over")
	assert_eq(camera.log.size(), 1)
	assert_eq(camera.log[0]["why"], "click")


func test_a_click_on_a_card_or_a_penguin_sets_the_focus_in_both_modes() -> void:
	UiInput.click({ "kind": "card", "arena": "A", "number": 7 }, camera, interface, 0.0)
	assert_eq(camera.focus_of("A"), 7)
	camera.mode = "MANUAL"
	UiInput.click({ "kind": "penguin", "arena": "A", "number": 9 }, camera, interface, 1.0)
	assert_eq(camera.focus_of("A"), 9)


func test_a_click_on_nothing_does_nothing() -> void:
	assert_false(UiInput.click({ "kind": "none" }, camera, interface, 0.0))
	assert_false(UiInput.click({ "kind": "menu" }, camera, interface, 0.0))
