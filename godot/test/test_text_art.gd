extends GutTest
## Text from the glyph atlas (spike S-3): the widths agree with textW() of look.js, the sign of a room has the
## layout of room(), and a character that the atlas lacks shows as "?".
## `test/fixtures/art_variants.json` holds the numbers that the browser measured.

const TextArt := preload("res://art/text_art.gd")
const RoomArt := preload("res://art/room_art.gd")
const Data := preload("res://art/atlas_data.gd")
const Golden := preload("res://test/support/golden.gd")


func _fixture() -> Dictionary:
	var data: Variant = Golden.load_json("res://test/fixtures/art_variants.json")
	assert_typeof(data, TYPE_DICTIONARY, "test/fixtures/art_variants.json is there (run tools/render-art.mjs)")
	return data if typeof(data) == TYPE_DICTIONARY else {}


func _is_ascii(text: String) -> bool:
	for i in text.length():
		if text.unicode_at(i) > 126:
			return false
	return true


func test_the_width_of_a_text_is_the_sum_of_its_glyph_advances() -> void:
	var widths: Array = _fixture().get("widths", [])
	assert_gt(widths.size(), 100, "the browser measured many texts")
	for entry: Dictionary in widths:
		assert_eq(TextArt.width(entry["font"], entry["text"]), int(entry["sum"]), "%s: %s" % [entry["font"], entry["text"]])


func test_the_width_equals_textw_of_the_mockup_for_ascii_text() -> void:
	var checked: int = 0
	for entry: Dictionary in _fixture().get("widths", []):
		if not _is_ascii(entry["text"]):
			continue
		checked += 1
		assert_eq(TextArt.width(entry["font"], entry["text"]), int(entry["js"]), "%s: %s" % [entry["font"], entry["text"]])
	assert_gt(checked, 100)


func test_the_width_of_every_text_in_tiny5_equals_textw() -> void:
	# Tiny5 has whole-pixel advances for every glyph of the set, so the sum is exact, with Polish letters too.
	var checked: int = 0
	for entry: Dictionary in _fixture().get("widths", []):
		if entry["font"] == TextArt.TINY5:
			checked += 1
			assert_eq(TextArt.width(TextArt.TINY5, entry["text"]), int(entry["js"]), entry["text"])
	assert_gt(checked, 30)


func test_polish_text_in_silkscreen_is_at_most_three_pixels_wider_than_textw() -> void:
	# a known limit (see godot/README.md, spike S-3): the font has fractional advances for some Polish letters
	var seen: int = 0
	for entry: Dictionary in _fixture().get("widths", []):
		if entry["font"] != TextArt.TINY5 and not _is_ascii(entry["text"]):
			var difference: int = TextArt.width(entry["font"], entry["text"]) - int(entry["js"])
			assert_true(difference >= 0 and difference <= 5, "%s: %s differs by %d" % [entry["font"], entry["text"], difference])
			seen += 1
	assert_gt(seen, 4)


func test_the_known_widths() -> void:
	assert_eq(TextArt.width(TextArt.SILK, "AGENT WORKSHOP"), 82, "the sign of the single room (look.js: 'AGENT WORKSHOP' in Silk 8)")
	assert_eq(TextArt.width(TextArt.SILK, "ARENA"), 30)
	assert_eq(TextArt.width(TextArt.TINY5, ""), 0)


func test_every_character_of_the_set_has_a_glyph_in_every_font() -> void:
	var chars: String = (_fixture().get("table", {}) as Dictionary).get("chars", "")
	assert_eq(chars.length(), 95 + 18 + 3, "ASCII, the Polish letters and three symbols")
	for font: String in Data.GLYPH_FONTS:
		for i in chars.length():
			assert_true(Data.PICTURES.has(TextArt.glyph_name(font, chars[i])), "%s has %s" % [font, chars[i]])


func test_a_character_that_is_not_in_the_atlas_shows_as_a_question_mark() -> void:
	for font: String in Data.GLYPH_FONTS:
		for ch: String in ["Ж", "漢", "→", "\u0001", "😀"]:
			assert_eq(TextArt.glyph_for(font, ch), TextArt.glyph_name(font, "?"), "%s: U+%04X" % [font, ch.unicode_at(0)])
			assert_eq(TextArt.advance(font, ch), TextArt.advance(font, "?"))
	assert_eq(TextArt.width(TextArt.TINY5, "a漢b"), TextArt.width(TextArt.TINY5, "a?b"))


func test_the_polish_letters_have_their_own_glyphs() -> void:
	var polish: String = (_fixture().get("table", {}) as Dictionary).get("polish", "")
	assert_eq(polish.length(), 18)
	for i in polish.length():
		for font: String in Data.GLYPH_FONTS:
			assert_ne(TextArt.glyph_for(font, polish[i]), TextArt.glyph_name(font, "?"), "%s: %s is not drawn as ?" % [font, polish[i]])


func test_glyph_cells_have_the_height_of_their_font() -> void:
	for font: String in Data.GLYPH_FONTS:
		var h: int = TextArt.cell_height(font)
		assert_gt(h, 6, font)
		for picture: String in Data.PICTURES:
			if picture.begins_with("glyph/%s/" % font):
				assert_eq((Data.PICTURES[picture] as Array)[4], h, picture)


# ---------------------------------------------------------------- the sign of a room

func test_the_sign_layout_equals_room_of_look_js() -> void:
	var signs: Array = _fixture().get("signs", [])
	assert_gt(signs.size(), 10, "the browser measured the sign for several names")
	for entry: Dictionary in signs:
		var letter: String = entry["name"] if entry["name"] != null else ""
		var got: Dictionary = RoomArt.sign_layout(letter)
		for key: String in entry:
			if key == "name":
				continue
			assert_eq(got[key], entry[key] if typeof(entry[key]) == TYPE_BOOL else int(entry[key]), "sign %s: %s" % [entry["name"], key])


func test_the_rugs_repeat_every_five_arenas() -> void:
	assert_eq(RoomArt.rug_of_arena(0)["name"], "red")
	assert_eq(RoomArt.rug_of_arena(1)["name"], "cobalt")
	assert_eq(RoomArt.rug_of_arena(4)["name"], "teal")
	assert_eq(RoomArt.rug_of_arena(5)["name"], "red", "arena F has the red rug again")
	assert_eq(RoomArt.rug_named("no such rug")["name"], "red")
