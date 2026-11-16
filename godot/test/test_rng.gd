extends GutTest
## `rng.gd` gives the same numbers as `mulberry32` of the JavaScript mockup (removed, see the git history).
## `test/fixtures/rng.json` holds the first outputs of the JavaScript for some seeds, as 32-bit integers.

const Rng := preload("res://src/core/rng.gd")
const Golden := preload("res://test/support/golden.gd")


func test_the_first_outputs_equal_the_javascript() -> void:
	var data: Variant = Golden.load_json("res://test/fixtures/rng.json")
	assert_typeof(data, TYPE_DICTIONARY, "test/fixtures/rng.json is there (a fixed snapshot, see test/fixtures/README.md)")
	if typeof(data) != TYPE_DICTIONARY:
		return
	var cases: Array = (data as Dictionary)["cases"]
	assert_gt(cases.size(), 10, "some seeds")
	for kase: Dictionary in cases:
		var rng: RefCounted = Rng.mulberry32(int(kase["seed"]))
		var u32: Array = kase["u32"]
		var floats: Array = kase["floats"]
		var wrong: Array[String] = []
		for i in u32.size():
			var got: int = rng.next_u32()
			if got != int(u32[i]):
				wrong.append("number %d: expected %d, got %d" % [i, int(u32[i]), got])
				break
		assert_eq(wrong, [], "seed %d: the 32-bit integers" % int(kase["seed"]))
		var again: RefCounted = Rng.mulberry32(int(kase["seed"]))
		for i in floats.size():
			var got_float: float = again.next()
			if absf(got_float - float(floats[i])) > 1e-15:
				wrong.append("float %d: expected %s, got %s" % [i, floats[i], got_float])
				break
		assert_eq(wrong, [], "seed %d: the floats" % int(kase["seed"]))


func test_imul_is_math_imul() -> void:
	# The values come from `Math.imul` in Node, shown as unsigned numbers.
	assert_eq(Rng.imul(0xFFFFFFFF, 0xFFFFFFFF), 1)
	assert_eq(Rng.imul(0x12345678, 0x9ABCDEF0), 606937216)
	assert_eq(Rng.imul(0xFFFFFFFF, 0x6D2B79F5), 2463401483)
	assert_eq(Rng.imul(0x80000000, 3), 2147483648)
	assert_eq(Rng.imul(0, 0xFFFFFFFF), 0)


func test_the_numbers_are_in_the_range_and_a_seed_makes_a_sequence() -> void:
	var rng: RefCounted = Rng.mulberry32(2028)
	var other: RefCounted = Rng.mulberry32(2028)
	for i in 1000:
		var x: float = rng.next()
		assert_true(x >= 0.0 and x < 1.0, "number %d is in [0, 1)" % i)
		assert_eq(x, other.next(), "the same seed gives the same number")
	assert_ne(Rng.mulberry32(1).next(), Rng.mulberry32(2).next(), "other seeds give other numbers")
