extends GutTest
## The shapes of `draw_kit.gd` equal the shapes that pxEll, pxLine, bitmap and box of `art/image_src/look.js` draw.
## The expected values come from the JavaScript: `look.js` ran with a canvas that records each fillRect call.
## The values are copied into this file. To make them again, run the same calls in the baker page.

const DrawKit := preload("res://art/draw_kit.gd")


func _rects(list: Array[Rect2i]) -> Array:
	var out: Array = []
	for r in list:
		out.append([r.position.x, r.position.y, r.size.x, r.size.y])
	return out


func _points(list: Array[Vector2i]) -> Array:
	var out: Array = []
	for p in list:
		out.append([p.x, p.y])
	return out


## The set of pixels that some rectangles cover, sorted by row and then column, as [x, y] pairs.
func _pixels(list: Array[Rect2i]) -> Array:
	var out: Array = []
	for r in list:
		for y in r.size.y:
			for x in r.size.x:
				out.append([r.position.x + x, r.position.y + y])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1] or (a[1] == b[1] and a[0] < b[0]))
	return out


func _sorted(points: Array) -> Array:
	var copy: Array = points.duplicate()
	copy.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1] or (a[1] == b[1] and a[0] < b[0]))
	return copy


func test_rounding_is_math_round() -> void:
	assert_eq(DrawKit.rnd(2.5), 3)
	assert_eq(DrawKit.rnd(2.4), 2)
	assert_eq(DrawKit.rnd(-0.5), 0, "Math.round(-0.5) is -0")
	assert_eq(DrawKit.rnd(-1.5), -1)
	assert_eq(DrawKit.rnd(0.0), 0)


func test_ellipse_rows_equal_pxell() -> void:
	assert_eq(_rects(DrawKit.ellipse_rects(10, 10, 3, 2)), [[8, 8, 4, 1], [7, 9, 6, 1], [7, 10, 6, 1], [8, 11, 4, 1]])
	assert_eq(_rects(DrawKit.ellipse_rects(5.5, 7.25, 4.2, 3.1)), [[4, 4, 3, 1], [2, 5, 7, 1], [1, 6, 9, 1], [1, 7, 9, 1], [2, 8, 7, 1], [3, 9, 5, 1]])
	assert_eq(_rects(DrawKit.ellipse_rects(0, 0, 1, 1)), [[-1, -1, 2, 1], [-1, 0, 2, 1]])


func test_an_ellipse_with_no_size_has_no_rows() -> void:
	assert_eq(DrawKit.ellipse_rects(20, 20, 0, 3).size(), 0)
	assert_eq(DrawKit.ellipse_rects(20, 20, 3, 0).size(), 0)


func test_line_pixels_equal_pxline() -> void:
	assert_eq(_points(DrawKit.line_points(0, 0, 5, 2)), [[0, 0], [1, 0], [2, 1], [3, 1], [4, 2], [5, 2]])
	assert_eq(_points(DrawKit.line_points(5, 5, 0, 0)), [[5, 5], [4, 4], [3, 3], [2, 2], [1, 1], [0, 0]])
	assert_eq(_points(DrawKit.line_points(2, 8, 2, 1)), [[2, 8], [2, 7], [2, 6], [2, 5], [2, 4], [2, 3], [2, 2], [2, 1]])
	assert_eq(_points(DrawKit.line_points(0.5, 0.5, 3.4, 3.5)), [[1, 1], [2, 2], [2, 3], [3, 4]], "the ends are rounded first")
	assert_eq(_points(DrawKit.line_points(3, 3, 3, 3)), [[3, 3]], "one pixel")


func test_bitmap_pixels_equal_bitmap() -> void:
	var star: Array[String] = [".#.", "###", ".#."]
	assert_eq(_pixels(DrawKit.bitmap_rects(star, 3.4, 2.6)), _sorted([[4, 3], [3, 4], [4, 4], [5, 4], [4, 5]]))
	var spark: Array[String] = ["...#...", "...#...", "..###..", "#######", "..###..", "...#...", "...#..."]
	assert_eq(_pixels(DrawKit.bitmap_rects(spark, 0, 0)), _sorted([[3, 0], [3, 1], [2, 2], [3, 2], [4, 2], [0, 3], [1, 3], [2, 3], [3, 3], [4, 3], [5, 3], [6, 3], [2, 4], [3, 4], [4, 4], [3, 5], [3, 6]]))
	var sign_mark: Array[String] = [".###.", "#...#", "....#", "..##.", "..#..", ".....", "..#.."]
	assert_eq(_pixels(DrawKit.bitmap_rects(sign_mark, -1.5, 4)), _sorted([[0, 4], [1, 4], [2, 4], [-1, 5], [3, 5], [3, 6], [1, 7], [2, 7], [1, 8], [1, 10]]), "a negative x is rounded as Math.round does")


func test_a_bitmap_makes_one_rectangle_for_each_run() -> void:
	var rows: Array[String] = ["###.##", "......", "#"]
	assert_eq(_rects(DrawKit.bitmap_rects(rows, 0, 0)), [[0, 0, 3, 1], [4, 0, 2, 1], [0, 2, 1, 1]])


func test_box_parts_equal_box() -> void:
	assert_eq(_rects(DrawKit.box_rects(2.4, 3.5, 6, 5)), [[3, 4, 4, 1], [3, 8, 4, 1], [2, 5, 1, 3], [7, 5, 1, 3], [3, 5, 4, 3]])
	assert_eq(_rects([DrawKit.box_shadow_rect(2.4, 3.5, 6, 5)]), [[3, 9, 4, 1]])
	assert_eq(_rects(DrawKit.box_rects(10, 10, 11, 11)), [[11, 10, 9, 1], [11, 20, 9, 1], [10, 11, 1, 9], [20, 11, 1, 9], [11, 11, 9, 9]])


# ---------------------------------------------------------------- the fast ellipse

func test_the_fast_ellipse_gives_the_rectangles_of_a_test_of_every_pixel() -> void:
	# the ellipses of the room (glow, shadows), the ring of the focus, and random ones with fractions
	var cases: Array = [
		[396.0, 92.0, 54.0, 20.0], [396.0, 92.0, 36.0, 13.0], [396.0, 92.0, 18.0, 7.0], [124.0, 168.0, 30.0, 22.0], [124.0, 168.0, 20.0, 15.0],
		[100.0, 100.0, 8.0, 2.4], [100.5, 100.5, 8.0, 2.4], [7.5, 237.5, 2.2, 2.2], [0.0, 0.0, 1.0, 1.0], [10.0, 10.0, 0.5, 0.5],
		[50.0, 40.0, 14.0, 5.0], [240.0, 116.0, 120.0, 58.0], [3.0, 3.0, 3.0, 3.0], [5.0, 5.0, 2.5, 2.5], [-4.25, 12.75, 6.5, 3.5],
	]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261116
	for i in 300:
		cases.append([rng.randf_range(-5.0, 480.0), rng.randf_range(-5.0, 270.0), rng.randf_range(0.3, 60.0), rng.randf_range(0.3, 30.0)])
	for i in 60:
		# whole and half numbers are where a test on the edge of a pixel can go either way
		cases.append([float(rng.randi_range(0, 400)) + 0.5 * float(rng.randi_range(0, 1)), float(rng.randi_range(0, 250)) + 0.5 * float(rng.randi_range(0, 1)), float(rng.randi_range(1, 40)) + 0.5 * float(rng.randi_range(0, 1)), float(rng.randi_range(1, 25)) + 0.5 * float(rng.randi_range(0, 1))])
	for entry: Array in cases:
		var fast: Array[Rect2i] = DrawKit.ellipse_rects(float(entry[0]), float(entry[1]), float(entry[2]), float(entry[3]))
		var slow: Array[Rect2i] = DrawKit.ellipse_rects_by_pixel(float(entry[0]), float(entry[1]), float(entry[2]), float(entry[3]))
		assert_eq(fast, slow, "ellipse %s" % str(entry))
	assert_eq(DrawKit.ellipse_rects(5.0, 5.0, 0.0, 3.0).size(), 0)
	assert_eq(DrawKit.ellipse_rects(5.0, 5.0, 3.0, -1.0).size(), 0)
