class_name U
## Unity (left-handed, +Z forward) -> Godot (right-handed, -Z forward) conversions.
## Positions mirror Z; quaternions (x,y,z,w) become (-x,-y,z,w); scales are unchanged.
## All transform data copied from the original scenes goes through these helpers so the
## layout matches the original exactly.


static func v(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, -z)


static func q(x: float, y: float, z: float, w: float) -> Quaternion:
	return Quaternion(-x, -y, z, w).normalized()


## Unity Quaternion.Euler(x, y, z) (applied Z, then X, then Y), converted to Godot.
static func euler(x: float, y: float, z: float) -> Quaternion:
	var qx := Quaternion(Vector3(1, 0, 0), deg_to_rad(x))
	var qy := Quaternion(Vector3(0, 1, 0), deg_to_rad(y))
	var qz := Quaternion(Vector3(0, 0, 1), deg_to_rad(z))
	var uq := qy * qx * qz # Unity-space quaternion (same algebra, different handedness)
	return Quaternion(-uq.x, -uq.y, uq.z, uq.w)


## Build a Godot Transform3D from Unity TRS (raw Unity numbers).
static func trs(pos: Vector3, rot: Quaternion, scl := Vector3.ONE) -> Transform3D:
	var gq := Quaternion(-rot.x, -rot.y, rot.z, rot.w).normalized()
	var b := Basis(gq) * Basis.from_scale(scl)
	return Transform3D(b, Vector3(pos.x, pos.y, -pos.z))


## Apply a Unity TRS (raw Unity numbers) to a node as its local transform.
static func place(n: Node3D, pos: Vector3, rot := Quaternion.IDENTITY, scl := Vector3.ONE) -> void:
	n.transform = trs(pos, rot, scl)


## Unity Color32 packed as 0xAABBGGRR (as stored in serialized TextMesh colours).
static func rgba32(packed: int) -> Color:
	return Color8(packed & 255, (packed >> 8) & 255, (packed >> 16) & 255, (packed >> 24) & 255)


## Unity Mathf.GammaToLinearSpace for single values (used where Unity converted HDR material colours).
static func g2l(c: float) -> float:
	if c <= 0.04045:
		return c / 12.92
	return pow((c + 0.055) / 1.055, 2.4)


static func g2l_color(c: Color) -> Color:
	return Color(g2l(c.r), g2l(c.g), g2l(c.b), c.a)


## Unity's Color == (Vector4 approximate equality).
static func color_eq(a: Color, b: Color) -> bool:
	var d := Vector4(a.r - b.r, a.g - b.g, a.b - b.b, a.a - b.a)
	return d.length_squared() < 9.99999944e-11


## Unity Random.onUnitSphere
static func on_unit_sphere() -> Vector3:
	var z := randf() * 2.0 - 1.0
	var t := randf() * TAU
	var r := sqrt(1.0 - z * z)
	return Vector3(r * cos(t), r * sin(t), z)


## Unity Vector3.MoveTowards
static func move_towards(current: Vector3, target: Vector3, max_delta: float) -> Vector3:
	var d := target - current
	var m := d.length()
	if m <= max_delta or m == 0.0:
		return target
	return current + d / m * max_delta


## Unity Transform.LookAt semantics (no change when the direction is zero).
static func look_basis(from: Vector3, target: Vector3, up := Vector3.UP, current := Basis.IDENTITY) -> Basis:
	var dir := target - from
	if dir.length_squared() < 1e-12:
		return current
	if absf(dir.normalized().dot(up.normalized())) > 0.9999:
		up = Vector3(0, 0, 1) if absf(dir.normalized().z) < 0.9 else Vector3(1, 0, 0)
	return Basis.looking_at(dir, up)
