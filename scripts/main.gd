extends Node
## Entry point. Owns the player rig and switches between the menu ("startMenu") and the game
## ("sample") the way SteamVR_LoadLevel did: fade out (1 s), load, fade back in.

var rig: PlayerRig
var level: Node3D
var _busy := false


func _ready() -> void:
	randomize()
	if not _assets_present():
		_show_missing_assets()
		return
	Settings.load_settings()
	rig = PlayerRig.new()
	rig.name = "PlayerRig"
	add_child(rig)
	var start := "menu"
	var args := OS.get_cmdline_user_args()
	if args.has("--game"):
		start = "game"
		_apply_quick_start_settings()
	_load(start)
	for a in args:
		if a == "--host":
			Net.host()
		elif a.begins_with("--join="):
			Net.join(a.substr(7))
	rig.set_fade_immediate(1.0)
	rig.fade_to(0.0, 0.5)


## The original game's assets are not distributed with the source; see tools/setup.py.
func _assets_present() -> bool:
	for p in ["res://assets/meshes/sphere.obj", "res://assets/textures/star_red.png",
			"res://assets/fonts/alterebro-pixel-font.ttf", "res://assets/data/explosions.json"]:
		if not (ResourceLoader.exists(p) or FileAccess.file_exists(p)):
			return false
	return true


func _show_missing_assets() -> void:
	var msg := "Lazerbait assets not found.\n\nExtract them from your copy of the original game:\n\n" + \
		"    python3 tools/setup.py /path/to/Lazerbait\n\nthen reopen / reimport the project. See README.md."
	push_error(msg.replace("\n\n", " "))
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var l := Label.new()
	l.text = msg
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 22)
	layer.add_child(l)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)


## `--game` (after `--`) jumps straight into a match with the saved menu settings.
func _apply_quick_start_settings() -> void:
	var colors := MenuLevel.MENU_COLORS
	Settings.number_of_players = [2, 4, 8][Settings.player_setting_count]
	Settings.number_of_ships = [40 / (Settings.planet_settings_count + 5), 80 / (Settings.planet_settings_count + 9), 160 / (Settings.planet_settings_count + 12)][Settings.ship_setting_count]
	Settings.ship_rotational_speed = [50.0, 110.0, 170.0][Settings.speed_setting_count]
	Settings.ship_translational_speed = [1.0, 2.0, 3.0][Settings.speed_setting_count]
	Settings.game_speed = [0.33, 0.66, 1.0][Settings.speed_setting_count]
	Settings.planet_count = Settings.planet_settings_count
	Settings.ai_diff = Settings.ai_settings_count
	Settings.player_color = colors[Settings.color_settings_count]
	Settings.min_x = -1.3
	Settings.max_x = 1.3
	Settings.min_z = -1.3
	Settings.max_z = 1.3


func _load(which: String) -> void:
	if which == "game":
		var g := GameLevel.new()
		g.name = "Game"
		add_child(g)
		level = g
		g.setup(self, rig)
	else:
		var m := MenuLevel.new()
		m.name = "Menu"
		add_child(m)
		level = m
		m.setup(self, rig)


func change_level(which: String) -> void:
	if _busy:
		return
	_busy = true
	rig.fade_to(1.0, 1.0)
	while not rig.fade_done():
		await get_tree().process_frame
	if level:
		if level.has_method("teardown"):
			level.teardown()
		level.queue_free()
		level = null
	rig.clear_hand_ui()
	Picker.clear()
	GameTime.time_scale = 1.0
	await get_tree().process_frame
	_load(which)
	rig.fade_to(0.0, 0.5)
	_busy = false


## Unity 5.4 (linear colour space, lightsUseLinearIntensity off) converted color*intensity
## from gamma to linear as a whole. Returns [sRGB colour, energy] for a Godot light.
func unity_light(c: Color, intensity: float) -> Array:
	var l := Color(U.g2l(c.r * intensity), U.g2l(c.g * intensity), U.g2l(c.b * intensity))
	var e := maxf(l.r, maxf(l.g, l.b))
	if e <= 0.0:
		return [Color.BLACK, 0.0]
	var lin := Color(l.r / e, l.g / e, l.b / e)
	return [lin.linear_to_srgb(), e]


## QualitySettings: Low (no shadows, no AA), Medium (shadows), High (shadows + MSAA).
func apply_quality(light: DirectionalLight3D) -> void:
	var q := Settings.quality_index
	var vp := get_viewport()
	match q:
		0:
			vp.msaa_3d = Viewport.MSAA_DISABLED
		1:
			vp.msaa_3d = Viewport.MSAA_DISABLED
		_:
			vp.msaa_3d = Viewport.MSAA_4X
	if light:
		light.shadow_enabled = q > 0


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Settings.save()
		Stats.flush()
