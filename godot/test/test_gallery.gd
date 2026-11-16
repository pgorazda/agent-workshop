extends GutTest
## The gallery shows every picture of the atlas on some page (the exit check of phase G-2 asks for every pose).

const GalleryArt := preload("res://art/gallery_art.gd")
const Data := preload("res://art/atlas_data.gd")


func test_every_picture_that_is_not_a_glyph_or_a_room_is_on_a_page() -> void:
	var shown: Dictionary = {}
	for page: Dictionary in GalleryArt.build_pages():
		if page["kind"] == "flow":
			for item: Dictionary in page["items"]:
				shown[item["name"]] = true
	var missing: Array[String] = []
	for picture: String in Data.PICTURES:
		if picture.begins_with("glyph/") or picture.begins_with("room/"):
			continue
		if not shown.has(picture):
			missing.append(picture)
	assert_eq(missing, [], "pictures that no page shows")


func test_there_is_a_page_for_every_font_and_every_room() -> void:
	var fonts: Dictionary = {}
	var rugs: Dictionary = {}
	for page: Dictionary in GalleryArt.build_pages():
		if page["kind"] == "glyphs":
			fonts[page["font"]] = true
		if page["kind"] == "room":
			rugs[page["rug"]] = true
	for font: String in Data.GLYPH_FONTS:
		assert_true(fonts.has(font), "a page for %s" % font)
	for rug: Dictionary in Data.RUGS:
		assert_true(rugs.has(rug["name"]), "a page for the room %s" % rug["name"])


func test_pictures_stay_on_the_screen() -> void:
	for page: Dictionary in GalleryArt.build_pages():
		if page["kind"] != "flow" and page["kind"] != "mirror":
			continue
		for item: Dictionary in page["items"]:
			var entry: Array = Data.PICTURES[item["name"]]
			var size := Vector2i(int(entry[3]), int(entry[4]))
			var fits: bool = item["x"] + size.x <= GalleryArt.SCREEN.x and item["y"] + size.y <= GalleryArt.SCREEN.y - GalleryArt.CAPTION_HEIGHT
			assert_true(fits, "%s fits on its page" % item["name"])


func test_the_gallery_node_changes_pages() -> void:
	var gallery: Node2D = GalleryArt.new()
	add_child_autofree(gallery)
	assert_gt(gallery.page_count(), 10)
	gallery.show_page(-1)
	assert_eq(gallery.page_index, gallery.page_count() - 1, "a page before the first wraps to the last")
	gallery.show_page(gallery.page_count())
	assert_eq(gallery.page_index, 0)
