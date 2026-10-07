class_name ControllerModel
extends Node3D
## Shows a model of the controller the player is actually holding (SteamVR_RenderModel equivalent).
##
## Sources, best first:
##  1. Meta's own controller meshes via XR_FB_render_model (OpenXRFbRenderModel, vendors plugin):
##     Quest 2 / 3 / Pro controllers.
##  2. Godot core XR_EXT_render_model (OpenXRRenderModelManager): SteamVR and other runtimes.
##  3. A procedural stand-in shaped after the active interaction profile (Touch-style or Vive wand).
##
## Must be placed under an XRController3D using the "grip" pose (both render model APIs are
## defined relative to the grip pose). PlayerRig sets this node's scale to the world scale.

var is_left := false
var tracker_name := &""
var _fb: Node3D = null
var _ext: Node3D = null
var _fallback: Node3D = null
var _fallback_kind := ""
var _have_real_model := false


func setup(left: bool) -> void:
	is_left = left
	tracker_name = &"left_hand" if left else &"right_hand"
	# 1) Meta render models (needs xr/openxr/extensions/meta/render_model and, on Quest,
	#    the export preset's meta_xr_features/render_model permission)
	if ClassDB.class_exists("OpenXRFbRenderModel") and ProjectSettings.get_setting("xr/openxr/extensions/meta/render_model", false):
		_fb = ClassDB.instantiate("OpenXRFbRenderModel")
		_fb.name = "MetaRenderModel"
		_fb.set("render_model_type", 0 if left else 1) # MODEL_CONTROLLER_LEFT / RIGHT
		add_child(_fb)
		if _fb.has_signal("openxr_fb_render_model_loaded"):
			_fb.connect("openxr_fb_render_model_loaded", _on_real_model_loaded)
	# 2) XR_EXT_render_model
	if ClassDB.class_exists("OpenXRRenderModelManager"):
		_ext = ClassDB.instantiate("OpenXRRenderModelManager")
		_ext.name = "RenderModelManager"
		_ext.set("tracker", 2 if left else 3) # RENDER_MODEL_TRACKER_LEFT_HAND / RIGHT_HAND
		_ext.set("make_local_to_pose", "grip")
		add_child(_ext)
		_ext.child_entered_tree.connect(func(_n): _on_real_model_loaded())
	# 3) procedural stand-in until / unless a real model arrives
	_set_fallback(_guess_kind(""))
	var t := XRServer.get_tracker(tracker_name)
	if t:
		_connect_tracker(t)
	XRServer.tracker_added.connect(_on_tracker_added)


func _on_tracker_added(tname: StringName, _type: int) -> void:
	if tname == tracker_name:
		_connect_tracker(XRServer.get_tracker(tname))


func _connect_tracker(t: XRTracker) -> void:
	if t is XRPositionalTracker:
		var pt := t as XRPositionalTracker
		if not pt.profile_changed.is_connected(_on_profile_changed):
			pt.profile_changed.connect(_on_profile_changed)
		_on_profile_changed(pt.profile)


func _on_profile_changed(profile: String) -> void:
	_set_fallback(_guess_kind(profile))


func _on_real_model_loaded() -> void:
	_have_real_model = true
	if _fallback:
		_fallback.visible = false
	# Prefer Meta's model if both APIs produced one.
	if _fb and _ext and _fb.has_method("has_render_model_node") and _fb.call("has_render_model_node"):
		_ext.visible = false


static func _guess_kind(profile: String) -> String:
	var p := profile.to_lower()
	if p.contains("vive_controller") or p.contains("htc/vive"):
		return "wand"
	if p == "":
		# Before the runtime reports a profile: standalone headsets are Touch-like.
		return "touch" if OS.has_feature("android") else "wand"
	return "touch"


func _set_fallback(kind: String) -> void:
	if kind == _fallback_kind:
		return
	_fallback_kind = kind
	if _fallback:
		_fallback.queue_free()
	_fallback = _build_touch() if kind == "touch" else _build_wand()
	_fallback.name = "Fallback"
	_fallback.visible = not _have_real_model
	add_child(_fallback)


# ---------------------------------------------------------------- procedural models
# OpenXR grip pose space (metres): origin in the middle of the handle, -Z the direction
# the fist points, +Y up, +X right.

static func _mat(c: Color, metallic := 0.1, rough := 0.55) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = rough
	return m


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


## Touch / Touch Plus style: a handle with a flat face holding the thumbstick and two buttons.
func _build_touch() -> Node3D:
	var n := Node3D.new()
	var s := -1.0 if is_left else 1.0 # mirror for the left hand
	var body := _mat(Color(0.12, 0.12, 0.13))
	var face := _mat(Color(0.06, 0.06, 0.065), 0.0, 0.35)
	var light := _mat(Color(0.82, 0.82, 0.84), 0.0, 0.4)
	var cap := CapsuleMesh.new()
	cap.radius = 0.018
	cap.height = 0.105
	_mesh(n, cap, body, Vector3(0, -0.005, 0.012), Vector3(-25, 0, 0))
	var head := CylinderMesh.new()
	head.top_radius = 0.033
	head.bottom_radius = 0.034
	head.height = 0.022
	head.radial_segments = 32
	_mesh(n, head, body, Vector3(0.004 * s, 0.03, -0.028), Vector3(-20, 0, 0), Vector3(1.0, 1.0, 0.82))
	var plate := CylinderMesh.new()
	plate.top_radius = 0.03
	plate.bottom_radius = 0.03
	plate.height = 0.002
	plate.radial_segments = 32
	_mesh(n, plate, face, Vector3(0.004 * s, 0.041, -0.024), Vector3(-20, 0, 0), Vector3(1.0, 1.0, 0.82))
	var stick := CylinderMesh.new()
	stick.top_radius = 0.009
	stick.bottom_radius = 0.004
	stick.height = 0.012
	_mesh(n, stick, light, Vector3(-0.009 * s, 0.047, -0.018), Vector3(-20, 0, 0))
	var btn := CylinderMesh.new()
	btn.top_radius = 0.0055
	btn.bottom_radius = 0.0055
	btn.height = 0.004
	_mesh(n, btn, light, Vector3(0.012 * s, 0.044, -0.03), Vector3(-20, 0, 0))
	_mesh(n, btn, light, Vector3(0.016 * s, 0.045, -0.016), Vector3(-20, 0, 0))
	var trig := BoxMesh.new()
	trig.size = Vector3(0.016, 0.012, 0.024)
	_mesh(n, trig, body, Vector3(0, 0.008, -0.046), Vector3(-45, 0, 0))
	return n


## HTC Vive wand (what the original game was designed around).
func _build_wand() -> Node3D:
	var n := Node3D.new()
	var mat := _mat(Color(0.08, 0.08, 0.09), 0.2, 0.45)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.017
	cyl.bottom_radius = 0.02
	cyl.height = 0.15
	_mesh(n, cyl, mat, Vector3(0, -0.01, 0.02), Vector3(-75, 0, 0))
	var tor := TorusMesh.new()
	tor.inner_radius = 0.022
	tor.outer_radius = 0.035
	_mesh(n, tor, mat, Vector3(0, 0.03, -0.07), Vector3(65, 0, 0))
	var pad := CylinderMesh.new()
	pad.top_radius = 0.016
	pad.bottom_radius = 0.016
	pad.height = 0.002
	_mesh(n, pad, _mat(Color(0.03, 0.03, 0.03)), Vector3(0, 0.014, -0.03), Vector3(-15, 0, 0))
	return n
