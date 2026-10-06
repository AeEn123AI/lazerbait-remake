class_name ExplosionPool
extends Node3D
## The nine ClusterExplosion<Colour> prefabs (MasterController.particleSystems), rebuilt with
## Godot GPU particles from the values extracted from the original. Instances are pooled
## (the original instantiated one per dead ship and destroyed it after 5 s).

# MasterController.particleSystems order
const ORDER := ["white", "cyan", "red", "grey", "yellow", "orange", "pink", "green", "blue"]
const PREFAB_SCALE := 0.075 # ClusterExplosion root localScale
const POOL_PER_COLOR := 24
const LIGHT_TIME := 0.176 # lightScript fade (7 -> 0) at 90 fps

var _pools := {}      # index -> Array of entries
var _next := {}       # index -> int
var _lights: Array = [] # [light, t_remaining]


func _ready() -> void:
	var data := A.explosion_data()
	for i in ORDER.size():
		_pools[i] = []
		_next[i] = 0
		for k in POOL_PER_COLOR:
			_pools[i].append(_build(data[ORDER[i]]))


func _grad(d: Dictionary) -> GradientTexture1D:
	var g := Gradient.new()
	# Unity gradients have separate colour and alpha keys; sample both onto shared offsets.
	var offs := {}
	for c in d["grad_c"]:
		offs[float(c[0])] = true
	for a in d["grad_a"]:
		offs[float(a[0])] = true
	var keys := offs.keys()
	keys.sort()
	var colors := PackedColorArray()
	var offsets := PackedFloat32Array()
	for t in keys:
		var rgb := _sample_keys(d["grad_c"], t, 3)
		var al := _sample_keys(d["grad_a"], t, 1)
		offsets.append(t)
		colors.append(Color(rgb[0], rgb[1], rgb[2], al[0]))
	g.offsets = offsets
	g.colors = colors
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


func _sample_keys(keys: Array, t: float, n: int) -> Array:
	# keys: [[time, v0, (v1, v2)], ...]
	if t <= float(keys[0][0]):
		return keys[0].slice(1, 1 + n)
	if t >= float(keys[-1][0]):
		return keys[-1].slice(1, 1 + n)
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t >= float(a[0]) and t <= float(b[0]):
			var f := (t - float(a[0])) / maxf(1e-6, float(b[0]) - float(a[0]))
			var out := []
			for j in n:
				out.append(lerpf(float(a[1 + j]), float(b[1 + j]), f))
			return out
	return keys[-1].slice(1, 1 + n)


func _curve(points: Array, max_value := 1.0) -> CurveTexture:
	var c := Curve.new()
	c.max_value = max_value
	for p in points:
		c.add_point(Vector2(p[0], p[1]))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


func _rng(v: Variant) -> Vector2:
	if typeof(v) == TYPE_ARRAY:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2(float(v), float(v))


func _particles(amount: int, lifetime: float, explosiveness: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = explosiveness
	p.local_coords = false
	p.fixed_fps = 0
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _build(d: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.visible = false
	add_child(root)
	var s := PREFAB_SCALE

	# --- main: mesh particles (hyperbit_sphere), "Particles/Additive (Soft)" ---
	var m: Dictionary = d["main"]
	var lt := _rng(m["lifetime"])
	var main := _particles(11, lt.y, 0.45)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = float(m["radius"]) * s
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = float(m["speed"]) * s
	pm.initial_velocity_max = float(m["speed"]) * s
	pm.gravity = Vector3(0, -9.81 * float(m["gravity"]), 0)
	var sz := _rng(m["size"]) * s
	pm.scale_min = sz.x
	pm.scale_max = sz.y
	pm.scale_curve = _curve([[0.0, 7.0 * 0.2449], [1.0, 7.0]], 7.0)
	pm.color_ramp = _grad(m)
	pm.lifetime_randomness = 1.0 - lt.x / lt.y
	main.process_material = pm
	var mesh := A.mesh("hyperbit_sphere").duplicate() as Mesh
	var mm := ShaderMaterial.new()
	mm.shader = A.shader("particle_addsmooth_mesh")
	mm.set_shader_parameter("use_texture", false)
	mesh.surface_set_material(0, mm)
	main.draw_pass_1 = mesh
	root.add_child(main)

	# --- Glow: birth sub-emitter, one big soft glow per main particle ---
	var gd: Dictionary = d["glow"]
	var glow := _particles(11, float(gd["lifetime"]), 0.45)
	var gp := ParticleProcessMaterial.new()
	gp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	gp.emission_sphere_radius = float(m["radius"]) * s
	gp.direction = Vector3(0, 1, 0)
	gp.spread = 180.0
	gp.initial_velocity_min = float(gd["speed"]) * s
	gp.initial_velocity_max = float(gd["speed"]) * s
	gp.gravity = Vector3(0, -9.81 * float(gd["gravity"]), 0)
	var gsz := _rng(gd["size"]) * s
	gp.scale_min = gsz.x
	gp.scale_max = gsz.y
	gp.scale_curve = _curve([[0.0, 0.0], [1.0, 1.0]])
	var gg := _grad(gd)
	var sc: Array = gd["start_color"]
	_scale_alpha(gg, float(sc[3]))
	gp.color_ramp = gg
	glow.process_material = gp
	var quad := QuadMesh.new()
	var gm := ShaderMaterial.new()
	gm.shader = A.shader("particle_add")
	gm.set_shader_parameter("tex", A.tex("glow"))
	gm.set_shader_parameter("tint", U.g2l_color(Color(0.5, 0.5, 0.5, 0.5)))
	quad.material = gm
	glow.draw_pass_1 = quad
	root.add_child(glow)

	# --- GlowSphere: burst of 30 small sparks ---
	var sd: Dictionary = d["glowsphere"]
	var spark := _particles(30, _rng(sd["lifetime"]).y, 1.0)
	var sp := ParticleProcessMaterial.new()
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sp.emission_sphere_radius = 0.01 * s
	sp.direction = Vector3(0, 1, 0)
	sp.spread = 180.0
	var spd := _rng(sd["speed"]) * s
	sp.initial_velocity_min = spd.x
	sp.initial_velocity_max = spd.y
	sp.gravity = Vector3(0, -9.81 * float(sd["gravity"]), 0)
	# Limit Velocity Over Lifetime (0.1, dampen 0.06/frame) -> strong damping
	sp.damping_min = 10.0
	sp.damping_max = 14.0
	var ssz := _rng(sd["size"]) * s
	sp.scale_min = ssz.x
	sp.scale_max = ssz.y
	sp.scale_curve = _curve([[0.0, 1.0], [0.506, 1.0], [1.0, 0.306]])
	sp.color_ramp = _grad(sd)
	var slt := _rng(sd["lifetime"])
	sp.lifetime_randomness = 1.0 - slt.x / slt.y
	spark.process_material = sp
	var squad := QuadMesh.new()
	var sm := ShaderMaterial.new()
	sm.shader = A.shader("particle_add")
	sm.set_shader_parameter("tex", A.tex("shape_sphere"))
	sm.set_shader_parameter("tint", U.g2l_color(Color(0.5, 0.5, 0.5, 0.5)))
	squad.material = sm
	spark.draw_pass_1 = squad
	root.add_child(spark)

	# --- Point light with lightScript (intensity 7, fading out quickly) ---
	var ld: Dictionary = d["light"]
	var light := OmniLight3D.new()
	var lc: Array = ld["color"]
	light.light_color = Color(lc[0], lc[1], lc[2])
	light.omni_range = float(ld["range"])
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.visible = false
	root.add_child(light)

	return {"root": root, "parts": [main, glow, spark], "light": light, "t": 0.0}


func _scale_alpha(gt: GradientTexture1D, f: float) -> void:
	var g := gt.gradient
	var cols := g.colors
	for i in cols.size():
		cols[i].a *= f
	g.colors = cols


## Spawn the explosion with the given MasterController.particleSystems index at a world position.
func spawn(index: int, pos: Vector3) -> void:
	if not _pools.has(index):
		return
	var pool: Array = _pools[index]
	var e: Dictionary = pool[_next[index]]
	_next[index] = (_next[index] + 1) % pool.size()
	var root: Node3D = e["root"]
	root.global_position = pos
	root.visible = true
	for p in root.get_children():
		if p is GPUParticles3D or p is CPUParticles3D:
			p.restart()
	var light: OmniLight3D = e["light"]
	light.visible = true
	light.light_energy = 7.0
	e["t"] = LIGHT_TIME
	if not _lights.has(e):
		_lights.append(e)


func _process(delta: float) -> void:
	var i := 0
	while i < _lights.size():
		var e: Dictionary = _lights[i]
		e["t"] -= delta
		var light: OmniLight3D = e["light"]
		if e["t"] <= 0.0:
			light.visible = false
			light.light_energy = 0.0
			_lights.remove_at(i)
			continue
		light.light_energy = 7.0 * e["t"] / LIGHT_TIME
		i += 1
