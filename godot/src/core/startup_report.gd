extends RefCounted
## The times of the start-up (`--startup-report=<file>`): when the client began, when its atlases were loaded, when the first
## frame was processed, and when each of the first frames was drawn. All times are microseconds of the engine clock (`Time.get_ticks_usec`),
## which starts when the engine starts. `tools/startup.mjs` runs the client several times and prints the medians. The report also has the
## time of the clock of the system at the first drawn frame, so that the tool can add the time from the start of the process.

## The number of drawn frames that the report waits for.
const FRAMES := 8

var marks: Dictionary = { }
var drawn: Array[int] = []
## The `delta` that the engine gave to the first calls of `_process`, in milliseconds.
var process_deltas: Array[float] = []
var unix_ms_at_first_draw: float = 0.0


## Remembers a time. A name that is already there keeps its first time.
func mark(label: String, usec: int = -1) -> void:
	if marks.has(label):
		return
	marks[label] = Time.get_ticks_usec() if usec < 0 else usec


## A frame was drawn.
func frame_drawn() -> void:
	drawn.append(Time.get_ticks_usec())
	if drawn.size() == 1:
		unix_ms_at_first_draw = Time.get_unix_time_from_system() * 1000.0


func is_complete() -> bool:
	return drawn.size() >= FRAMES


## The report as JSON text: the marks in milliseconds, the time between the drawn frames, and the system time of the first one.
func to_json() -> String:
	var out: Dictionary = { "marks_ms": { }, "frame_ms": [], "process_delta_ms": process_deltas, "unix_ms_at_first_draw": unix_ms_at_first_draw }
	for label: String in marks:
		(out["marks_ms"] as Dictionary)[label] = float(marks[label]) / 1000.0
	if not drawn.is_empty():
		(out["marks_ms"] as Dictionary)["first_draw"] = float(drawn[0]) / 1000.0
	for i in range(1, drawn.size()):
		(out["frame_ms"] as Array).append(float(drawn[i] - drawn[i - 1]) / 1000.0)
	return JSON.stringify(out, "\t")
