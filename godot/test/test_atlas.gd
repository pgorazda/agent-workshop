extends GutTest
## The image files and the atlas data.
##
## The pictures come from the art code of the mockup, so they match it by construction. These tests check the files and
## how they are used: the hashes in MANIFEST.txt, the rectangles of atlas_data.gd, and that every picture that the
## variant table lists exists. `test/fixtures/art_variants.json` is the table, written by `tools/render-art.mjs`.

const Atlas := preload("res://art/atlas.gd")
const Data := preload("res://art/atlas_data.gd")
const Golden := preload("res://test/support/golden.gd")

const IMAGES_DIR := "res://art/images"
const MANIFEST := "res://art/MANIFEST.txt"
const FIXTURE := "res://test/fixtures/art_variants.json"
## Loading all sheets must take less than this. It is a very generous limit: the real time is a few tens of milliseconds.
const LOAD_LIMIT_MS := 2000.0

var _images: Dictionary = {}


func _fixture() -> Dictionary:
	var data: Variant = Golden.load_json(FIXTURE)
	assert_typeof(data, TYPE_DICTIONARY, "test/fixtures/art_variants.json is there (run tools/render-art.mjs)")
	return data if typeof(data) == TYPE_DICTIONARY else {}


func _image(sheet: int) -> Image:
	if not _images.has(sheet):
		_images[sheet] = Image.load_from_file(ProjectSettings.globalize_path(Data.SHEETS[sheet]))
	return _images[sheet]


# ---------------------------------------------------------------- the files

func test_every_sheet_file_exists_and_has_a_size() -> void:
	for sheet in Data.SHEETS.size():
		var path: String = Data.SHEETS[sheet]
		assert_true(FileAccess.file_exists(path), "%s exists" % path)
		var image: Image = _image(sheet)
		assert_not_null(image, "%s loads" % path)
		if image != null:
			assert_gt(image.get_width() * image.get_height(), 0, "%s is not empty" % path)


func test_every_png_matches_its_hash_in_the_manifest() -> void:
	var listed: Dictionary = _manifest()
	assert_gt(listed.size(), 0, "the manifest lists files")
	var files: Array[String] = []
	var dir: DirAccess = DirAccess.open(IMAGES_DIR)
	for file in dir.get_files():
		if file.ends_with(".png"):
			files.append(file)
	assert_gt(files.size(), 0, "there are PNG files")
	for file in files:
		var key: String = "images/%s" % file
		assert_true(listed.has(key), "%s is in the manifest" % key)
		if listed.has(key):
			assert_eq(FileAccess.get_sha256("%s/%s" % [IMAGES_DIR, file]), listed[key], "the hash of %s" % key)
	for key: String in listed:
		if key.begins_with("images/"):
			assert_true(files.has(key.trim_prefix("images/")), "%s: the file is there" % key)


func _manifest() -> Dictionary:
	var listed: Dictionary = {}
	var file: FileAccess = FileAccess.open(MANIFEST, FileAccess.READ)
	assert_not_null(file, "MANIFEST.txt opens")
	if file == null:
		return listed
	for line in file.get_as_text().split("\n"):
		if line.length() > 66 and line.substr(64, 2) == "  ":
			listed[line.substr(66)] = line.substr(0, 64)
	return listed


func test_the_sheets_use_the_expected_import_settings() -> void:
	# nearest filtering is the project default; the import files say: lossless; only the rooms have mipmaps (spike S-6: a
	# room scaled down in a fly or in the overview needs trilinear filtering, and the sheets of sprites do not)
	assert_eq(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter"), 0, "the default texture filter is nearest")
	var dir: DirAccess = DirAccess.open(IMAGES_DIR)
	var count: int = 0
	for file in dir.get_files():
		if not file.ends_with(".png"):
			continue
		count += 1
		assert_true(FileAccess.file_exists("%s/%s.import" % [IMAGES_DIR, file]), "%s has an .import file" % file)
		var config := ConfigFile.new()
		assert_eq(config.load("%s/%s.import" % [IMAGES_DIR, file]), OK, "%s.import loads" % file)
		assert_eq(config.get_value("params", "compress/mode"), 0, "%s: lossless, no compression" % file)
		var wants_mipmaps: bool = file.begins_with("room_")
		assert_eq(config.get_value("params", "mipmaps/generate"), wants_mipmaps, "%s: mipmaps only for the rooms" % file)
		assert_eq(config.get_value("remap", "type"), "CompressedTexture2D", "%s is imported as a texture" % file)
	assert_gt(count, 0)


# ---------------------------------------------------------------- the rectangles

func test_each_rectangle_lies_inside_its_png() -> void:
	for picture: String in Data.PICTURES:
		var entry: Array = Data.PICTURES[picture]
		var sheet: int = int(entry[0])
		assert_true(sheet >= 0 and sheet < Data.SHEETS.size(), "%s: the sheet index" % picture)
		var image: Image = _image(sheet)
		var rect := Rect2i(int(entry[1]), int(entry[2]), int(entry[3]), int(entry[4]))
		var inside: bool = rect.size.x > 0 and rect.size.y > 0 and rect.position.x >= 0 and rect.position.y >= 0 \
			and rect.end.x <= image.get_width() and rect.end.y <= image.get_height()
		assert_true(inside, "%s: %s lies inside the %dx%d sheet" % [picture, rect, image.get_width(), image.get_height()])


func test_no_two_rectangles_overlap() -> void:
	var by_sheet: Dictionary = {}
	for picture: String in Data.PICTURES:
		var entry: Array = Data.PICTURES[picture]
		var sheet: int = int(entry[0])
		if not by_sheet.has(sheet):
			by_sheet[sheet] = []
		(by_sheet[sheet] as Array).append([picture, Rect2i(int(entry[1]), int(entry[2]), int(entry[3]), int(entry[4]))])
	var overlaps: Array[String] = []
	for sheet: int in by_sheet:
		var list: Array = by_sheet[sheet]
		for i in list.size():
			for j in range(i + 1, list.size()):
				if (list[i][1] as Rect2i).intersects(list[j][1]):
					overlaps.append("%s and %s" % [list[i][0], list[j][0]])
	assert_eq(overlaps, [], "pictures that overlap")


func test_every_picture_has_ink_but_the_space_glyphs() -> void:
	var empty: Array[String] = []
	for picture: String in Data.PICTURES:
		var entry: Array = Data.PICTURES[picture]
		var image: Image = _image(int(entry[0]))
		var region: Image = image.get_region(Rect2i(int(entry[1]), int(entry[2]), int(entry[3]), int(entry[4])))
		if region.get_used_rect().size == Vector2i.ZERO:
			empty.append(picture)
	var spaces: Array[String] = []
	for font: String in Data.GLYPH_FONTS:
		spaces.append("glyph/%s/U+0020" % font)
	assert_eq(empty, spaces, "only the glyph of a space is empty")


# ---------------------------------------------------------------- the variant table

func test_every_name_of_the_variant_table_is_in_the_atlas() -> void:
	var table: Dictionary = (_fixture().get("table", {}) as Dictionary)
	var names: Array = table.get("names", [])
	assert_gt(names.size(), 600, "the table lists the pictures")
	var missing: Array[String] = []
	for picture: String in names:
		if not Data.PICTURES.has(picture):
			missing.append(picture)
	assert_eq(missing, [], "names of the table that the atlas lacks")


func test_the_atlas_has_no_picture_that_the_table_does_not_list() -> void:
	var table: Dictionary = (_fixture().get("table", {}) as Dictionary)
	var listed: Dictionary = {}
	for picture: String in table.get("names", []):
		listed[picture] = true
	var extra: Array[String] = []
	for picture: String in Data.PICTURES:
		if not listed.has(picture):
			extra.append(picture)
	assert_eq(extra, [], "pictures in the atlas that are not in the table")
	assert_eq(Data.PICTURES.size(), listed.size(), "the same number of names")


func test_every_frame_of_every_animation_exists_for_every_cord() -> void:
	var animations: Dictionary = (_fixture().get("table", {}) as Dictionary).get("animations", {})
	assert_gt(animations.size(), 10, "the table has animations")
	var missing: Array[String] = []
	var frames: int = 0
	for key: String in animations:
		var anim: Dictionary = animations[key]
		for group: String in ["frames", "blink"]:
			for per_cord: Dictionary in anim[group]:
				for picture: String in per_cord["names"]:
					frames += 1
					if not Data.PICTURES.has(picture):
						missing.append("%s: %s" % [key, picture])
	assert_gt(frames, 100)
	assert_eq(missing, [], "frames that no picture has")
	# the data in atlas_data.gd name the same poses
	for key: String in Data.ANIMATIONS:
		assert_true(animations.has(key), "%s is in the table" % key)


func test_every_cord_and_rug_of_the_table_is_in_the_atlas_data() -> void:
	var table: Dictionary = (_fixture().get("table", {}) as Dictionary)
	assert_eq((Data.CORDS as Dictionary).keys(), (table["cords"] as Dictionary).keys(), "the cord names")
	assert_eq(Data.RUGS.size(), (table["rugs"] as Array).size(), "the rug colours")
	for cord: String in Data.CORDS:
		assert_true(Data.PICTURES.has("penguin/%s/front/idle" % cord), "%s has a penguin" % cord)
	for rug: Dictionary in Data.RUGS:
		assert_true(Data.PICTURES.has("room/%s" % rug["name"]), "%s has a room" % rug["name"])
	var props: Array[String] = []
	for place: Dictionary in Data.PROP_PLACES:
		props.append(place["name"])
		assert_true(Data.PICTURES.has(place["name"]), "%s has a picture" % place["name"])
	assert_eq(props.size(), 12, "twelve props in the room table of the mockup")


func test_a_mirrored_left_view_needs_no_picture_of_its_own() -> void:
	for picture: String in Data.PICTURES:
		assert_false("/left/" in picture,"%s: the left view is the right view, mirrored" % picture)


# ---------------------------------------------------------------- loading

func test_the_sheets_load_as_textures_and_the_time_is_small() -> void:
	var started: int = Time.get_ticks_usec()
	var textures: Array[Texture2D] = []
	for path: String in Data.SHEETS:
		textures.append(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D)
	var elapsed_ms: float = (Time.get_ticks_usec() - started) / 1000.0
	gut.p("load time of %d sheets: %.1f ms (headless, no GPU upload)" % [textures.size(), elapsed_ms])
	for sheet in textures.size():
		assert_not_null(textures[sheet], Data.SHEETS[sheet])
		if textures[sheet] != null:
			assert_eq(Vector2i(textures[sheet].get_size()), Vector2i(_image(sheet).get_size()), "%s: the texture has the size of the PNG" % Data.SHEETS[sheet])
	assert_lt(elapsed_ms, LOAD_LIMIT_MS, "load time of the sheets")


func test_the_atlas_data_script_compiles_fast() -> void:
	var started: int = Time.get_ticks_usec()
	var script: Resource = ResourceLoader.load("res://art/atlas_data.gd", "", ResourceLoader.CACHE_MODE_IGNORE)
	var elapsed_ms: float = (Time.get_ticks_usec() - started) / 1000.0
	gut.p("compile time of atlas_data.gd: %.1f ms" % elapsed_ms)
	assert_not_null(script)
	assert_lt(elapsed_ms, LOAD_LIMIT_MS, "compile time of atlas_data.gd")


func test_the_atlas_api_finds_a_picture() -> void:
	assert_true(Atlas.has("penguin/claude-code/side/hammer"))
	assert_false(Atlas.has("penguin/claude-code/left/hammer"))
	assert_eq(Atlas.size_of("penguin/claude-code/front/idle"), Vector2i(48, 50))
	assert_eq(Atlas.size_of("room/red"), Vector2i(480, 232))
	assert_eq(Atlas.rect_of("room/red"), Rect2i(0, 0, 480, 232))
	assert_not_null(Atlas.texture(Atlas.sheet_of("prop/forge")))


func test_a_mirrored_picture_keeps_its_left_edge() -> void:
	# An earlier version moved a mirrored picture one width to the right. A negative width mirrors in place in Godot 4.7.2.
	# The room view showed it on a screenshot. This test keeps the rectangle.
	var plain: Rect2 = Atlas.destination(Vector2(10, 5), Vector2(48, 50), false)
	var mirrored: Rect2 = Atlas.destination(Vector2(10, 5), Vector2(48, 50), true)
	assert_eq(plain, Rect2(10, 5, 48, 50))
	assert_eq(mirrored, Rect2(10, 5, -48, 50))
	assert_eq(mirrored.position, plain.position, "same left edge")
	assert_eq(absf(mirrored.size.x), plain.size.x, "same width")
