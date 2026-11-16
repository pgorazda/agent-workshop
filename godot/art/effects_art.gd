# Copyright (c) 2026 Pawel Gorazda. All rights reserved.
# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
#
# The effects that depend on time, drawn each frame from the effect cues (src/core/effects.gd) and from the penguins:
# dust under a walk, the puff of a penguin that appears or goes, the sparks and the fire of the forge, the smoke of a failed
# run, the stars of the hammer and of the bell, the confetti and sparkles of a finished turn, the thought cloud with its
# candle, and the stars around a penguin that flopped. It follows `session-art.js` and `crowd-art.js` of the mockup.
#
# Every function is a function of the time and of the seeded random numbers (src/core/rng.gd): the same cues and the same
# time give the same picture. Nothing here reads a clock. The pictures that are fixed (the cloud, the candle, the flame, the
# stars) come from the atlas.
extends RefCounted

const Atlas := preload("res://art/atlas.gd")
const DrawKit := preload("res://art/draw_kit.gd")
const Rng := preload("res://src/core/rng.gd")

const INK := Color("#1d2333")
const CREAM := Color("#f7f9fc")
const WHITE := Color("#ffffff")
const GOLD := Color("#f2c230")
const FIRE1 := Color("#fff3b0")
const FIRE2 := Color("#ffc23d")
const FIRE3 := Color("#ff7a2a")
const STONE_LT := Color("#b6c0cc")
const STONE_DK := Color("#66717f")
const DUST_DARK := Color("#b98d5c")
const DUST_LIGHT := Color("#ecd2a6")
const CONFETTI: Array[Color] = [Color("#d23c3c"), Color("#3a6fc4"), Color("#3f9a5a"), Color("#f7f9fc"), Color("#f2c230"), Color("#2a9d8f")]
## The flicker of a candle flame: the frame of the flame for each 0.11 s.
const FLICKER: Array[int] = [0, 1, 0, 2, 3, 0, 2, 1, 0, 3]
## The sparkle sizes of a finished turn, from `spark/0` to `spark/3` and back.
const SPARKLE_FRAMES: Array[int] = [0, 1, 2, 3, 3, 2, 1]
const GRAVITY := 150.0
## The seated penguin's thought bubble is in fixed places by the armchair (session-art.js).
const SEAT_DOTS: Array = [[0.05, 108.0, 152.0, 2.0, 1.6, 1.2, 0.9], [0.15, 115.0, 144.0, 3.0, 2.4, 2.2, 1.6]]
const SEAT_CLOUD := Vector2(114, 108)
const SEAT_CANDLE := Vector2(141, 135)
const BELL_STARS: Array = [[410.0, 174.0, true], [397.0, 172.0, true], [415.0, 181.0, false]]
## The center of the forge fire.
const FORGE_FIRE := Vector2(396, 75)
## The place where sparks leave the forge when a penguin shovels coal.
const SPARK_ORIGIN := Vector2(386, 74)


# ---------------------------------------------------------------- before the penguins

## What lies on the floor, under the penguins: dust.
static func draw_under(ci: CanvasItem, cues: Array[Dictionary], now: float) -> void:
	for cue in cues:
		if cue["kind"] == "dust":
			_dust(ci, cue, now - float(cue["t0"]))


# ---------------------------------------------------------------- after the penguins

## Everything that is drawn over the props and the penguins. `penguins` are the dictionaries of `room_stage_art.gd`.
static func draw_over(ci: CanvasItem, cues: Array[Dictionary], now: float, penguins: Array[Dictionary]) -> void:
	forge_life(ci, now)
	for cue in cues:
		var age: float = now - float(cue["t0"])
		if age < 0.0:
			continue
		match cue["kind"]:
			"spark":
				_sparks(ci, cue, age)
			"puff":
				puff(ci, float(cue["x"]), float(cue["y"]), age, float(cue["scale"]))
			"smoke":
				_smoke(ci, age)
			"tink":
				Atlas.draw(ci, "spark/mini", Vector2(float(cue["x"]) + 9.0, float(cue["y"]) - 30.0), false, CREAM)
			"bell":
				for star: Array in BELL_STARS:
					Atlas.draw(ci, "spark/mini", Vector2(float(star[0]), float(star[1])), false, GOLD if star[2] else CREAM)
			"confetti":
				_confetti(ci, cue, age)
		if cue["kind"] == "sparkle":
			_sparkle(ci, cue, age)
	for penguin in penguins:
		_thinking(ci, penguin, now)
		_flop_stars(ci, penguin, now)


## The fire in the forge: a few pixels of the fire colours that change ten times a second.
static func forge_life(ci: CanvasItem, now: float) -> void:
	var rng: RefCounted = Rng.mulberry32(int(floorf(now * 10.0)) * 7 + 1)
	var colors: Array[Color] = [FIRE1, FIRE2, FIRE3]
	for i in 12:
		var angle: float = rng.next() * PI * 2.0
		var radius: float = sqrt(rng.next())
		DrawKit.px(ci, FORGE_FIRE.x + cos(angle) * 7.0 * radius, FORGE_FIRE.y + sin(angle) * 5.0 * radius, colors[i % 3])
	for i in 3:
		var x: float = 390.0 + rng.next() * 12.0
		var y: float = 64.0 + rng.next() * 4.0
		DrawKit.px(ci, x, y, FIRE2 if rng.next() < 0.5 else FIRE3)


## A puff of smoke for a penguin that pops in or goes (`puff` of session-art.js). `age` is in seconds, `scale` shrinks it for a helper.
static func puff(ci: CanvasItem, x: float, y: float, age: float, scale: float = 1.0) -> void:
	var k: float = minf(1.0, age / 0.35)
	var r: float = (2.8 * (1.0 - k) + 0.4) * scale
	for i in 7:
		var angle: float = float(i) / 7.0 * PI * 2.0 + 0.4
		var radius: float = (4.0 + 13.0 * k) * scale
		var cx: float = x + cos(angle) * radius
		var cy: float = y - 12.0 * scale + sin(angle) * radius * 0.7
		DrawKit.ellipse(ci, cx, cy, r + 0.7, r * 0.8 + 0.7, STONE_LT)
		DrawKit.ellipse(ci, cx, cy - 0.3, r, r * 0.8, WHITE)


static func _dust(ci: CanvasItem, cue: Dictionary, age: float) -> void:
	if age < 0.0 or age > 0.4:
		return
	var radius: float = (2.2 * (1.0 - age / 0.4) + 0.3) * float(cue["scale"])
	var x: float = float(cue["x"])
	var y: float = float(cue["y"])
	DrawKit.ellipse(ci, x, y, radius + 0.7, radius * 0.7 + 0.7, DUST_DARK)
	DrawKit.ellipse(ci, x, y - 0.3, radius, radius * 0.7, DUST_LIGHT)


## Nine sparks that fly up from the forge and fall (`sparksAt` of session-art.js).
static func _sparks(ci: CanvasItem, cue: Dictionary, age: float) -> void:
	if age > 0.65:
		return
	var rng: RefCounted = Rng.mulberry32(int(cue["seed"]))
	for i in 9:
		var vx: float = 15.0 + rng.next() * 85.0
		var vy: float = -(25.0 + rng.next() * 85.0)
		var x: float = SPARK_ORIGIN.x + vx * age
		var y: float = SPARK_ORIGIN.y + vy * age + 130.0 * age * age
		var color: Color = FIRE1 if age < 0.2 else (FIRE2 if age < 0.4 else FIRE3)
		DrawKit.px(ci, x, y, color)
		if rng.next() < 0.5 and age < 0.3:
			DrawKit.px(ci, x - 1.0, y + 1.0, FIRE3)


## Five puffs of grey smoke that rise from the chimney after a failed run at the forge.
static func _smoke(ci: CanvasItem, age: float) -> void:
	for i in 5:
		var a: float = age - float(i) * 0.22
		if a < 0.0 or a > 1.1:
			continue
		var x: float = 396.0 + sin(a * 5.0 + float(i)) * 3.0 + (4.0 if i % 2 == 1 else -3.0)
		var y: float = 66.0 - a * 26.0
		var r: float = 2.4 + a * 2.6
		DrawKit.ellipse(ci, x, y, r + 0.8, r * 0.8 + 0.8, STONE_DK)
		DrawKit.ellipse(ci, x, y, r, r * 0.8, STONE_LT)


## The confetti of a finished turn: 70 pieces that fly up, flutter and land (`burst` of crowd-art.js). The cue holds the foot of
## the penguin. A piece that is outside the room is not drawn.
static func _confetti(ci: CanvasItem, cue: Dictionary, age: float) -> void:
	if age > 4.0:
		return
	var cx: float = float(cue["x"])
	var cy: float = float(cue["y"])
	var rng: RefCounted = Rng.mulberry32(int(cue["seed"]))
	for i in 70:
		var delay: float = rng.next() * 0.3
		var vx: float = (rng.next() - 0.5) * 160.0
		var vy: float = -(80.0 + rng.next() * 120.0)
		var floor_y: float = cy - 40.0 + rng.next() * 70.0
		var x0: float = cx + (rng.next() - 0.5) * 12.0
		var y0: float = cy - 36.0
		var phase: float = rng.next() * 6.0
		var a: float = age - delay
		if a < 0.0:
			continue
		var land: float = (-vy + sqrt(vy * vy + 4.0 * GRAVITY * (floor_y - y0))) / (2.0 * GRAVITY)
		var landed: bool = a >= land
		var x: float = x0 + vx * land if landed else x0 + vx * a + (sin(a * 9.0 + phase) * 2.5 if vy + 2.0 * GRAVITY * a > 0.0 else 0.0)
		var y: float = floor_y if landed else y0 + vy * a + GRAVITY * a * a
		if x < 8.0 or x > 471.0 or y < 6.0 or y > 224.0:
			continue
		var thin: bool = (not landed) and int(floorf(a * 10.0 + phase)) % 2 != 0
		DrawKit.fill(ci, x, y, 1.0 if thin else 2.0, 2.0 if thin else 1.0, CONFETTI[i % CONFETTI.size()])


## A gold star that grows and shrinks (`sparkle`). The cue holds its centre.
static func _sparkle(ci: CanvasItem, cue: Dictionary, age: float) -> void:
	var life: float = 0.5
	if age < 0.0 or age > life:
		return
	var frame: int = SPARKLE_FRAMES[mini(6, int(floorf(age / life * 7.0)))]
	var picture: String = "spark/%d" % frame
	var size: Vector2i = Atlas.size_of(picture)
	Atlas.draw(ci, picture, Vector2(float(cue["x"]) - float(size.x >> 1), float(cue["y"]) - float(size.y >> 1)), false, GOLD)


# ---------------------------------------------------------------- the thought cloud and the flop

## The cloud with a candle of a penguin that thinks. The seated penguin has a big cloud by the armchair. Another penguin has a
## small one above its head. The candle burns down while the thinking lasts, and each new spell starts with a new candle.
static func _thinking(ci: CanvasItem, penguin: Dictionary, now: float) -> void:
	var age: float = float(penguin.get("think_age", -1.0))
	if age < 0.0:
		return
	if bool(penguin.get("think_in_place", false)):
		var x: float = float(penguin["x"])
		var y: float = float(penguin["y"])
		if age > 0.05:
			DrawKit.ellipse(ci, x - 8.0, y - 44.0, 1.6, 1.3, INK)
			DrawKit.ellipse(ci, x - 8.0, y - 44.0, 0.9, 0.7, CREAM)
		if age > 0.2:
			Atlas.draw(ci, "prop/cloud-mini", Vector2(x - 48.0, y - 78.0))
			var wax: int = maxi(2, 5 - int(floorf((age - 0.2) / 0.9)))
			candle_in_cloud(ci, x - 28.0, y - 54.0, wax, now + float(penguin.get("number", 0)) * 0.37)
		return
	for dot: Array in SEAT_DOTS:
		if age > float(dot[0]):
			DrawKit.ellipse(ci, float(dot[1]), float(dot[2]), float(dot[3]), float(dot[4]), INK)
			DrawKit.ellipse(ci, float(dot[1]), float(dot[2]), float(dot[5]), float(dot[6]), CREAM)
	if age > 0.25:
		Atlas.draw(ci, "prop/cloud", SEAT_CLOUD)
		var wax: int = maxi(3, 8 - int(floorf((age - 0.25) / 1.0)))
		candle_in_cloud(ci, SEAT_CANDLE.x, SEAT_CANDLE.y, wax, now)


## A candle in a cloud: `x` is the centre of the dish and `base` is its lowest row. The flame flickers.
static func candle_in_cloud(ci: CanvasItem, x: float, base: float, wax: int, now: float) -> void:
	var picture: String = "prop/candle/%d" % clampi(wax, 2, 8)
	var height: int = Atlas.size_of(picture).y
	var top: float = base - float(height)
	var f: int = FLICKER[int(floorf(now / 0.11)) % FLICKER.size()]
	DrawKit.ellipse(ci, x + 0.5, top - 3.0, 5.0 + float(f % 2), 4.5 + float(f % 2), GOLD, 0.28)
	DrawKit.ellipse(ci, x + 0.5, top - 3.0, 3.5, 3.0, GOLD, 0.25)
	Atlas.draw(ci, picture, Vector2(x - 7.0, top))
	Atlas.draw(ci, "flame/%d" % f, Vector2(x - 2.0, top - 6.0))


## The ring of stars around a penguin that lies on the floor (the flop).
static func _flop_stars(ci: CanvasItem, penguin: Dictionary, now: float) -> void:
	var age: float = float(penguin.get("flop_age", -1.0))
	if age <= 0.3 or age >= 1.45:
		return
	var x: float = float(penguin["x"])
	var y: float = float(penguin["y"])
	DrawKit.ellipse(ci, x - 8.0, y - 24.0, 12.0, 3.4, GOLD, 0.22)
	for k in 5:
		var angle: float = float(k) / 5.0 * PI * 2.0 + now * 5.0
		Atlas.draw(ci, "spark/mini", Vector2(x - 9.0 + cos(angle) * 12.0, y - 25.0 + sin(angle) * 3.4), false, GOLD if k % 2 == 1 else CREAM)


## A gold star at (x, y) that grows and shrinks, `age` seconds after it started (the ribbon of a new arena uses it).
static func sparkle(ci: CanvasItem, x: float, y: float, age: float) -> void:
	_sparkle(ci, {"x": x, "y": y}, age)
