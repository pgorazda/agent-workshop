extends RefCounted
## What the keys and the clicks of the person do. The hit tests are in `interface_model.gd`; this file turns a hit into a
## call of the camera, and a key of the open follow menu into a change of what pulls the camera. It holds no state. The camera
## queues each call with the time and applies it at its next step, as it applies the inputs of a timeline.
##
## The follow menu: 1 to 6 tick or untick a kind of pull, `[` and `]` lower and raise the
## pace, 0 is "manual only", and Esc or a click elsewhere closes it.

const ArenaRules := preload("res://src/core/arena_rules.gd")
const BarLayout := preload("res://src/core/bar_layout.gd")


## A key while the follow menu is open. Returns true when the menu used it (any other key goes on to its usual use).
static func menu_key(keycode: Key, camera: RefCounted, interface: RefCounted, now: float) -> bool:
	if keycode == KEY_ESCAPE:
		interface.menu_open = false
		return true
	if keycode >= KEY_1 and keycode <= KEY_6:
		camera.toggle(ArenaRules.KINDS[keycode - KEY_1], now)
		return true
	if keycode >= KEY_KP_1 and keycode <= KEY_KP_6:
		camera.toggle(ArenaRules.KINDS[keycode - KEY_KP_1], now)
		return true
	match keycode:
		KEY_0, KEY_KP_0:
			camera.manual_only(now)
			return true
		KEY_BRACKETLEFT:
			step_pace(camera, -1, now)
			return true
		KEY_BRACKETRIGHT:
			step_pace(camera, 1, now)
			return true
	return false


## Lowers (`direction` -1) or raises (1) the pace of the camera by one level: 1 to 10 moves in the pace window, then no limit.
static func step_pace(camera: RefCounted, direction: int, now: float) -> void:
	camera.set_pace(BarLayout.next_pace(camera.pace, float(camera.o["pace_window"]), direction), now)


## A left click that hit `hit` (see `InterfaceModel.hit`). Returns true when it did something.
static func click(hit: Dictionary, camera: RefCounted, interface: RefCounted, now: float) -> bool:
	match str(hit["kind"]):
		"close_menu":
			interface.menu_open = false
			return true
		"follow":
			if bool((interface.ui["follow"] as Dictionary).get("pill", false)):
				camera.press("F", now)
			else:
				interface.menu_open = not interface.menu_open
			return true
		"menu_line":
			match str(hit["line"]):
				"manual":
					camera.manual_only(now)
				"pace":
					step_pace(camera, int(hit["direction"]), now)
				_:
					camera.toggle(str(hit["line"]), now)
			return true
		"tab":
			camera.click_tab(str(hit["arena"]), now)
			return true
		"page", "page_arrow", "edge_arrow":
			camera.click_page(int(hit["page"]), now)
			return true
		"cell":
			camera.click_cell(str(hit["arena"]), now)
			return true
		"card", "penguin":
			camera.set_focus(str(hit["arena"]), int(hit["number"]), now)
			return true
	return false
