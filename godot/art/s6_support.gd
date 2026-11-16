# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# Helper of spike S-6 (godot/spikes/s6/). The license check keeps drawing and texture-making calls inside art/, so
# the two things that the spike needs live here:
#   1. a copy of an atlas sheet with mipmaps (the imported sheets have none), made at run time;
#   2. a node that draws a room and its sign (RoomArt draws on a CanvasItem), with a choice of the room texture.
# Delete this file with the spike if phase G-5 does not use it.
extends Node2D

const Atlas := preload("res://art/atlas.gd")
const RoomArt := preload("res://art/room_art.gd")

static var _mip_sheets: Dictionary = {}

## The rug colour of the room ("red", "cobalt", ...).
var rug: String = "red"
## The arena letter. Empty is the sign of the single room.
var letter: String = ""
## True: draw the room from a copy of its texture that has mipmaps. False: draw the imported texture.
var use_mipmaps: bool = false


## The texture of a sheet. With `mipmaps` it is a copy with a full mipmap chain (made once for each sheet).
static func sheet_texture(sheet: int, mipmaps: bool) -> Texture2D:
	if not mipmaps:
		return Atlas.texture(sheet)
	if not _mip_sheets.has(sheet):
		var image: Image = Atlas.texture(sheet).get_image()
		image.generate_mipmaps()
		_mip_sheets[sheet] = ImageTexture.create_from_image(image)
	return _mip_sheets[sheet] as Texture2D


func _draw() -> void:
	var picture: String = RoomArt.picture_name(rug)
	if use_mipmaps:
		var rect: Rect2i = Atlas.rect_of(picture)
		draw_texture_rect_region(sheet_texture(Atlas.sheet_of(picture), true), Rect2(Vector2.ZERO, Vector2(rect.size)), Rect2(rect))
	else:
		Atlas.draw(self, picture, Vector2.ZERO)
	RoomArt.draw_sign(self, rug, letter)
