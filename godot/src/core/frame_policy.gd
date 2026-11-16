extends RefCounted
## How much the app draws, by the state of its window (choice 13 of the plan, "Cost beside a coding agent").
##
## The client runs next to a coding agent and is often visible but not focused. So:
##   * with focus, it draws at FOCUSED_FPS (60 by default; 0 is no cap). The simulation steps at 60 a second and the picture only
##     changes at a step, so a screen of 144 or 360 Hz would show the same picture again and again, and burn a core to do it;
##   * without focus, it draws at UNFOCUSED_FPS (30 by default). The simulation keeps its step of 1/60 s, so the story does
##     not change, only the number of pictures;
##   * when the window is minimized, it stops drawing. The events still come in and the simulation still runs, at a low frame
##     rate and with the actors in larger steps (nobody sees them), so the backlog rule has little to do when the window shows again.
## These are pure functions, so a test can check each case with no window. The view applies the answers to the engine.

## The frame cap of a window with focus: the rate of the simulation (`Clock.STEP`).
const FOCUSED_FPS := 60
## The frame cap of a minimized window. The simulation needs a frame now and then to step. A frame of a minimized window may count for
## MINIMIZED_MAX_FRAME seconds (the clock keeps up with real time), and the actors move on in pieces of COARSE_STEPS steps.
const MINIMIZED_FPS := 4
const MINIMIZED_MAX_FRAME := 0.5
const COARSE_STEPS := 6


## The frame cap for `Engine.max_fps`. 0 means no cap.
static func fps_cap(focused: bool, minimized: bool, unfocused_fps: int, focused_fps: int = FOCUSED_FPS) -> int:
	if minimized:
		return MINIMIZED_FPS
	if focused:
		return maxi(0, focused_fps)
	return maxi(0, unfocused_fps)


## True when the app draws. A minimized window shows nothing, so nothing is drawn.
static func should_draw(minimized: bool) -> bool:
	return not minimized
