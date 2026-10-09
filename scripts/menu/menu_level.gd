class_name MenuLevel
extends Node3D
## The "startMenu" scene: MenuMaster + MenuClickHandler + MovieTexturePlayer + stats texts.

const AI_TEXT := ["A.I. is Easy", "A.I. is Medium", "A.I. is Hard", "A.I. is Cheating"]
const PLANET_TEXT := ["Map Size: Small", "Map Size: Med", "Map Size: Large", "Map Size: Huge"]
# MenuMaster serialized values
const STARTING_NUMBER := 40
const STARTING_SPEED := 1
const SHIP_SCALE := 0.6
const SHIP_RADIUS := 0.15
# MenuClickHandler.startingSpeed (its own field, not copied from MenuMaster)
const CLICK_STARTING_SPEED := 1
const TUTORIAL_SCALE_DOWN := 0.3
const TUTORIAL_SCALE_UP := 0.32
const MENU_COLORS := [
	Color(0, 1, 1, 1), Color(1, 0, 0, 1) / 1.5, Color(0.4, 0.4, 0.4, 1), Color(1, 0.92156863, 0.015686275, 1),
	Color(0, 1, 0, 1), Color(1, 0, 1, 1), Color(0, 0, 1, 1), Color(1, 0.5, 0, 1)]

var main # Main
var rig: PlayerRig
var env: Environment
var sun: SunFX
var light: DirectionalLight3D
var starfield: Starfield

var planets := {}            # label -> PlanetController
var ai_text: Label3D
var planets_text: Label3D
var graphics_text: Label3D
var passthrough_text: Label3D
var performance_warning: Label3D
var counters_text: Label3D
var leader_texts := {}       # board key -> Label3D
var tutorials := {}          # name -> MeshInstance3D
var tv: MeshInstance3D
var tv_mat: StandardMaterial3D
var video: VideoStreamPlayer
var music: AudioStreamPlayer
var ambient: AudioStreamPlayer
var _sfx: AudioStreamPlayer

# menu ships
class MenuShip:
	var custom_tag := ""
	var pos := Vector3.ZERO
	var basis := Basis.IDENTITY
	var scale := 1.0
	var color := Color.WHITE
	var planet_pos := Vector3.ZERO
	var rotational_speed := 50.0
	var translational_speed := 1.0
	var visible := false
	var previous := Vector3.ZERO
	var cached := Vector3.ZERO
	var prev_time := 0.0
	var p1 := Vector3.ZERO
	var p2 := Vector3.ZERO
	var p3 := Vector3.ZERO
	var velocity := Vector3.ZERO

var ships: Array = []
var _ship_mm: MultiMeshInstance3D
var _colliding: PlanetController = null
var _trigger_unpressed := true
var _left_click := false
var _first_stats := false
var _movie_index := -1
var _movie_paused := false
var _has_been_played := false
var _videos: Array = []
var _leaving := false

# versus (network) panel - remake addition
var net_host_text: Label3D
var net_join_text: Label3D
var net_next_text: Label3D
var net_status_text: Label3D
var _host_index := 0
var _address_box: LineEdit


func setup(p_main, p_rig: PlayerRig) -> void:
	main = p_main
	rig = p_rig
	Picker.clear()
	GameTime.time_scale = 1.0
	rig.set_scale_factor(1.0)
	rig.set_rig_position(Vector3.ZERO)
	_build_environment()
	_build_world()
	_build_audio()
	# MenuClickHandler.Start
	Settings.clear_menu_settings()
	Settings.load_settings()
	ai_text.text = AI_TEXT[Settings.ai_settings_count]
	planets_text.text = PLANET_TEXT[Settings.planet_settings_count]
	graphics_text.text = "Graphics = " + Settings.QUALITY_NAMES[Settings.quality_index]
	_update_passthrough_text()
	main.apply_quality(light)
	performance_warning.visible = Settings.ship_setting_count == 3
	_late_init_ships()
	_build_net_panel()
	if rig.vr:
		var lp := LaserPointer.new()
		rig.right.ui.add_child(lp)
		lp.setup(rig, rig.right, 0.0006, 100.0)
	else:
		for h in [rig.left, rig.right]:
			var model: Node3D = h.ui.get_node_or_null("Model")
			if model:
				model.visible = false
		rig.allow_vertical = false
		rig.content_fixed = true
		rig.content.global_transform = Transform3D.IDENTITY
		rig.desktop_move_speed = 1.5
		rig.set_desktop_yaw_pitch(0.0, deg_to_rad(-8.0))
		if rig.touch:
			rig.set_touch_layout("menu")
		if rig.touch:
			rig.set_help_text("Tap: click planets / tutorials   Two fingers: look around, pinch: move\nVersus: the panel behind you on the left   Join: enter a host address")
		else:
			rig.set_help_text("LMB: click planets / tutorials   RMB drag: look around   WASD: move   F11: fullscreen   H: hide help\n" +
				"Versus: the panel behind you on the left   J: join a game by address")
	XRManager.passthrough_changed.connect(_on_passthrough_changed)
	_on_passthrough_changed(XRManager.passthrough_active)


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07494, 0.07725, 0.08088) # Camera (eye) solid colour
	# Ambient: Flat (1.04, 1.04, 1.05). No skybox -> no reflections.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.993, 0.995, 1.0)
	env.ambient_light_energy = 1.05
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _menu_planet(label: String, pos: Vector3, scl: float, radius: float) -> PlanetController:
	var p := PlanetController.new()
	p.name = "menuPlanet_" + label
	p.menu_label = label
	U.place(p, pos, Quaternion.IDENTITY, Vector3.ONE * scl)
	rig.content.add_child(p)
	p.build(false, Color(0, 0.192, 0.287, 1), radius, "menuPlanet")
	p.start()
	planets[label] = p
	return p


func _build_world() -> void:
	var c := rig.content
	var w := Color.WHITE
	# Sun
	sun = SunFX.new()
	add_child(sun)
	U.place(sun, Vector3(0.043, 1.095, -409.6))
	sun.setup(100.0, 15.0, 2.0)
	Picker.add_sphere(sun._sphere, 0.5, "", null, "Sun")
	# Directional light
	light = DirectionalLight3D.new()
	U.place(light, Vector3(0.045, 0.433, -0.071))
	var lc: Array = main.unity_light(Color(0.96324, 0.85656, 0.66577), 2.98)
	light.light_color = lc[0]
	light.light_energy = lc[1]
	light.shadow_enabled = true
	light.shadow_bias = 0.001
	light.shadow_normal_bias = 0.002
	add_child(light)
	# platform
	var plane := MeshInstance3D.new()
	plane.mesh = A.mesh("cylinder")
	var pm := StandardMaterial3D.new()
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.albedo_color = Color(0.051, 0.192, 0.243, 1)
	pm.albedo_texture = A.tex("geo_pattern_albedo")
	pm.uv1_scale = Vector3(10, 10, 1)
	pm.metallic = 0.25
	pm.roughness = 0.5
	plane.material_override = pm
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	U.place(plane, Vector3.ZERO, Quaternion.IDENTITY, Vector3(3, 0.01, 3))
	c.add_child(plane)
	# menu planets
	_menu_planet("start", Vector3(0.045, 1.604, 1.809), 0.5, 0.5)
	_menu_planet("NumberOfPlayers", Vector3(-1.421, 0.5, 1.402), 0.2, 0.4)
	_menu_planet("GameSpeed", Vector3(-1.421, 1, 1.402), 0.2, 0.4)
	_menu_planet("NumberOfShips", Vector3(-1.421, 1.5, 1.402), 0.2, 0.4)
	_menu_planet("PlayerColor", Vector3(1.332, 1.5, 1.402), 0.2, 0.4)
	_menu_planet("AI", Vector3(1.332, 1.001, 1.402), 0.2, 0.4)
	_menu_planet("PlanetCount", Vector3(1.332, 0.552, 1.402), 0.2, 0.4)
	_menu_planet("Quality", Vector3(0.026, 0.736, 1.809), 0.2, 0.7)
	# remake addition: optional passthrough (mixed reality) toggle, in the unused "help" slot area
	_menu_planet("Passthrough", Vector3(0.026, 0.42, 1.809), 0.2, 0.7)
	# texts
	var roty_l := Quaternion(0, -0.1305, 0, 0.9914)
	var roty_r := Quaternion(0, 0.1305, 0, 0.9914)
	var s8 := Vector3(0.008, 0.008, 0.008)
	UI3D.make(c, "Start\n", "pixel", 1.8, 100, 0, w, Vector3(-0.188, 2.127, 1.809), Quaternion.IDENTITY, Vector3(0.02, 0.02, 0.1))
	UI3D.make(c, "Lazerbait", "logo", 100, 100, 0, U.rgba32(4278190247), Vector3(-2.186, 1.834, -0.868), Quaternion(0, -0.7071, 0, 0.7071), Vector3(0.0005, 0.0005, 0.05))
	UI3D.make(c, "Number of ships", "pixel", 1.8, 100, 0, w, Vector3(-1.225, 1.575, 1.525), roty_l, s8)
	UI3D.make(c, "   Ship Speed", "pixel", 1.8, 100, 0, w, Vector3(-1.286, 1.075, 1.525), roty_l, s8)
	UI3D.make(c, "Number of Players", "pixel", 1.8, 100, 0, w, Vector3(-1.225, 0.575, 1.525), roty_l, s8)
	UI3D.make(c, "Player Color", "pixel", 1.8, 100, 0, w, Vector3(0.669, 1.57, 1.6), roty_r, s8)
	ai_text = UI3D.make(c, "A.I. is Easy", "pixel", 1.8, 100, 0, w, Vector3(0.69, 1.071, 1.6), roty_r, s8)
	planets_text = UI3D.make(c, "Map Size: Small", "pixel", 1.8, 100, 0, w, Vector3(0.669, 0.575, 1.633), roty_r, s8)
	graphics_text = UI3D.make(c, "Graphics = Low", "pixel", 1.8, 100, 0, w, Vector3(-0.322, 0.995, 1.809), Quaternion.IDENTITY, Vector3(0.01, 0.01, 0.01))
	passthrough_text = UI3D.make(c, "Passthrough = Off", "pixel", 1.8, 100, 1, w, Vector3(0.026, 0.31, 1.809), Quaternion.IDENTITY, Vector3(0.01, 0.01, 0.01))
	performance_warning = UI3D.make(c, "(Performance may suffer)", "arial", 0.65, 100, 0, w, Vector3(-1.684, 1.733, 1.253), Quaternion(0, -0.2164, 0, 0.9763), s8, false)
	var roty90 := Quaternion(0, 0.7071, 0, 0.7071)
	var s20 := Vector3(0.02, 0.02, 0.1)
	counters_text = UI3D.make(c, "Loading...", "pixel", 0.5, 100, 0, w, Vector3(1.799, 1.557, -0.483), roty90, s20)
	UI3D.make(c, "My Stats:", "pixel", 1.8, 100, 0, w, Vector3(1.799, 1.9, -0.424), roty90, s20)
	UI3D.make(c, "Tutorials:", "pixel", 1.8, 100, 0, w, Vector3(1.799, 1.9, 0.918), roty90, s20)
	var roty180 := Quaternion(0, 1, 0, -1.629e-07)
	UI3D.make(c, "Leaderboards:", "pixel", 1.8, 100, 0, w, Vector3(0.672, 1.941, -1.4), roty180, s20)
	leader_texts["ShipKills"] = UI3D.make(c, "Loading...", "pixel", 0.3, 100, 0, w, Vector3(1.499, 1.5, -1.4), roty180, s20)
	leader_texts["MediumWins"] = UI3D.make(c, "Loading...", "pixel", 0.3, 100, 0, w, Vector3(0.246, 1.5, -1.4), roty180, s20)
	leader_texts["EasyWins"] = UI3D.make(c, "Loading...", "pixel", 0.3, 100, 0, w, Vector3(0.94, 1.5, -1.4), roty180, s20)
	leader_texts["HardWins"] = UI3D.make(c, "Loading...", "pixel", 0.3, 100, 0, w, Vector3(-0.432, 1.5, -1.4), roty180, s20)
	leader_texts["CheatingWins"] = UI3D.make(c, "Loading...", "pixel", 0.3, 100, 0, w, Vector3(-1.036, 1.5, -1.4), roty180, s20)
	UI3D.make(c, "Cheating AIs Defeated:", "pixel", 0.4, 100, 0, w, Vector3(-1.03, 1.6, -1.4), roty180, s20)
	UI3D.make(c, "Hard AIs Defeated:", "pixel", 0.4, 100, 0, w, Vector3(-0.428, 1.6, -1.4), roty180, s20)
	UI3D.make(c, "Easy AIs Defeated:", "pixel", 0.4, 100, 0, w, Vector3(0.94, 1.6, -1.4), roty180, s20)
	UI3D.make(c, "Medium AIs Defeated:", "pixel", 0.4, 100, 0, w, Vector3(0.246, 1.6, -1.4), roty180, s20)
	UI3D.make(c, "Most Ship Kills:", "pixel", 0.4, 100, 0, w, Vector3(1.499, 1.6, -1.4), roty180, s20)
	# decorative ship
	var deco := MeshInstance3D.new()
	deco.mesh = A.mesh("ship")
	deco.material_override = A.toon_lit()
	U.place(deco, Vector3(-3.3, 0.766, 0.232), Quaternion(0, 0.3827, 0, 0.9239), Vector3(60, 60, 60))
	c.add_child(deco)
	# tutorials
	for t in [["MenuTutorial", 1.378, "Menu"], ["GameplayTutorial", 1.028, "Controls"], ["ControlsTutorial", 0.68, "Gameplay"]]:
		var mi := MeshInstance3D.new()
		mi.name = t[0]
		mi.mesh = A.mesh("cube")
		var tm := StandardMaterial3D.new()
		tm.albedo_texture = A.tex(t[2])
		tm.metallic = 0.75
		tm.roughness = 0.5
		mi.material_override = tm
		U.place(mi, Vector3(1.75, t[1], 0.85), Quaternion.IDENTITY, Vector3(0.01, TUTORIAL_SCALE_DOWN, TUTORIAL_SCALE_DOWN))
		c.add_child(mi)
		Picker.add_box(mi, Vector3.ONE, Vector3.ZERO, "", null, t[0])
		tutorials[t[0]] = mi
	# TV (MovieTexturePlayer)
	tv = MeshInstance3D.new()
	tv.name = "MovieTexturePlayer"
	tv.mesh = A.mesh("quad")
	tv_mat = StandardMaterial3D.new()
	tv_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tv_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tv_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tv_mat.albedo_color = Color(0, 0, 0, 0.491)
	tv.material_override = tv_mat
	U.place(tv, Vector3(1.75, 1.031, 0.208), Quaternion(0, 0.7022, 0, 0.7119), Vector3(0.8346, 1, 0.06334))
	add_child(tv)
	Picker.add_box(tv, Vector3(1, 1, 0.0001), Vector3.ZERO, "", null, "MovieTexturePlayer")
	video = VideoStreamPlayer.new()
	video.size = Vector2(2, 2)
	video.position = Vector2(-10, -10)
	video.self_modulate = Color(1, 1, 1, 0)
	video.volume_db = linear_to_db(0.385 * 0.6)
	add_child(video)
	_videos = [load("res://assets/video/primarycontrols.ogv"), load("res://assets/video/secondarycontrols.ogv"), load("res://assets/video/gameplay.ogv")]
	# star field
	starfield = Starfield.new()
	c.add_child(starfield)
	U.place(starfield, Vector3.ZERO, Quaternion(-0.7071, 0, 0, 0.7071))
	starfield.setup(1.0, false, false)


func _build_audio() -> void:
	music = AudioStreamPlayer.new()
	var fb := A.music("fall_back") as AudioStreamOggVorbis
	fb = fb.duplicate() as AudioStreamOggVorbis
	fb.loop = true
	music.stream = fb
	music.volume_db = linear_to_db(0.15)
	add_child(music)
	music.play()
	ambient = AudioStreamPlayer.new()
	var amb := (A.sfx("spacesounds_loop_9") as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
	amb.loop = true
	ambient.stream = amb
	ambient.volume_db = linear_to_db(0.08)
	add_child(ambient)
	ambient.play()
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)


func _play(stream: AudioStream, volume: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = linear_to_db(volume)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ------------------------------------------------------------------ MenuMaster

func _late_init_ships() -> void:
	_ship_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = A.mesh("ship")
	_ship_mm.multimesh = mm
	_ship_mm.material_override = A.lambert1(Color.WHITE, true)
	_ship_mm.extra_cull_margin = 16384.0
	_ship_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ship_mm)
	var sp := float(STARTING_SPEED)
	for label in planets.keys():
		var p: PlanetController = planets[label]
		match label:
			"NumberOfShips":
				for j in STARTING_NUMBER / 4:
					for k in 4:
						_spawn_ship(Color.WHITE, sp, SHIP_SCALE, p, SHIP_RADIUS, "1_%d" % k, Settings.ship_setting_count >= k)
			"GameSpeed":
				for j in STARTING_NUMBER / 8:
					for k in 3:
						_spawn_ship(Color.WHITE, sp * (k + 1), SHIP_SCALE, p, SHIP_RADIUS, "2_%d" % k, Settings.speed_setting_count >= k)
			"NumberOfPlayers":
				var defs := [[Color(0, 1, 1, 1), 0], [Color(1, 0, 0, 1) / 1.5, 0], [Color(0.4, 0.4, 0.4, 1), 1], [MENU_COLORS[3], 1],
					[Color(0, 1, 0, 1), 2], [Color(1, 0, 1, 1), 2], [Color(0, 0, 1, 1), 2], [Color(1, 0.5, 0, 1), 2]]
				for d in defs:
					_spawn_ship(d[0], sp, SHIP_SCALE, p, SHIP_RADIUS, "3_%d" % d[1], Settings.player_setting_count >= d[1])
			"PlayerColor":
				for j in STARTING_NUMBER / 4:
					for k in 8:
						_spawn_ship(MENU_COLORS[k], sp, SHIP_SCALE, p, SHIP_RADIUS, "4_%d" % k, Settings.color_settings_count == k)
			"start":
				for j in STARTING_NUMBER / 8:
					for k in 8:
						_spawn_ship(MENU_COLORS[k], sp, SHIP_SCALE * 100.0, p, SHIP_RADIUS * 1000.0, "5_%d" % k, true)


func _spawn_ship(color: Color, speed: float, scl: float, planet: PlanetController, radius: float, tag: String, enabled: bool) -> void:
	var s := MenuShip.new()
	s.custom_tag = tag
	s.scale = scl
	s.planet_pos = planet.global_position
	s.pos = U.on_unit_sphere() * radius + planet.global_position
	s.cached = s.pos
	s.color = color
	s.translational_speed = speed
	s.rotational_speed = speed * 50.0
	if scl > SHIP_SCALE:
		s.rotational_speed *= (randf() - 0.5) * 1.0
	s.visible = enabled
	# ShipController.Start() speed variation
	s.rotational_speed += (randf() - 0.5) * 0.12 * s.rotational_speed
	s.translational_speed += (randf() - 0.5) * 0.12 * s.translational_speed
	ships.append(s)


func _inc(setting: String, count: int, total: int) -> int:
	count += 1
	count %= total
	for i in total:
		for s in ships:
			if s.custom_tag == "%s_%d" % [setting, i]:
				s.visible = i <= count
	return count


func _inc_color() -> void:
	Settings.color_settings_count = (Settings.color_settings_count + 1) % 8
	for s in ships:
		if s.custom_tag.begins_with("4"):
			s.visible = s.custom_tag == "4_%d" % Settings.color_settings_count


func _move_ships() -> void:
	var now := GameTime.realtime()
	var axis := Vector3(1, 1, -1).normalized() # orbitAxis default (1,1,1) in Unity space
	for s in ships:
		s.prev_time = s.prev_time if s.prev_time > 0.0 else now
		var dt: float = now - s.prev_time
		# CalculateVelocity
		var v: Vector3 = s.cached - s.previous
		s.previous = s.cached
		var v2: Vector3 = v / (dt + 1e-05)
		s.p1 = s.p2
		s.p2 = s.p3
		s.p3 = v2
		s.velocity = (s.p1 + s.p2 + s.p3) / 3.0
		# MenuMove (inOrbit): RotateAround(planetPos, orbitAxis, dt * rotationalSpeed)
		var q := Quaternion(axis, -deg_to_rad(dt * s.rotational_speed))
		s.pos = s.planet_pos + q * (s.pos - s.planet_pos)
		s.basis = Basis(q) * s.basis
		s.cached = s.pos
		s.basis = U.look_basis(s.pos, s.velocity + s.cached, Vector3.UP, s.basis)
		s.prev_time = now


func _render_ships() -> void:
	var mm := _ship_mm.multimesh
	var vis := []
	for s in ships:
		if s.visible:
			vis.append(s)
	if mm.instance_count < ships.size():
		mm.instance_count = ships.size()
	var buf := PackedFloat32Array()
	buf.resize(mm.instance_count * 16)
	var k := 0
	for s in vis:
		var b: Basis = s.basis.scaled_local(Vector3.ONE * s.scale)
		var o: Vector3 = s.pos
		var c: Color = s.color
		buf[k] = b.x.x; buf[k + 1] = b.y.x; buf[k + 2] = b.z.x; buf[k + 3] = o.x
		buf[k + 4] = b.x.y; buf[k + 5] = b.y.y; buf[k + 6] = b.z.y; buf[k + 7] = o.y
		buf[k + 8] = b.x.z; buf[k + 9] = b.y.z; buf[k + 10] = b.z.z; buf[k + 11] = o.z
		buf[k + 12] = c.r; buf[k + 13] = c.g; buf[k + 14] = c.b; buf[k + 15] = 1.0
		k += 16
	mm.buffer = buf
	mm.visible_instance_count = vis.size()


func _update_stats() -> void:
	if not (GameTime.crossed(90) or not _first_stats):
		return
	_first_stats = true
	var text := ""
	for kv in Stats.get_all_counters():
		text += str(kv[1]) + " - " + str(kv[0]) + "\n"
	counters_text.text = text
	# Steam leaderboards aren't available: show the local profile's entry.
	for key in leader_texts.keys():
		leader_texts[key].text = "%d - %s\n" % [Stats.get_counter(key), Stats.player_name()]


# ------------------------------------------------------------------ MenuClickHandler

func _process(_d: float) -> void:
	if rig == null:
		return
	_move_ships()
	_render_ships()
	_update_stats()
	_movie_update()
	if _leaving:
		return
	var hand := rig.right
	# leftClickThisFrame
	if not hand.trigger_pressed:
		_trigger_unpressed = true
		_left_click = false
	else:
		_left_click = hand.trigger_pressed and _trigger_unpressed
		_trigger_unpressed = false
	var hits := Picker.raycast_all(hand.pointer_origin(), hand.pointer_dir(), 100.0)
	var flag := false
	if hits.is_empty():
		for t in tutorials.values():
			_set_tutorial_scale(t, TUTORIAL_SCALE_DOWN)
	for hit in hits:
		var col: Picker.Col = hit["col"]
		var nm := col.name
		if tutorials.has(nm):
			_set_tutorial_scale(tutorials[nm], TUTORIAL_SCALE_UP)
			if _left_click:
				_play_movie(["MenuTutorial", "GameplayTutorial", "ControlsTutorial"].find(nm))
		if nm == "MovieTexturePlayer" and _left_click:
			_pause_movie()
		if col.tag != "menuPlanet":
			continue
		flag = true
		var pc: PlanetController = col.owner
		match pc.menu_label:
			"start":
				if _left_click:
					hand.vibrate(0.1, 0.3)
					if Net.is_host() and Net.ready_count() > 0:
						_start_versus()
					else:
						Net.close() # single player: stop hosting / searching / waiting
						_apply_settings()
						_leaving = true
						main.change_level("game")
			"NumberOfShips":
				_inc_setting("1")
			"GameSpeed":
				_inc_setting("2")
			"NumberOfPlayers":
				_inc_setting("3")
			"PlayerColor":
				if _left_click:
					hand.vibrate(0.05, 0.2)
					_inc_color()
			"AI":
				if _left_click:
					hand.vibrate(0.05, 0.2)
					Settings.ai_settings_count = (Settings.ai_settings_count + 1) % 4
					ai_text.text = AI_TEXT[Settings.ai_settings_count]
			"PlanetCount":
				if _left_click:
					hand.vibrate(0.05, 0.2)
					Settings.planet_settings_count = (Settings.planet_settings_count + 1) % 4
					planets_text.text = PLANET_TEXT[Settings.planet_settings_count]
			"Quality":
				if _left_click:
					hand.vibrate(0.05, 0.2)
					Settings.quality_index = (Settings.quality_index + 1) % Settings.QUALITY_NAMES.size()
					graphics_text.text = "Graphics = " + Settings.QUALITY_NAMES[Settings.quality_index]
					main.apply_quality(light)
			"NetHost", "NetJoin", "NetNext":
				if _left_click:
					hand.vibrate(0.05, 0.2)
					_net_click(pc.menu_label)
			"Passthrough":
				if _left_click:
					hand.vibrate(0.05, 0.2)
					Settings.passthrough = not Settings.passthrough
					XRManager.apply_passthrough(Settings.passthrough)
					_update_passthrough_text()
		if _left_click:
			Settings.save()
			_play(A.sfx("click_electronic_14"), 0.4)
			break
		if _colliding != null:
			if _colliding.global_position == pc.global_position:
				break
			_colliding.on_pointer_exit()
		_colliding = pc
		_colliding.on_pointer_enter(true)
		_play(A.sfx("click_electronic_01"), 0.1)
		break
	if not flag and _colliding != null:
		_colliding.on_pointer_exit()
		_colliding = null


func _inc_setting(setting: String) -> void:
	if _left_click:
		rig.right.vibrate(0.05, 0.2)
		match setting:
			"1": Settings.ship_setting_count = _inc("1", Settings.ship_setting_count, 3)
			"2": Settings.speed_setting_count = _inc("2", Settings.speed_setting_count, 3)
			"3": Settings.player_setting_count = _inc("3", Settings.player_setting_count, 3)
	if setting == "1":
		performance_warning.visible = Settings.ship_setting_count == 2


func _update_passthrough_text() -> void:
	var state := "On" if Settings.passthrough else "Off"
	if not XRManager.vr:
		passthrough_text.text = "Passthrough = %s (VR only)" % state
	elif Settings.passthrough and not XRManager.passthrough_active:
		passthrough_text.text = "Passthrough = On (unsupported)"
	else:
		passthrough_text.text = "Passthrough = " + state


func _set_tutorial_scale(t: MeshInstance3D, s: float) -> void:
	t.scale = Vector3(0.01, s, s)


func _apply_settings() -> void:
	match Settings.player_setting_count:
		0: Settings.number_of_players = 2
		1: Settings.number_of_players = 4
		2: Settings.number_of_players = 8
	var num := float(STARTING_NUMBER)
	for i in Settings.number_of_players:
		num *= 0.9
	Settings.number_of_ships = int(num)
	match Settings.ship_setting_count:
		0: Settings.number_of_ships = STARTING_NUMBER * 1 / (Settings.planet_settings_count + 5)
		1: Settings.number_of_ships = STARTING_NUMBER * 2 / (Settings.planet_settings_count + 9)
		2: Settings.number_of_ships = STARTING_NUMBER * 4 / (Settings.planet_settings_count + 12)
	var ss := CLICK_STARTING_SPEED
	match Settings.speed_setting_count:
		0:
			Settings.ship_rotational_speed = ss * 50
			Settings.ship_translational_speed = ss
			Settings.game_speed = 0.33
		1:
			Settings.ship_rotational_speed = (float(ss) + 1.2) * 50.0
			Settings.ship_translational_speed = float(ss) + 1.0
			Settings.game_speed = 0.66
		2:
			Settings.ship_rotational_speed = (float(ss) + 2.4) * 50.0
			Settings.ship_translational_speed = float(ss) + 2.0
			Settings.game_speed = 1.0
	Settings.planet_count = Settings.planet_settings_count
	Settings.ai_diff = Settings.ai_settings_count
	for s in ships:
		if s.custom_tag == "4_%d" % Settings.color_settings_count:
			Settings.player_color = s.color
			break
	var num2 := 1.3
	Settings.min_x = -num2
	Settings.max_x = num2
	Settings.min_z = -num2
	Settings.max_z = num2
	Settings.save()


# ------------------------------------------------------------------ MovieTexturePlayer

func _play_movie(index: int) -> void:
	if index < 0:
		return
	_stop_movie()
	_movie_index = index
	video.stream = _videos[index]
	video.play()
	tv_mat.albedo_texture = video.get_video_texture()
	tv_mat.albedo_color = Color(1, 1, 1, 0.9)
	_movie_paused = false
	music.stop() # [CameraRig] AudioSource disabled while a movie plays
	_has_been_played = true


func _stop_movie() -> void:
	video.stop()


func _pause_movie() -> void:
	if not _has_been_played:
		return
	if not _movie_paused:
		tv_mat.albedo_color = Color(1, 1, 1, 0.3)
		video.paused = true
		_movie_paused = true
		if not music.playing:
			music.play()
	else:
		tv_mat.albedo_color = Color(1, 1, 1, 0.9)
		video.paused = false
		_movie_paused = false
		music.stop()


func _movie_update() -> void:
	if video.is_playing() and not video.paused:
		var t := video.get_video_texture()
		if t and tv_mat.albedo_texture != t:
			tv_mat.albedo_texture = t
	if not GameTime.crossed(100):
		return
	var playing := video.is_playing() and not video.paused
	if not playing and not music.playing:
		music.play()


func _on_passthrough_changed(active: bool) -> void:
	if active:
		env.background_color = Color(0, 0, 0, 0)
	else:
		env.background_color = Color(0.07494, 0.07725, 0.08088, 1)
	sun.set_visuals(not active)
	starfield.visible = not active
	_update_passthrough_text()


# ------------------------------------------------------------------ versus panel (remake addition)

func _build_net_panel() -> void:
	var c := rig.content
	var w := Color.WHITE
	# back-left corner (Unity coordinates), turned to face the player at the centre
	var yaw := deg_to_rad(-122.0)
	var rot := Quaternion(Vector3.UP, yaw)
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var base := Vector3(-1.55, 0, -1.25)
	var at := func(x: float, y: float) -> Vector3: return base + right * x + Vector3(0, y, 0)
	var s8 := Vector3(0.008, 0.008, 0.008)
	UI3D.make(c, "Versus (network):", "pixel", 1.8, 100, 0, w, at.call(-0.3, 1.75), rot, Vector3(0.011, 0.011, 0.011))
	_menu_planet("NetHost", at.call(-0.15, 1.35), 0.2, 0.4)
	_menu_planet("NetJoin", at.call(-0.15, 0.95), 0.2, 0.4)
	_menu_planet("NetNext", at.call(-0.15, 0.6), 0.12, 0.4)
	net_host_text = UI3D.make(c, "", "pixel", 1.8, 100, 3, w, at.call(0.05, 1.35), rot, s8)
	net_join_text = UI3D.make(c, "", "pixel", 1.8, 100, 3, w, at.call(0.05, 0.95), rot, s8)
	net_next_text = UI3D.make(c, "", "pixel", 1.8, 100, 3, w, at.call(0.05, 0.6), rot, s8)
	net_status_text = UI3D.make(c, "", "pixel", 1.8, 100, 0, Color(0.7, 0.9, 1.0), at.call(-0.3, 0.4), rot, Vector3(0.005, 0.005, 0.005))
	Net.status_changed.connect(_on_net_status)
	Net.hosts_changed.connect(_update_net_texts)
	Net.match_starting.connect(_on_match_starting)
	Net.lobby_changed.connect(_on_lobby_changed)
	_update_net_texts()
	if not rig.vr:
		_address_box = LineEdit.new()
		_address_box.placeholder_text = "Host address (e.g. 192.168.1.20) - Enter to join, Esc to cancel"
		_address_box.custom_minimum_size = Vector2(520, 0)
		_address_box.position = Vector2(12, 80)
		_address_box.visible = false
		_address_box.text_submitted.connect(_on_address_submitted)
		_address_box.gui_input.connect(_on_address_input)
		_address_box.focus_exited.connect(func(): if _address_box.visible: _close_address_box())
		rig.desktop_hud.add_child(_address_box)
		if rig.touch:
			rig.touch.join_requested.connect(_show_address_box)


func _unhandled_key_input(event: InputEvent) -> void:
	if _address_box == null or _leaving:
		return
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_J and not _address_box.visible:
		_show_address_box()
		get_viewport().set_input_as_handled()


func _show_address_box() -> void:
	if _address_box == null or _address_box.visible:
		return
	_address_box.visible = true
	_address_box.text = ""
	_address_box.grab_focus()
	rig.desktop_controls_enabled = false


func _on_address_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and k.keycode == KEY_ESCAPE:
		_close_address_box()
		_address_box.accept_event()


func _close_address_box() -> void:
	_address_box.visible = false
	_address_box.release_focus()
	rig.desktop_controls_enabled = true


func _on_address_submitted(text: String) -> void:
	_close_address_box()
	if text.strip_edges() != "":
		Net.join(text)
		_update_net_texts()


func _net_click(label: String) -> void:
	match label:
		"NetHost":
			if Net.is_host():
				Net.close()
			else:
				Net.host()
		"NetJoin":
			var hosts := Net.found_hosts.values()
			if Net.is_client() or Net.is_host():
				Net.close()
			elif hosts.is_empty():
				Net.start_search()
			else:
				var h: Dictionary = hosts[_host_index % hosts.size()]
				Net.join(h["ip"], h["port"])
		"NetNext":
			_host_index += 1
	_update_net_texts()


func _update_net_texts() -> void:
	var hosts := Net.found_hosts.values()
	net_host_text.text = "Stop Hosting" if Net.is_host() else "Host a Game"
	if Net.is_client():
		net_join_text.text = "Cancel"
	elif Net.is_host():
		net_join_text.text = "Find Games"
	elif hosts.is_empty():
		net_join_text.text = "Find Games"
	else:
		var h: Dictionary = hosts[_host_index % hosts.size()]
		net_join_text.text = "Join %s (%d/%d)" % [h["name"], h.get("players", 1), Net.MAX_PLAYERS]
	var show_next := hosts.size() > 1 and not Net.is_client()
	net_next_text.text = "Next Game (%d/%d)" % [_host_index % maxi(hosts.size(), 1) + 1, hosts.size()] if show_next else ""
	planets["NetNext"].mesh.visible = show_next
	planets["NetNext"].set_collider_enabled(show_next)
	var st := Net.status
	if st == "":
		st = "Play against friends on your network (up to 8).\nThe host's menu settings are used and the host\nclicks Start; the other slots are A.I.s."
	net_status_text.text = st


func _on_net_status(_t: String) -> void:
	_update_net_texts()


## Client: the host started the match.
func _on_match_starting() -> void:
	if _leaving:
		return
	_leaving = true
	main.change_level("game")


## Host: start the match with everyone who joined. The map grows to fit the humans
## (4 or 8 players); the remaining slots are A.I.s.
func _start_versus() -> void:
	_apply_settings()
	var humans := 1 + Net.ready_count()
	if humans > Settings.number_of_players:
		Settings.number_of_players = 4 if humans <= 4 else 8
	Net.begin_match()
	_leaving = true
	main.change_level("game")


## `--autostart=N` (after `--`): a host starts as soon as N players (itself included) are in.
func _on_lobby_changed() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autostart=") and Net.is_host() and not _leaving:
			if 1 + Net.ready_count() >= int(a.substr(12)):
				_start_versus()


func teardown() -> void:
	for pair in [[Net.status_changed, _on_net_status], [Net.hosts_changed, _update_net_texts], [Net.match_starting, _on_match_starting], [Net.lobby_changed, _on_lobby_changed]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])
	if _address_box:
		_address_box.queue_free()
	if XRManager.passthrough_changed.is_connected(_on_passthrough_changed):
		XRManager.passthrough_changed.disconnect(_on_passthrough_changed)
	if video:
		video.stop()
