class_name Starfield
extends GPUParticles3D
## The "Particle System" star field: box shape 1000^3, 1000 particles/s (max 10000),
## lifetime 15 s, colour (0.984, 0.992, 0.863), Default-Particle material
## ("Particles/Alpha Blended Premultiply").


func setup(star_size: float, twinkle: bool, world_space: bool) -> void:
	amount = 10000
	lifetime = 15.0
	explosiveness = 0.0
	local_coords = not world_space
	visibility_aabb = AABB(Vector3(-600, -600, -600), Vector3(1200, 1200, 1200))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(500, 500, 500)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.scale_min = star_size
	pm.scale_max = star_size
	pm.color = Color(0.984, 0.992, 0.863, 1.0)
	if twinkle:
		# in-game star field has a size-over-lifetime curve 0 -> 0.9 -> 0
		var c := Curve.new()
		c.add_point(Vector2(0.0, 0.00894))
		c.add_point(Vector2(0.49421, 0.90313))
		c.add_point(Vector2(0.99614, 0.00745))
		var ct := CurveTexture.new()
		ct.curve = c
		pm.scale_curve = ct
	process_material = pm
	var quad := QuadMesh.new()
	var m := ShaderMaterial.new()
	m.shader = A.shader("particle_premul")
	m.set_shader_parameter("tex", A.tex("Default-Particle"))
	m.render_priority = -2
	quad.material = m
	draw_pass_1 = quad
	emitting = true
