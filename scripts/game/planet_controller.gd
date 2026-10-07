class_name PlanetController
extends Node3D
## Port of PlanetController.cs. Used for real planets (with ring, range sphere, countdown dots,
## selection lines and sounds) and for "menu" planets (menu buttons, end-game planets, the
## wrist menu planets) which are plain Car Paint spheres.

const COLOR_MULTIPLIER := 1.5
const LINE_DENSITY := 3.0
const LINE_WIDTH := 0.2
const LINE_BRIGHTNESS := 2.0
const COUNTDOWN_INTERVAL := 1.5
const LASER_INTERVAL := 0.08
const DOT_VOLUME := 0.9
const LASER_VOLUME := 0.1
const EXPLODE_VOLUME := 1.5
const PITCH_RANGE := 0.15

var parent # Planet (game data) or null for menu planets
var menu_label := ""
var planet_range := 1.0
var is_full := false            # Unity: transform.childCount > childCount(5)
var initialized := false

var mesh: MeshInstance3D
var mat: StandardMaterial3D
var mat_color := Color(0, 0.192, 0.287, 1)  # Car Paint default _Color
var startcolor := Color.WHITE

var line: Line3D
var link_line: Line3D
var ring: MeshInstance3D
var distance_outline: MeshInstance3D
var distance_outline_wire: MeshInstance3D
var _outline_mat: ShaderMaterial
var _wire_mat: ShaderMaterial
var dot1: MeshInstance3D
var dot2: MeshInstance3D
var dot3: MeshInstance3D
var audio: AudioStreamPlayer3D
var laser_audio: AudioStreamPlayer3D
var collider: Picker.Col

# line textures (Planet prefab): arrow, greenArrow, greenSquare, redX, one
var line_textures: Array[Texture2D] = []

var _play_laser_sound := false
var _play_explode_sound := false
var _linked := false
var _selected := false
var _countdown_enabled := false
var _countdown_dots := 3
var _last_countdown := 0.0
var _last_laser := 0.0
var _range_lines: Array = []
var _line_offset := 0.0
var _link_offset := 0.0


## Build the visual. `full` = game planet prefab (ring, outlines, dots, audio, lines).
func build(full: bool, color: Color, collider_radius: float, tag: String) -> void:
	is_full = full
	mesh = MeshInstance3D.new()
	mesh.name = "Sphere"
	mesh.mesh = A.mesh("sphere")
	mat = A.car_paint(color)
	mat_color = color
	mesh.material_override = mat
	add_child(mesh)
	collider = Picker.add_sphere(self, collider_radius, tag, self, name)
	if full:
		line_textures = [A.tex("arrow"), A.tex("greenArrow"), A.tex("greenSquare"), A.tex("redX"), A.tex("one")]
		# Ring (LBcylinder mesh) - shown while hovered / selected
		ring = MeshInstance3D.new()
		ring.mesh = A.mesh("ring")
		ring.material_override = A.toon_lit()
		U.place(ring, Vector3(-0.15, 0, 0), Quaternion.IDENTITY, Vector3(750, 50, 750))
		ring.visible = false
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		# range spheres (shown when selected)
		distance_outline_wire = MeshInstance3D.new()
		distance_outline_wire.mesh = Wire.make_wire_mesh("sphere")
		_wire_mat = ShaderMaterial.new()
		_wire_mat.shader = A.shader("wire")
		distance_outline_wire.material_override = _wire_mat
		distance_outline_wire.visible = false
		distance_outline_wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(distance_outline_wire)
		distance_outline = MeshInstance3D.new()
		distance_outline.mesh = A.mesh("sphere")
		_outline_mat = ShaderMaterial.new()
		_outline_mat.shader = A.shader("range_sphere")
		distance_outline.material_override = _outline_mat
		distance_outline.visible = false
		distance_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(distance_outline)
		# countdown dots
		var dots := []
		for i in 3:
			var d := MeshInstance3D.new()
			d.mesh = A.mesh("cube")
			d.material_override = A.lambert1(Color.WHITE)
			U.place(d, Vector3(-0.25 + 0.25 * i, 0.75, 0), Quaternion.IDENTITY, Vector3(0.1, 0.1, 0.1))
			d.visible = false
			add_child(d)
			dots.append(d)
		dot1 = dots[0]
		dot2 = dots[1]
		dot3 = dots[2]
		# AudioSource[0] (dots / explosion): 3D, logarithmic, min 1 max 20
		audio = AudioStreamPlayer3D.new()
		audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		audio.unit_size = 1.0
		audio.max_db = 0.0
		audio.max_polyphony = 4
		add_child(audio)
		# AudioSource[1] (lasers): steep custom roll-off out to 12 units
		laser_audio = AudioStreamPlayer3D.new()
		laser_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		laser_audio.unit_size = 0.85
		laser_audio.max_distance = 12.0
		laser_audio.max_db = 0.0
		laser_audio.max_polyphony = 4
		add_child(laser_audio)


## PlanetController.Start()
func start() -> void:
	startcolor = mat_color
	if is_full:
		line = Line3D.new(false, line_textures[0], LINE_WIDTH)
		link_line = Line3D.new(false, line_textures[0], LINE_WIDTH)
		add_child(line)
		add_child(link_line)
		line.set_points(global_position, global_position)
		link_line.set_points(global_position, global_position)
		var bright := U.g2l_color(Color(LINE_BRIGHTNESS, LINE_BRIGHTNESS, LINE_BRIGHTNESS, 1.0))
		line.set_tint(bright)
		link_line.set_tint(bright)
		ring.visible = false
		_set_outline_colors(Color(startcolor.r, startcolor.g, startcolor.b, 0.18), Color(startcolor.r, startcolor.g, startcolor.b, 0.2))
		for d in [dot1, dot2, dot3]:
			(d.material_override as StandardMaterial3D).albedo_color = Color.WHITE
	initialized = true


func _set_outline_colors(fill: Color, wire: Color) -> void:
	_outline_mat.set_shader_parameter("color", fill)
	_wire_mat.set_shader_parameter("color", wire)


func set_mat_color(c: Color) -> void:
	mat_color = c
	mat.albedo_color = c


func _process(_delta: float) -> void:
	if not initialized or not is_full:
		return
	var dt := GameTime.delta
	if _linked:
		_link_offset -= dt * 2.0
		if not link_line.collapsed():
			_update_line_uv(link_line, _link_offset)
	else:
		_line_offset -= dt * 2.0
		if not line.collapsed():
			_update_line_uv(line, _line_offset)
	if GameTime.paused():
		return
	var now := GameTime.realtime()
	if _play_laser_sound and _last_laser + LASER_INTERVAL < now:
		_last_laser = now
		_play_laser_sound = false
		_play_sound_laser(A.sfx("laser_09"), LASER_VOLUME)
		if _play_explode_sound:
			_play_explode_sound = false
			_play_sound_laser(A.sfx("impact5"), EXPLODE_VOLUME)
	if not _countdown_enabled or not (_last_countdown + COUNTDOWN_INTERVAL < now):
		return
	_last_countdown = now
	var flag: bool = parent.enemy_ships.any(func(s): return s.player == parent.master.local_player) or parent.player == parent.master.local_player
	_countdown_dots -= 1
	if _countdown_dots <= 0:
		dot1.visible = false
		_countdown_dots = 3
		if flag:
			_play_one_shot(A.sfx("click_electronic_03"), DOT_VOLUME, 1.0)
		_countdown_enabled = false
		parent.master.change_planet_hands_queued(parent)
	elif _countdown_dots == 1:
		if flag:
			_play_one_shot(A.sfx("click_electronic_05"), DOT_VOLUME, 1.0)
		dot2.visible = false
	elif _countdown_dots == 2:
		if flag:
			_play_one_shot(A.sfx("click_electronic_05"), DOT_VOLUME, 1.0)
		dot3.visible = false


var _uv_scale_line := 1.0
var _uv_scale_link := 1.0


func _update_line_uv(l: Line3D, offset: float) -> void:
	var sc := _uv_scale_link if l == link_line else _uv_scale_line
	l.set_uv(Vector2(sc, 1.0), Vector2(offset, 0.0))


func _set_line_scale(l: Line3D, sc: float) -> void:
	if l == link_line:
		_uv_scale_link = sc
		_update_line_uv(l, _link_offset)
	else:
		_uv_scale_line = sc
		_update_line_uv(l, _line_offset)


func _enable_range_lines() -> void:
	for p in parent.master.get_planets_in_range(parent):
		var l := Line3D.new(false, line_textures[4], 0.01)
		l.set_tint(U.g2l_color(Color(0.5, 0.5, 0.5, 0.5)))
		add_child(l)
		l.set_points(p.position, global_position)
		_range_lines.append(l)


func _disable_range_lines() -> void:
	for l in _range_lines:
		if is_instance_valid(l):
			l.queue_free()
	_range_lines.clear()


func _play_one_shot(stream: AudioStream, volume: float, pitch: float) -> void:
	if audio == null:
		return
	audio.stream = stream
	audio.pitch_scale = pitch
	audio.volume_db = linear_to_db(volume)
	audio.play()


func _play_sound(stream: AudioStream, volume: float) -> void:
	_play_one_shot(stream, volume, randf() * PITCH_RANGE - PITCH_RANGE / 2.0 + 1.0)


func _play_sound_laser(stream: AudioStream, volume: float) -> void:
	if laser_audio == null:
		return
	laser_audio.stream = stream
	laser_audio.pitch_scale = randf() * PITCH_RANGE - PITCH_RANGE / 2.0 + 1.0
	laser_audio.volume_db = linear_to_db(volume)
	laser_audio.play()


func on_pointer_enter(menu: bool) -> void:
	set_mat_color(mat_color * COLOR_MULTIPLIER)
	if is_full:
		ring.visible = true
	if not menu and parent and parent.master.player.selected_planet != null:
		var sel = parent.master.player.selected_planet
		var component: PlanetController = sel.node
		var position := sel.node.global_position as Vector3
		var num := position.distance_to(global_position)
		line.set_points(position, global_position)
		if num > component.planet_range:
			line.set_texture(line_textures[3])
		elif sel.player == parent.player:
			line.set_texture(line_textures[1])
		else:
			line.set_texture(line_textures[0])
		_set_line_scale(line, position.distance_to(global_position) * LINE_DENSITY)
	if not menu and parent and parent.master.player.selected_planet == null and parent.player == parent.master.local_player and parent.master.get_planet_assignment(parent) != parent:
		link_line.set_texture(line_textures[3])


func on_pointer_exit(menu := true) -> void:
	if is_full and not _selected:
		ring.visible = false
	set_mat_color(mat_color / COLOR_MULTIPLIER)
	if line:
		line.set_points(global_position, global_position)
	if parent != null and not menu and parent.master.player.selected_planet == null and parent.player == parent.master.local_player and parent.master.get_planet_assignment(parent) != parent:
		if parent.master.get_planet_assignment(parent).player == parent.player:
			link_line.set_texture(line_textures[1])
		else:
			link_line.set_texture(line_textures[0])


func play_laser_sound() -> void:
	_play_laser_sound = true


func play_explode_sound() -> void:
	_play_explode_sound = true


## `force`: a versus client mirrors the host's countdown and skips the re-trigger guard.
func enable_countdown(force := false) -> void:
	if not _countdown_enabled and (force or _last_countdown + COUNTDOWN_INTERVAL < GameTime.realtime()):
		if parent.enemy_ships.any(func(s): return s.player == parent.master.local_player):
			_play_one_shot(A.sfx("click_electronic_05"), DOT_VOLUME, audio.pitch_scale)
		_countdown_enabled = true
		_last_countdown = GameTime.realtime()
		dot1.visible = true
		dot2.visible = true
		dot3.visible = true


func disable_countdown() -> void:
	_countdown_dots = 3
	_countdown_enabled = false
	dot1.visible = false
	dot2.visible = false
	dot3.visible = false


func select() -> void:
	if is_full:
		ring.visible = true
	_selected = true
	mat.albedo_color = mat_color * 1.8
	mat_color = mat_color * 1.8
	distance_outline.visible = true
	distance_outline_wire.visible = true
	_enable_range_lines()


func deselect() -> void:
	if is_full:
		ring.visible = false
	_selected = false
	set_mat_color(mat_color / 1.8)
	parent.master.player.selected_planet = null
	line.set_points(global_position, global_position)
	if not _linked:
		link_line.set_points(global_position, global_position)
	distance_outline.visible = false
	distance_outline_wire.visible = false
	_disable_range_lines()


func change_color(new_color: Color) -> void:
	startcolor = new_color
	set_mat_color(new_color)
	_set_outline_colors(Color(new_color.r, new_color.g, new_color.b, 0.25), Color(new_color.r, new_color.g, new_color.b, 0.3))
	parent.color = new_color


func draw_link_to_planet(dest) -> void:
	line.set_points(global_position, global_position)
	if dest.player == parent.player:
		link_line.set_texture(line_textures[1])
		link_line.set_tint(U.g2l_color(Color(LINE_BRIGHTNESS, LINE_BRIGHTNESS, LINE_BRIGHTNESS, 1.0)))
	else:
		link_line.set_texture(line_textures[0])
		link_line.set_tint(U.g2l_color(Color(2.1, 2.1, 2.1, 1.0)))
	var position := global_position
	link_line.set_points(position, dest.position)
	_set_line_scale(link_line, position.distance_to(dest.position) * LINE_DENSITY)
	_linked = true


func draw_link_to_point(dest: Vector3, to_link = null) -> void:
	if global_position.distance_to(dest) > planet_range:
		line.set_texture(line_textures[3])
	elif to_link != null:
		if to_link.player == parent.player:
			line.set_texture(line_textures[1])
		else:
			line.set_texture(line_textures[0])
	else:
		line.set_texture(line_textures[1])
	line.set_tint(U.g2l_color(Color(LINE_BRIGHTNESS, LINE_BRIGHTNESS, LINE_BRIGHTNESS, 1.0)))
	var position := global_position
	line.set_points(position, dest)
	_set_line_scale(line, position.distance_to(dest) * LINE_DENSITY)


func erase_link() -> void:
	link_line.set_points(global_position, global_position)
	_linked = false


func erase_line() -> void:
	line.set_points(global_position, global_position)


func change_link_color() -> void:
	link_line.set_texture(line_textures[1])
	link_line.set_tint(U.g2l_color(Color(LINE_BRIGHTNESS, LINE_BRIGHTNESS, LINE_BRIGHTNESS, 1.0)))


## Set the range sphere sizes (MasterController.SpawnPlanets).
func set_outline_scale(local_scale: float) -> void:
	if distance_outline:
		distance_outline.scale = Vector3.ONE * local_scale
		distance_outline_wire.scale = Vector3.ONE * local_scale


func set_collider_enabled(e: bool) -> void:
	if collider:
		collider.enabled = e
