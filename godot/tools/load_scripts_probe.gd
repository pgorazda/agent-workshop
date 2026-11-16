extends SceneTree
## Times the loading of the scripts of the client (phase G-6, start-up). Run it headless:
##   godot --headless --path godot -s res://tools/load_scripts_probe.gd
## It loads the scripts that the main scene needs, one after the other, leaves first, and prints the milliseconds of each load
## (a script that another one needs is loaded with it, so the first user pays), and then the total for the main scene.

const LEAVES: Array[String] = [
	"res://art/atlas_data.gd", "res://art/atlas.gd", "res://art/draw_kit.gd", "res://art/text_art.gd", "res://art/ui_kit.gd",
	"res://src/core/event.gd", "res://src/core/rng.gd", "res://src/core/stations.gd", "res://src/core/arena_rules.gd",
	"res://src/core/spots.gd", "res://src/core/effects.gd", "res://src/core/world.gd", "res://src/core/log_model.gd",
	"res://src/core/penguin_actor.gd", "res://src/core/camera.gd", "res://src/core/director.gd", "res://art/effects_art.gd",
	"res://art/room_art.gd", "res://art/ribbon_art.gd", "res://art/crowd_art.gd", "res://art/room_stage_art.gd",
	"res://art/world_art.gd", "res://art/bar_art.gd", "res://art/overview_art.gd", "res://art/status_art.gd",
	"res://src/view/arena_view.gd", "res://src/view/interface_model.gd", "res://src/view/live_view.gd",
]


func _initialize() -> void:
	var rows: Array[String] = []
	var total: float = 0.0
	for path in LEAVES:
		var begin: int = Time.get_ticks_usec()
		var loaded: Variant = load(path)
		var ms: float = float(Time.get_ticks_usec() - begin) / 1000.0
		total += ms
		rows.append("%8.1f ms  %s%s" % [ms, path, "" if loaded != null else "  (failed)"])
	for row in rows:
		print(row)
	print("%8.1f ms  total" % total)
	var scene_begin: int = Time.get_ticks_usec()
	load("res://src/live.tscn")
	print("%8.1f ms  live.tscn after all of them" % (float(Time.get_ticks_usec() - scene_begin) / 1000.0))
	quit()
