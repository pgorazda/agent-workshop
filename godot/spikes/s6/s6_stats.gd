extends RefCounted
## Spike S-6: the numbers of a run. Pure functions, tested in test/test_s6_stats.gd.

## The frame time that a 60 Hz screen allows, in milliseconds.
const BUDGET_MS := 16.7


## The p-th percentile (0 to 100) of sorted values, with linear interpolation between neighbours.
static func percentile(sorted_values: PackedFloat64Array, p: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var rank: float = clampf(p, 0.0, 100.0) / 100.0 * float(sorted_values.size() - 1)
	var low: int = int(floorf(rank))
	var high: int = mini(low + 1, sorted_values.size() - 1)
	return lerpf(sorted_values[low], sorted_values[high], rank - float(low))


## Count, mean, median, 95th and 99th percentile, worst value, and the share of values over the budget (0 to 100).
static func summarize(values: PackedFloat64Array, budget: float = BUDGET_MS) -> Dictionary:
	var sorted_values: PackedFloat64Array = values.duplicate()
	sorted_values.sort()
	var total: float = 0.0
	var over: int = 0
	for value in sorted_values:
		total += value
		if value > budget:
			over += 1
	var count: int = sorted_values.size()
	return {
		"count": count,
		"mean": total / float(count) if count > 0 else 0.0,
		"median": percentile(sorted_values, 50.0),
		"p95": percentile(sorted_values, 95.0),
		"p99": percentile(sorted_values, 99.0),
		"worst": sorted_values[count - 1] if count > 0 else 0.0,
		"over_share": 100.0 * float(over) / float(count) if count > 0 else 0.0,
	}


## The size of a grid of rooms: `count` rooms in `columns` columns, each `room` pixels, with `gutter` pixels between.
static func grid_columns(count: int) -> int:
	return maxi(1, ceili(sqrt(float(count))))


## The scale at which a whole grid fits in a view. It never goes above 1.
static func fit_scale(count: int, room: Vector2, gutter: float, view: Vector2) -> float:
	var columns: int = grid_columns(count)
	var rows: int = ceili(float(count) / float(columns))
	var width: float = float(columns) * room.x + float(columns - 1) * gutter
	var height: float = float(rows) * room.y + float(rows - 1) * gutter
	return minf(1.0, minf(view.x / width, view.y / height))


## The mean absolute difference (0 to 255, over the red, green and blue channels) between a test image and a
## reference that is shrunk by an exact factor. `block` is the factor: 2 means that a test pixel is compared with
## the mean of a 2x2 block of the reference. `test_origin` is the top left corner of the shrunk picture in `test`.
## The reference starts at its corner (0, 0). `size` is the size of the shrunk picture in pixels.
static func mean_diff_to_box_reference(test: Image, test_origin: Vector2i, ref_image: Image, block: int, size: Vector2i) -> float:
	var total: float = 0.0
	for y in size.y:
		for x in size.x:
			var mean: Color = Color(0, 0, 0, 0)
			for by in block:
				for bx in block:
					mean += ref_image.get_pixel(x * block + bx, y * block + by)
			mean = mean / float(block * block)
			var got: Color = test.get_pixel(test_origin.x + x, test_origin.y + y)
			total += absf(got.r - mean.r) + absf(got.g - mean.g) + absf(got.b - mean.b)
	return total / float(size.x * size.y * 3) * 255.0
