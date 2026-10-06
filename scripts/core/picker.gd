class_name Picker
## Minimal replacement for the Unity colliders that the laser pointers raycast against
## (Physics.Raycast / RaycastAll). Triggers are not included: the original project had
## queriesHitTriggers = false, so ships were never hit by rays.

class Col:
	var node: Node3D
	var shape := "sphere"     # "sphere" | "box"
	var radius := 0.5         # sphere radius (local units, Unity SphereCollider.radius)
	var size := Vector3.ONE   # box size (local units)
	var center := Vector3.ZERO
	var enabled := true
	var tag := ""
	var name := ""
	var owner: Object = null

	func world_hit(origin: Vector3, dir: Vector3, max_dist: float) -> float:
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			return -1.0
		var gt := node.global_transform
		if shape == "sphere":
			var b := gt.basis
			var s := maxf(b.x.length(), maxf(b.y.length(), b.z.length()))
			var c := gt * center
			var r := radius * s
			var oc := origin - c
			var bq := oc.dot(dir)
			var cq := oc.length_squared() - r * r
			if cq <= 0.0:
				return -1.0 # ray starts inside: Unity doesn't report a hit
			var disc := bq * bq - cq
			if disc < 0.0:
				return -1.0
			var t := -bq - sqrt(disc)
			if t < 0.0 or t > max_dist:
				return -1.0
			return t
		else:
			var inv := gt.affine_inverse()
			var lo := inv * origin
			var ld := inv.basis * dir
			var half := size * 0.5
			var bmin := center - half
			var bmax := center + half
			var tmin := -INF
			var tmax := INF
			for i in 3:
				if absf(ld[i]) < 1e-12:
					if lo[i] < bmin[i] or lo[i] > bmax[i]:
						return -1.0
				else:
					var t1 := (bmin[i] - lo[i]) / ld[i]
					var t2 := (bmax[i] - lo[i]) / ld[i]
					if t1 > t2:
						var tt := t1
						t1 = t2
						t2 = tt
					tmin = maxf(tmin, t1)
					tmax = minf(tmax, t2)
					if tmin > tmax:
						return -1.0
			if tmin < 0.0:
				return -1.0 # inside the box
			var hit_local := lo + ld * tmin
			var dist := (gt * hit_local - origin).length()
			if dist > max_dist:
				return -1.0
			return dist


static var colliders: Array[Col] = []


static func clear() -> void:
	colliders.clear()


static func add_sphere(node: Node3D, radius: float, tag := "", owner: Object = null, name := "") -> Col:
	var c := Col.new()
	c.node = node
	c.shape = "sphere"
	c.radius = radius
	c.tag = tag
	c.owner = owner
	c.name = name if name != "" else String(node.name)
	colliders.append(c)
	return c


static func add_box(node: Node3D, size: Vector3, center := Vector3.ZERO, tag := "", owner: Object = null, name := "") -> Col:
	var c := Col.new()
	c.node = node
	c.shape = "box"
	c.size = size
	c.center = center
	c.tag = tag
	c.owner = owner
	c.name = name if name != "" else String(node.name)
	colliders.append(c)
	return c


static func remove(c: Col) -> void:
	colliders.erase(c)


## Physics.RaycastAll: every enabled collider hit within max_dist, nearest first.
static func raycast_all(origin: Vector3, dir: Vector3, max_dist: float) -> Array:
	var d := dir.normalized()
	var hits := []
	for c in colliders:
		if not c.enabled:
			continue
		var t := c.world_hit(origin, d, max_dist)
		if t >= 0.0:
			hits.append({"col": c, "distance": t, "point": origin + d * t})
	hits.sort_custom(func(a, b): return a["distance"] < b["distance"])
	return hits


## Physics.Raycast: nearest hit or empty dictionary.
static func raycast(origin: Vector3, dir: Vector3, max_dist := INF) -> Dictionary:
	var h := raycast_all(origin, dir, max_dist)
	return h[0] if h.size() > 0 else {}
