extends Node
## Emulates the parts of Unity's Time class the original game relied on.
##
## * time_scale        -> Time.timeScale (the game pauses by setting it to 0)
## * time / delta      -> Time.time / Time.deltaTime (scaled)
## * realtime()        -> Time.realtimeSinceStartup
## * frame_count       -> Time.frameCount. The original ran on a 90 Hz Vive and has
##                        lots of "every N frames" logic, so we advance a *virtual*
##                        90 Hz frame counter, keeping that logic refresh-rate independent.

const VIRTUAL_FPS := 90.0

var time_scale := 1.0
var time := 0.0
var delta := 0.0
var unscaled_delta := 0.0
var frame_count := 0
var prev_frame_count := 0

var _start_usec := 0
var debug_speed := 1.0 # testing only (Debug --timescale)


func _ready() -> void:
	process_priority = -1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_usec = Time.get_ticks_usec()


func realtime() -> float:
	return float(Time.get_ticks_usec() - _start_usec) / 1000000.0 * debug_speed


func _process(d: float) -> void:
	d *= debug_speed
	unscaled_delta = d
	delta = d * time_scale
	time += delta
	prev_frame_count = frame_count
	frame_count = int(realtime() * VIRTUAL_FPS)
	if frame_count == prev_frame_count:
		# at > 90 Hz several real frames share a virtual frame; that's fine,
		# "every N frames" checks use crossed() below.
		pass


## True if the virtual frame counter crossed a multiple of n during this real frame
## (equivalent of `Time.frameCount % n == 0` being hit once).
func crossed(n: int) -> bool:
	return int(frame_count / n) != int(prev_frame_count / n)


func paused() -> bool:
	return time_scale == 0.0
