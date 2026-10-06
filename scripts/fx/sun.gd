class_name SunFX
extends Node3D
## The "Sun" object: red_star sphere with AnimateTiledTexture + Sun_Scale + three
## particle systems (Glow, Flares, Flares_big).

var frames_per_second := 15.0
var rot_speed := 2.0
var _mat: ShaderMaterial
var _index := 0
var _timer := 0.0
var _sphere: MeshInstance3D


func setup(scale_factor: float, fps: float, rotation_speed: float) -> void:
	frames_per_second = fps
	rot_speed = rotation_speed
	_sphere = MeshInstance3D.new()
	_sphere.mesh = A.mesh("sphere")
	_sphere.scale = Vector3.ONE * scale_factor
	_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = A.shader("sun")
	_mat.set_shader_parameter("tex", A.tex("star_red"))
	_sphere.material_override = _mat
	add_child(_sphere)
	_set_frame(0)

	# Sun_Scale multiplies the particle start sizes by the sun's scale; the shape
	# ("Shape" scaling mode) is scaled by the transform as well.
	add_child(_glow(scale_factor))
	add_child(_flares(scale_factor, 20.0, 2.0, Vector2(0.15, 0.3), 0.5, 0.01))
	add_child(_flares(scale_factor, 10.0, 3.0, Vector2(0.6, 1.0), 0.25, 0.0))


## Hide the sphere and particles (used for passthrough) but keep any attached light.
func set_visuals(v: bool) -> void:
	for c in get_children():
		if not (c is Light3D):
			c.visible = v


func _set_frame(i: int) -> void:
	var columns := 8
	var rows := 8
	var off := Vector2(float(i) / columns - float(i / columns), 1.0 - 1.0 / rows - float(i / columns) / rows)
	_mat.set_shader_parameter("tile_scale", Vector2(1.0 / columns, 1.0 / rows))
	_mat.set_shader_parameter("tile_offset", off)


func _process(delta: float) -> void:
	if frames_per_second > 0.0 and GameTime.time_scale > 0.0:
		_timer += delta
		var step := 1.0 / frames_per_second
		while _timer >= step:
			_timer -= step
			_index += 1
			if _index >= 64:
				_index = 0
			_set_frame(_index)
	# AnimateTiledTexture.Update: transform.Rotate(Vector3.up, rot_speed / 100) per frame (90 Hz)
	if rot_speed != 0.0:
		_sphere.rotate_y(-deg_to_rad(rot_speed / 100.0) * delta * GameTime.VIRTUAL_FPS)


func _fade_grad() -> GradientTexture1D:
	# alpha 0 -> 1 (0.326) -> 1 (0.703) -> 0, white
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.326, 0.703, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


func _glow(k: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 3
	p.lifetime = 3.0
	p.preprocess = 3.0
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3.ONE * -2.0 * k, Vector3.ONE * 4.0 * k)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.scale_min = 2.3 * k
	pm.scale_max = 2.3 * k
	pm.color_ramp = _fade_grad()
	p.process_material = pm
	var quad := QuadMesh.new()
	var m := ShaderMaterial.new()
	m.shader = A.shader("particle_add")
	m.set_shader_parameter("tex", A.tex("glow"))
	m.set_shader_parameter("tint", U.g2l_color(Color(1.0, 0.98, 0.265, 0.278)))
	m.render_priority = -1
	quad.material = m
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _flares(k: float, rate: float, lifetime: float, size: Vector2, radius: float, speed: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = int(rate * lifetime)
	p.lifetime = lifetime
	p.preprocess = 5.0
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3.ONE * -2.0 * k, Vector3.ONE * 4.0 * k)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = radius * k
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = speed
	pm.initial_velocity_max = speed
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.scale_min = size.x * k
	pm.scale_max = size.y * k
	var c := Curve.new()
	c.add_point(Vector2(0, 0))
	c.add_point(Vector2(1, 1))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	pm.color_ramp = _fade_grad()
	pm.anim_speed_min = 1.0
	pm.anim_speed_max = 1.0
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	p.process_material = pm
	var quad := QuadMesh.new()
	var m := ShaderMaterial.new()
	m.shader = A.shader("particle_add_flip")
	m.set_shader_parameter("tex", A.tex("torch_tint"))
	m.set_shader_parameter("tint", U.g2l_color(Color(1.0, 0.648, 0.544, 0.576)))
	m.set_shader_parameter("h_frames", 8)
	m.set_shader_parameter("v_frames", 8)
	quad.material = m
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
