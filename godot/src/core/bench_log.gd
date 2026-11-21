extends RefCounted
## The log of a benchmark run (`--benchmark=<scene>`): one line for each frame, as CSV, and the camera's moves as JSON.
## `tools/benchmark-report.mjs` reads both. This class builds the text. The view writes the files.
##
## The columns of a frame line: `t` (the simulation time of the frame, seconds), `frame_ms` (the time between this frame and the
## frame before it, as the engine reports it: it includes the wait for vsync), `process_ms` (the time that the client spent in its
## own frame code: the simulation and the update of the view; it does not include the drawing that the engine does afterwards),
## and `move` (the id of the camera move that is under way, or 0).

const HEADER := "t,frame_ms,process_ms,move"

var rows: PackedStringArray = PackedStringArray()


## Adds the line of a frame.
func add(t: float, frame_ms: float, process_ms: float, move_id: int) -> void:
	rows.append("%.4f,%.3f,%.3f,%d" % [t, frame_ms, process_ms, move_id])


func frame_count() -> int:
	return rows.size()


## The whole CSV text, with its header line.
func csv() -> String:
	return HEADER + "\n" + "\n".join(rows) + "\n"


## The moves of the camera as JSON: `[{id, t, to, why, kind, apart, dur, peak, wide}]`.
static func moves_json(moves: Array[Dictionary]) -> String:
	return JSON.stringify(moves, "\t")
