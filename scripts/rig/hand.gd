class_name Hand
extends Node3D
## One controller, abstracted over VR (XRController3D) and desktop (mouse/keyboard emulation).
## Mirrors the SteamVR_TrackedController fields the original scripts used.

var is_left := false
var is_vr := false
var controller: XRController3D = null   # VR only
## Everything the original parented under "Controller (left/right)" goes under `ui`,
## which is scaled by the rig scale exactly like the SteamVR [CameraRig] children were.
var ui: Node3D
var rig # PlayerRig

# --- SteamVR_TrackedController state ---
var trigger_pressed := false
var pad_pressed := false
var pad_touched := false
var menu_pressed := false
var gripped := false
var pad_axis := Vector2.ZERO

# desktop emulation
var _synthetic: Array = []   # queued [touched, pressed, axis] states (percent keys)
var desktop_trigger := false
var desktop_pad_latched := false
var desktop_menu_click := false
var _desktop_menu_frames := 0


func setup(p_rig, left: bool, vr: bool) -> void:
	rig = p_rig
	is_left = left
	is_vr = vr
	ui = Node3D.new()
	ui.name = "UI"
	add_child(ui)


## Called every frame by the rig before levels update.
func poll() -> void:
	if is_vr and controller:
		var c := controller
		trigger_pressed = c.get_float("trigger") > 0.55 or c.is_button_pressed("trigger_click")
		gripped = c.get_float("grip") > 0.55 or c.is_button_pressed("grip_click")
		pad_axis = c.get_vector2("primary")
		pad_touched = c.is_button_pressed("primary_touch") or pad_axis.length() > 0.08
		pad_pressed = c.is_button_pressed("primary_click")
		if is_left:
			# Vive: left trackpad click. Other controllers: X / Y as well.
			pad_pressed = pad_pressed or c.is_button_pressed("ax_button") or c.is_button_pressed("by_button")
			menu_pressed = c.is_button_pressed("menu_button")
		else:
			menu_pressed = c.is_button_pressed("menu_button") or c.is_button_pressed("by_button")
		var s: float = rig.scale_factor()
		ui.scale = Vector3.ONE * s
	else:
		trigger_pressed = desktop_trigger
		gripped = false
		menu_pressed = _desktop_menu_frames > 0
		if _desktop_menu_frames > 0:
			_desktop_menu_frames -= 1
		if is_left:
			pad_pressed = desktop_pad_latched
			pad_touched = false
		else:
			if _synthetic.size() > 0:
				var st: Array = _synthetic.pop_front()
				pad_touched = st[0]
				pad_pressed = st[1]
				pad_axis = st[2]
			else:
				pad_touched = false
				pad_pressed = false
		ui.scale = Vector3.ONE * float(rig.scale_factor())


## Desktop: pick a percentage quadrant (1..4 = 25/50/75/100%) as if touching + clicking the pad.
func desktop_select_percent(q: int) -> void:
	var axis := Vector2.ZERO
	match q:
		1: axis = Vector2(-0.6, -0.6)
		2: axis = Vector2(-0.6, 0.6)
		3: axis = Vector2(0.6, 0.6)
		4: axis = Vector2(0.6, -0.6)
	_synthetic = [[true, true, axis], [true, true, axis], [true, false, axis], [false, false, axis]]


func desktop_press_menu() -> void:
	_desktop_menu_frames = 2


## Unity: controller.transform.localPosition (relative to the [CameraRig], in rig units = metres).
func rig_local_position() -> Vector3:
	return rig.to_rig_local(global_position)


## SteamVR_Controller.TriggerHapticPulse loop (ClickHandler.LongVibration).
func vibrate(length: float, strength: float) -> void:
	if not is_vr or controller == null:
		return
	if length <= 0.0 or strength <= 0.0:
		return
	controller.trigger_haptic_pulse("haptic", 0.0, clampf(strength, 0.0, 1.0), maxf(length, 0.01), 0.0)


## World-space ray used for pointing (the LaserHolder transform in VR, the mouse ray on desktop).
func pointer_origin() -> Vector3:
	if is_vr:
		return global_position
	return rig.mouse_ray_origin()


func pointer_dir() -> Vector3:
	if is_vr:
		return -global_transform.basis.z
	return rig.mouse_ray_dir()
