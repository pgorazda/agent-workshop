extends RefCounted
## The random numbers of the mockup: mulberry32 (`mulberry32` of the JavaScript mockup, removed, see the git history).
##
## The JavaScript works on 32-bit integers with `Math.imul` and `>>>`. GDScript integers have 64 bits.
## So this class keeps the state as an unsigned 32-bit number and masks every result.
## `test/fixtures/rng.json` holds the first outputs of the JavaScript. A test compares them.

const MASK := 0xFFFFFFFF
const INCREMENT := 0x6D2B79F5

var _state: int = 0


func _init(seed_value: int = 0) -> void:
	# JavaScript: `a |= 0`. A 32-bit mask gives the same bits, also for a negative seed.
	_state = seed_value & MASK


## Same as `mulberry32(seed)` in the JavaScript. The result is an object: call `next()` on it.
static func mulberry32(seed_value: int) -> RefCounted:
	return new(seed_value)


## `Math.imul` for two unsigned 32-bit numbers: the low 32 bits of the product, unsigned.
## The product is built from 16-bit parts, so no step goes over 63 bits.
static func imul(x: int, y: int) -> int:
	var x_high: int = (x >> 16) & 0xFFFF
	var x_low: int = x & 0xFFFF
	return (x_low * y + (((x_high * y) & 0xFFFF) << 16)) & MASK


## The next number as an unsigned 32-bit integer (0 to 4294967295).
func next_u32() -> int:
	_state = (_state + INCREMENT) & MASK
	var t: int = imul(_state ^ (_state >> 15), 1 | _state)
	t = ((t + imul(t ^ (t >> 7), 61 | t)) ^ t) & MASK
	return (t ^ (t >> 14)) & MASK


## The next number as a float, from 0 (included) to 1 (not included).
func next() -> float:
	return float(next_u32()) / 4294967296.0
