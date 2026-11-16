extends Node
## The gallery of the art: every picture of the atlas, page by page, and a line of text.
##
## Run it with: godot --path godot res://src/gallery.tscn
## Keys: left and right arrow (or Page Up and Page Down) change the page. The option `-- --page=N` starts on page N (0 is the first).
## The art code draws everything. This file only starts it and reads the keys.

const Atlas := preload("res://art/atlas.gd")
const GalleryArt := preload("res://art/gallery_art.gd")

var _gallery: Node2D


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#1b2236"))
	var started: int = Time.get_ticks_usec()
	Atlas.load_all()
	var elapsed_ms: float = (Time.get_ticks_usec() - started) / 1000.0
	_gallery = GalleryArt.new()
	_gallery.load_ms = elapsed_ms
	add_child(_gallery)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--page="):
			_gallery.show_page(int(arg.trim_prefix("--page=")))
	print("gallery: %d pages, sheets loaded in %.1f ms" % [_gallery.page_count(), elapsed_ms])


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_RIGHT or key.keycode == KEY_PAGEDOWN:
		_gallery.show_page(_gallery.page_index + 1)
	elif key.keycode == KEY_LEFT or key.keycode == KEY_PAGEUP:
		_gallery.show_page(_gallery.page_index - 1)
