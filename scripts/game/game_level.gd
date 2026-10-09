class_name GameLevel
extends Node3D
## The "sample" scene: skybox, sun, star field, platform, end-game texts/planets, music,
## controllers and the MasterController.

const TRACKS := ["allies_or_enemies", "calm_before_the_storm", "chosen_ones", "fall_back", "for_glory",
	"reflections", "the_mission", "unknown_beings", "we_all_have_secrets", "engage"]

var main # Main
var rig: PlayerRig
var master: MasterController
var click_handler: ClickHandler
var left_handler: LeftControllerHandler
var env: Environment
var world_env: WorldEnvironment
var sun: SunFX
var sun_light: DirectionalLight3D
var starfield: Starfield
var star_anchor: Node3D
var music: AudioStreamPlayer
var ambient: AudioStreamPlayer
var _win_texts: Array = []
var _lose_texts: Array = []
var _end_planets: Array = []
var _end_texts: Array = []
var _music_muted := false
var _leaving := false
var _net_texts: Array = []


func setup(p_main, p_rig: PlayerRig) -> void:
	main = p_main
	rig = p_rig
	Picker.clear()
	GameTime.time_scale = 1.0
	rig.set_scale_factor(10.0)        # [CameraRig] localScale = 10 in the sample scene
	rig.set_rig_position(Vector3.ZERO)
	_build_environment()
	_build_sun()
	_build_rig_content()
	_build_audio()
	master = MasterController.new()
	master.name = "Master"
	add_child(master)
	click_handler = ClickHandler.new()
	click_handler.name = "ClickHandler"
	left_handler = LeftControllerHandler.new()
	left_handler.name = "LeftControllerHandler"
	add_child(click_handler)
	add_child(left_handler)
	click_handler.setup(self, rig, master)
	master.map_ready.connect(_on_map_ready)
	if Net.versus():
		Net.remote_left.connect(_on_remote_left)
		Net.notice.connect(_on_notice)
		if Net.is_client():
			show_net_message("Waiting for the host...")
	master.start_game(self, rig)
	click_handler.left_handler = left_handler
	left_handler.setup(rig, master, click_handler)
	XRManager.passthrough_changed.connect(_on_passthrough_changed)
	_on_passthrough_changed(XRManager.passthrough_active)
	main.apply_quality(sun_light)


## The planets exist (a versus client gets the map from the host a moment after loading).
func _on_map_ready() -> void:
	click_handler.set_player_color(master.local_color())
	if Net.is_client():
		show_net_message("")
	if not rig.vr:
		_setup_desktop_view()


func _setup_desktop_view() -> void:
	for h in [rig.left, rig.right]:
		var model: Node3D = h.ui.get_node_or_null("Model")
		if model:
			model.visible = true
	rig.allow_vertical = true
	rig.desktop_move_speed = 2.0
	# Stand back from the home planet a little, looking at the centre of the map.
	var home := rig.rig_position()
	var centre := Vector3(0, home.y, 0)
	var away := (home - centre)
	away.y = 0
	if away.length() > 0.01:
		away = away.normalized()
	rig.set_rig_position(home + away * 6.0)
	var look := Vector3(0, 15.0, 0)
	rig.reset_desktop_view(look)
	_desktop_help = ("LMB: select / drag to link   1-4: % of ships   Tab: mini-map   Esc: menu   P: pause\n" +
		"RMB drag: look   WASD/QE: move   Shift: fast   Wheel: forward/back   MMB drag: pan   H: hide help")
	if rig.touch:
		_desktop_help = "Tap: select / send   Drag planet to planet: link   Two fingers: move the view, pinch: forward / back"
		rig.set_touch_layout("game")
	rig.set_help_text(_desktop_help)


var _desktop_help := ""


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = A.shader("sky6")
	for face in ["front", "back", "left", "right"]:
		sm.set_shader_parameter(face + "_tex", load("res://assets/skybox/BluePinkNebular_%s.png" % face))
	sm.set_shader_parameter("up_tex", load("res://assets/skybox/BluePinkNebular_top.png"))
	sm.set_shader_parameter("down_tex", load("res://assets/skybox/BluePinkNebular_bottom.png"))
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	# Ambient: Trilight (sky 0.90 / equator 0.70 / ground 0.55), reflections from the skybox.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.72, 0.72)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _build_sun() -> void:
	sun = SunFX.new()
	sun.name = "Sun"
	add_child(sun)
	U.place(sun, Vector3(0, 200, 100))
	sun.setup(40.0, 90.0, 0.0)
	sun_light = DirectionalLight3D.new()
	sun_light.name = "SunLight"
	U.place(sun_light, Vector3(0, 0.023, 0), Quaternion(0.866, -5.963e-08, -5.963e-08, 0.5))
	var lc: Array = main.unity_light(Color(1.0, 0.91878, 0.6296), 1.18)
	sun_light.light_color = lc[0]
	sun_light.light_energy = lc[1]
	sun_light.shadow_enabled = true
	sun_light.shadow_bias = 0.05
	sun_light.shadow_normal_bias = 0.4
	sun_light.directional_shadow_max_distance = 300.0
	sun.add_child(sun_light)


func _build_rig_content() -> void:
	var c := rig.content
	var white := Color.WHITE
	# logo text lying on the platform
	UI3D.make(c, "Lazerbait", "logo", 100, 100, 0, U.rgba32(4278190247), Vector3(-1, 0.05, 0.25), Quaternion(0.7071, 0, 0, 0.7071), Vector3(0.0005, 0.0005, 0.003))
	# win / lose texts (MeshRenderers disabled until EndGame)
	var win_col := U.rgba32(4294958848)
	var lose_col := U.rgba32(4278190335)
	var wins := [
		[Vector3(0, 15, 20), Quaternion(-0.2588, 0, 0, 0.9659)],
		[Vector3(0, 15, -20), Quaternion(4.217e-08, 0.9659, 0.2588, -1.574e-07)],
		[Vector3(20, 15, 0), Quaternion(-0.183, 0.683, 0.183, 0.683)],
		[Vector3(-20, 15, 0), Quaternion(0.183, 0.683, 0.183, -0.683)],
	]
	for w in wins:
		_win_texts.append(UI3D.make(c, "You Win", "pixel", 27, 100, 4, win_col, w[0], w[1], Vector3(0.03, 0.03, 0.001), false))
	var loses := [
		[Vector3(0, 15, -20), Quaternion(4.217e-08, -0.9659, -0.2588, -1.574e-07)],
		[Vector3(0, 15, 20), Quaternion(-0.2588, 0, 0, 0.9659)],
		[Vector3(20, 15, 0), Quaternion(0.183, -0.683, -0.183, -0.683)],
		[Vector3(-20, 15, -0.2), Quaternion(-0.183, -0.683, -0.183, 0.683)],
	]
	for l in loses:
		_lose_texts.append(UI3D.make(c, "You Lose", "pixel", 27, 100, 4, lose_col, l[0], l[1], Vector3(0.03, 0.03, 0.003), false))
	# platform
	var plat := MeshInstance3D.new()
	plat.name = "Platform"
	plat.mesh = A.mesh("cylinder")
	var pm := StandardMaterial3D.new()
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.albedo_color = Color(0, 0, 0, 0.853)
	pm.albedo_texture = A.tex("geo_pattern_albedo")
	pm.uv1_scale = Vector3(40, 40, 1)
	pm.metallic = 0.733
	pm.roughness = 1.0 - 0.861
	pm.emission_enabled = true
	pm.emission = Color(0.044, 0, 0)
	plat.material_override = pm
	plat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	U.place(plat, Vector3(0, -0.07, 0), Quaternion.IDENTITY, Vector3(4, 0.1, 4))
	c.add_child(plat)
	# end game planets
	var ends := [
		[Vector3(0.05, 1.5, 1), Quaternion.IDENTITY],
		[Vector3(1.35, 1.5, 0), Quaternion(0, 0.7071, 0, 0.7071)],
		[Vector3(0, 1.5, -1), Quaternion(0, 1, 0, -1.629e-07)],
		[Vector3(-1.5, 1.5, 0), Quaternion(0, 0.7071, 0, -0.7071)],
	]
	for i in ends.size():
		var p := PlanetController.new()
		p.name = "EndGamePlanet%d" % (i + 1)
		U.place(p, ends[i][0], ends[i][1], Vector3(0.4, 0.4, 0.4))
		c.add_child(p)
		p.build(false, Color(0, 0.192, 0.287, 1), 0.7, "endPlanet")
		p.start()
		p.mesh.visible = false
		p.set_collider_enabled(false)
		_end_planets.append(p)
		_end_texts.append(UI3D.make(p, "Return to Menu", "pixel", 27, 100, 4, white, Vector3(0, 1.2, 0), Quaternion.IDENTITY, Vector3(0.003, 0.003, 0.003), false))
	# star field (world simulation space, "Local" scaling => not scaled by the rig)
	star_anchor = Node3D.new()
	star_anchor.name = "StarAnchor"
	add_child(star_anchor)
	starfield = Starfield.new()
	star_anchor.add_child(starfield)
	starfield.setup(2.0, true, true)


func _build_audio() -> void:
	music = AudioStreamPlayer.new()
	music.volume_db = linear_to_db(0.071)
	add_child(music)
	music.finished.connect(_next_track)
	_next_track()
	ambient = AudioStreamPlayer.new()
	var amb := A.sfx("spacesounds_loop_9") as AudioStreamOggVorbis
	if amb:
		amb.loop = true
	ambient.stream = amb
	ambient.volume_db = linear_to_db(0.04)
	add_child(ambient)
	ambient.play()


func _next_track() -> void:
	# MusicPlayer: pick a random track whenever nothing is playing
	music.stream = A.music(TRACKS[randi() % TRACKS.size()])
	music.play()


var _was_paused := false


func _process(_d: float) -> void:
	if star_anchor and rig:
		star_anchor.global_position = rig.rig_position()
	# Time.timeScale = 0 froze every particle system in the original
	var p := GameTime.paused()
	if p != _was_paused:
		_was_paused = p
		for n in find_children("*", "GPUParticles3D", true, false):
			(n as GPUParticles3D).speed_scale = 0.0 if p else 1.0
		for n in find_children("*", "CPUParticles3D", true, false):
			(n as CPUParticles3D).speed_scale = 0.0 if p else 1.0


func set_player_color_disc(c: Color) -> void:
	if click_handler and click_handler.player_color_disc:
		click_handler.set_player_color(c)


func toggle_music_mute() -> void:
	_music_muted = not _music_muted
	music.volume_db = -80.0 if _music_muted else linear_to_db(0.071)


func show_end_game(winner: bool) -> void:
	for t in (_win_texts if winner else _lose_texts):
		t.visible = true
	for p in _end_planets:
		p.mesh.visible = true
		p.set_collider_enabled(true)
	for t in _end_texts:
		t.visible = true


## Versus status text, shown in the four directions like the end-game texts ("" hides it).
func show_net_message(msg: String) -> void:
	if _net_texts.is_empty():
		var col := Color(1, 1, 1, 1)
		for w in [
				[Vector3(0, 10, 20), Quaternion(-0.2588, 0, 0, 0.9659)],
				[Vector3(0, 10, -20), Quaternion(4.217e-08, 0.9659, 0.2588, -1.574e-07)],
				[Vector3(20, 10, 0), Quaternion(-0.183, 0.683, 0.183, 0.683)],
				[Vector3(-20, 10, 0), Quaternion(0.183, 0.683, 0.183, -0.683)]]:
			_net_texts.append(UI3D.make(rig.content, "", "pixel", 27, 100, 4, col, w[0], w[1], Vector3(0.012, 0.012, 0.001), false))
	for t in _net_texts:
		t.text = msg
		t.visible = msg != ""
	if not rig.vr:
		rig.set_help_text(msg if msg != "" else _desktop_help)


func _on_notice(text: String) -> void:
	if not master._game_over:
		show_net_message(text)
		get_tree().create_timer(6.0).timeout.connect(func():
			if is_instance_valid(self) and _net_texts.size() > 0 and _net_texts[0].text == text:
				show_net_message(""))


## A joined player disconnected (host), or the host left (client).
func _on_remote_left(player: String) -> void:
	if master.net_role == Net.Role.HOST:
		master.on_remote_left(player) # the message arrives through Net.notice
	else:
		show_net_message("Connection to the host was lost")
		for p in _end_planets:
			p.mesh.visible = true
			p.set_collider_enabled(true)
		for t in _end_texts:
			t.visible = true


func return_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	main.change_level("menu")


func _on_passthrough_changed(active: bool) -> void:
	if env == null:
		return
	if active:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0, 0, 0, 0)
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	else:
		env.background_mode = Environment.BG_SKY
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	sun.set_visuals(not active)
	starfield.visible = not active


func teardown() -> void:
	if Net.remote_left.is_connected(_on_remote_left):
		Net.remote_left.disconnect(_on_remote_left)
	if Net.notice.is_connected(_on_notice):
		Net.notice.disconnect(_on_notice)
	if Net.role != Net.Role.OFFLINE:
		Net.leave_match()
	if XRManager.passthrough_changed.is_connected(_on_passthrough_changed):
		XRManager.passthrough_changed.disconnect(_on_passthrough_changed)
	GameTime.time_scale = 1.0
	Stats.flush()
