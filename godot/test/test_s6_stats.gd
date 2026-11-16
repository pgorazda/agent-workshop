extends GutTest
## The numbers of spike S-6 (godot/spikes/s6/): percentiles, the summary of a run, the fit scale, and the picture compare.

const Stats := preload("res://spikes/s6/s6_stats.gd")


func _values(items: Array) -> PackedFloat64Array:
	var packed: PackedFloat64Array = PackedFloat64Array()
	for item: Variant in items:
		packed.append(float(item))
	return packed


func test_percentile_of_one_value_is_that_value() -> void:
	assert_eq(Stats.percentile(_values([4.0]), 99.0), 4.0)


func test_percentile_of_an_empty_list_is_zero() -> void:
	assert_eq(Stats.percentile(PackedFloat64Array(), 50.0), 0.0)


func test_percentile_interpolates_between_neighbours() -> void:
	var sorted_values: PackedFloat64Array = _values([1, 2, 3, 4, 5])
	assert_almost_eq(Stats.percentile(sorted_values, 50.0), 3.0, 1e-9)
	assert_almost_eq(Stats.percentile(sorted_values, 25.0), 2.0, 1e-9)
	assert_almost_eq(Stats.percentile(sorted_values, 90.0), 4.6, 1e-9)
	assert_almost_eq(Stats.percentile(sorted_values, 100.0), 5.0, 1e-9)


func test_summary_of_unsorted_values() -> void:
	var summary: Dictionary = Stats.summarize(_values([5, 1, 3, 2, 4]))
	assert_eq(summary["count"], 5)
	assert_almost_eq(float(summary["mean"]), 3.0, 1e-9)
	assert_almost_eq(float(summary["median"]), 3.0, 1e-9)
	assert_almost_eq(float(summary["worst"]), 5.0, 1e-9)


func test_summary_counts_the_share_over_the_budget() -> void:
	var summary: Dictionary = Stats.summarize(_values([10, 20, 10, 30]), 16.7)
	assert_almost_eq(float(summary["over_share"]), 50.0, 1e-9)


func test_summary_of_nothing_is_zero() -> void:
	var summary: Dictionary = Stats.summarize(PackedFloat64Array())
	assert_eq(summary["count"], 0)
	assert_eq(float(summary["median"]), 0.0)
	assert_eq(float(summary["worst"]), 0.0)


func test_grid_columns() -> void:
	assert_eq(Stats.grid_columns(1), 1)
	assert_eq(Stats.grid_columns(4), 2)
	assert_eq(Stats.grid_columns(9), 3)
	assert_eq(Stats.grid_columns(16), 4)
	assert_eq(Stats.grid_columns(10), 4)


func test_fit_scale() -> void:
	var room: Vector2 = Vector2(480, 232)
	var view: Vector2 = Vector2(480, 270)
	assert_eq(Stats.fit_scale(1, room, 16.0, view), 1.0)
	# 16 rooms: 4 columns of 480 and 3 gutters is 1968 wide. 480 / 1968 is the smaller of the two ratios.
	assert_almost_eq(Stats.fit_scale(16, room, 16.0, view), 480.0 / 1968.0, 1e-9)
	assert_almost_eq(Stats.fit_scale(4, room, 16.0, view), 480.0 / 976.0, 1e-9)


## An RGBA image of one grey level (0 to 255), or a checker of black and white when `checker` is true.
func _image(width: int, height: int, grey: int, checker: bool = false) -> Image:
	var bytes: PackedByteArray = PackedByteArray()
	for y in height:
		for x in width:
			var level: int = grey
			if checker:
				level = 255 if (x + y) % 2 == 0 else 0
			bytes.append_array(PackedByteArray([level, level, level, 255]))
	var image: Image = Image.new()
	image.set_data(width, height, false, Image.FORMAT_RGBA8, bytes)
	return image


func test_box_reference_is_exact_for_a_perfect_shrink() -> void:
	# A 4x4 reference with a checker of black and white. A 2x2 shrink gives grey everywhere.
	var reference: Image = _image(4, 4, 0, true)
	var grey: Image = _image(2, 2, 128)
	assert_almost_eq(Stats.mean_diff_to_box_reference(grey, Vector2i(0, 0), reference, 2, Vector2i(2, 2)), 0.0, 1.0)
	# A shrink that dropped rows and columns (every other pixel) is far from grey.
	var dropped: Image = _image(2, 2, 255)
	assert_gt(Stats.mean_diff_to_box_reference(dropped, Vector2i(0, 0), reference, 2, Vector2i(2, 2)), 100.0)
