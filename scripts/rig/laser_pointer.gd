class_name LaserPointer
extends Node3D
## Port of the (modified) SteamVR_LaserPointer: a thin cube beam with a sphere at its tip.
## Red normally, green (and shortened) when something is hit within `distance`.

var thickness := 0.002
var distance := 100.0
var rig: PlayerRig
var hand: Hand
var _pointer: MeshInstance3D
var _sphere: MeshInstance3D
var _mat: StandardMaterial3D


func setup(p_rig: PlayerRig, p_hand: Hand, p_thickness: float, p_distance: float) -> void:
	rig = p_rig
	hand = p_hand
	thickness = p_thickness
	distance = p_distance
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color.RED
	_pointer = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	_pointer.mesh = bm
	_pointer.material_override = _mat
	_pointer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pointer)
	_sphere = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 12
	sm.rings = 6
	_sphere.mesh = sm
	_sphere.material_override = _mat
	_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sphere.scale = Vector3.ONE * thickness * 4.0
	add_child(_sphere)


func _process(_d: float) -> void:
	if rig == null:
		return
	var s := rig.scale_factor()
	var num := distance * 10.0 / s
	var origin := global_position
	var dir := -global_transform.basis.z
	var hit := Picker.raycast(origin, dir)
	if not hit.is_empty() and float(hit["distance"]) < distance:
		num = float(hit["distance"]) / s * 10.0
		_mat.albedo_color = Color.GREEN
	else:
		_mat.albedo_color = Color.RED
	var t := thickness * 2.0 if hand.trigger_pressed else thickness
	_pointer.scale = Vector3(t, t, num)
	_pointer.position = Vector3(0, 0, -num / 2.0)
	_sphere.position = Vector3(0, 0, -num)
