extends RefCounted
## The simulation clock: fixed steps of 1/60 s, whatever the frame rate.
##
## The frame code gives the time of the frame to `advance()`. The clock answers with the number of steps to run.
## The simulation, the effects and the timeline player all read `now`. No code reads the wall clock for the picture.
## A test or a recording calls `tick()` in a loop and needs no frame time at all.
##
## `now` is `steps * STEP`, so it does not drift when many steps run.

## One simulation step, in seconds.
const STEP := 1.0 / 60.0
## The longest frame time that counts. A longer frame (a window that was hidden, a stop in the debugger) counts as
## this long, so the simulation does not jump. The backlog rule handles the events that came in the meantime.
const MAX_FRAME := 0.1
## The speeds that the demo mode offers.
const SPEEDS: Array[float] = [0.5, 1.0, 2.0, 4.0]

## The number of steps that have run.
var steps: int = 0
## The simulation time in seconds.
var now: float = 0.0
## 1.0 is real time. 4.0 runs the story four times as fast.
var speed: float = 1.0
## A paused clock gives no steps.
var paused: bool = false

var _carry: float = 0.0


## Adds the time of one frame. Returns how many steps to run for it. Call `tick()` that many times. `max_frame` is the longest frame
## that counts (a window that is not shown has slow frames and lets them count for more).
func advance(frame_time: float, max_frame: float = MAX_FRAME) -> int:
	if paused or frame_time <= 0.0:
		return 0
	_carry += minf(frame_time, max_frame) * speed
	var count: int = int(_carry / STEP + 1e-9)
	_carry -= float(count) * STEP
	if _carry < 0.0:
		_carry = 0.0
	return count


## Runs one step. Returns the new time.
func tick() -> float:
	steps += 1
	now = float(steps) * STEP
	return now


## Back to time 0, or to `start` (a scene may begin before 0, with the agents that were there before; `start` is then below 0).
## The speed and the pause stay.
func reset(start: float = 0.0) -> void:
	steps = int(roundf(start / STEP))
	now = float(steps) * STEP
	_carry = 0.0


## The speed after `speed`, in the list of SPEEDS (the last one stays last).
func faster() -> void:
	speed = _next_speed(1)


## The speed before `speed` (the first one stays first).
func slower() -> void:
	speed = _next_speed(-1)


func _next_speed(direction: int) -> float:
	var index: int = 0
	for i in SPEEDS.size():
		if absf(SPEEDS[i] - speed) < absf(SPEEDS[index] - speed):
			index = i
	return SPEEDS[clampi(index + direction, 0, SPEEDS.size() - 1)]
