extends Node
## Decides between VR (OpenXR) and desktop mode, and manages optional passthrough.
##
## VR is used when an OpenXR runtime + headset are available.
## Force desktop with the command line argument `--desktop` (or Godot's `--xr-mode off`).

signal passthrough_changed(active: bool)
signal vr_session_started

var vr := false
var xr_interface: XRInterface = null
var passthrough_active := false
var _session_running := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var force_desktop := args.has("--desktop") or args.has("--no-vr")
	xr_interface = XRServer.find_interface("OpenXR")
	if args.has("--xr-test"):
		# Development: exercise the VR code path without a headset (Godot's mobile VR interface).
		var mobile := XRServer.find_interface("Native mobile")
		if mobile and mobile.initialize():
			xr_interface = mobile
	if xr_interface and xr_interface.is_initialized() and not force_desktop:
		vr = true
		get_viewport().use_xr = true
		# The compositor paces frames in VR; vsync would only add latency.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		if xr_interface.has_signal("session_begun"):
			xr_interface.connect("session_begun", _on_session_begun)
		if xr_interface.has_signal("session_stopping"):
			xr_interface.connect("session_stopping", func(): _session_running = false)
		if xr_interface.has_signal("pose_recentered"):
			xr_interface.connect("pose_recentered", _on_pose_recentered)
		print("[Lazerbait] VR mode (OpenXR)")
	else:
		if xr_interface and xr_interface.is_initialized():
			xr_interface.uninitialize()
		vr = false
		if OS.has_feature("android") and not force_desktop:
			# On Android a standalone headset only runs in VR when the export preset's
			# "XR Mode" is "OpenXR". If the OpenXR interface is missing here, the build was
			# exported with XR Mode = Regular (or without the OpenXR loader), so Godot runs flat.
			push_warning("OpenXR interface unavailable on Android; exporting with XR Mode = OpenXR is required for VR.")
			print("[Lazerbait] Desktop mode (Android: set export preset XR Mode to OpenXR for VR)")
		else:
			print("[Lazerbait] Desktop mode")


## The user recentered from the system (e.g. holding the Meta button on Quest).
## With the Stage reference space the runtime doesn't move the play space itself, so we
## re-centre on the headset: horizontal position and facing only, keeping the real floor height.
func _on_pose_recentered() -> void:
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	print("[Lazerbait] recentered on headset")


func _on_session_begun() -> void:
	_session_running = true
	# Match physics rate to the headset refresh rate where possible.
	var rr := 0.0
	if xr_interface.has_method("get_display_refresh_rate"):
		rr = xr_interface.get_display_refresh_rate()
	if rr > 0.0:
		Engine.physics_ticks_per_second = int(rr)
	apply_passthrough(Settings.passthrough)
	vr_session_started.emit()


## True if this device/runtime can show passthrough at all.
func passthrough_supported() -> bool:
	if not vr or xr_interface == null:
		return false
	var modes: Array = xr_interface.get_supported_environment_blend_modes()
	if modes.has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
		return true
	return xr_interface.is_passthrough_supported()


## Enables/disables passthrough. Returns whether passthrough is now active.
func apply_passthrough(enable: bool) -> bool:
	var active := false
	if vr and xr_interface:
		var modes: Array = xr_interface.get_supported_environment_blend_modes()
		if enable:
			if modes.has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
				active = xr_interface.set_environment_blend_mode(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND)
			if not active and xr_interface.is_passthrough_supported():
				active = xr_interface.start_passthrough()
		else:
			if xr_interface.is_passthrough_enabled():
				xr_interface.stop_passthrough()
			if modes.has(XRInterface.XR_ENV_BLEND_MODE_OPAQUE):
				xr_interface.set_environment_blend_mode(XRInterface.XR_ENV_BLEND_MODE_OPAQUE)
	get_viewport().transparent_bg = active
	if active != passthrough_active:
		passthrough_active = active
		passthrough_changed.emit(active)
	else:
		passthrough_active = active
	return active


func session_running() -> bool:
	return _session_running
