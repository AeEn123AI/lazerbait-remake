class_name ClickHandler
extends Node
## Port of ClickHandler.cs (right controller in game) and the objects that lived under
## "Controller (right)" in the sample scene: PausedText, PercentSelector (+ texts), PlayerColor,
## tooltips and the laser.

const MIN_SCALE := 0.125
const MAX_SCALE := 20.0
const SCALE_RATE := 10.0
const SCALE_VIBRATION_STRENGTH := 0.002
const MOVEABLE_RANGE := 100.0

var distance := 2.0 # serialized value on Controller (right)
var rig: PlayerRig
var hand: Hand
var master: MasterController
var level # GameLevel
var left_handler # LeftControllerHandler

var _colliding_planet: PlanetController = null
var _colliding_menu: PlanetController = null
var _trigger_clicked := false
var _pad_clicked := false
var _trigger_unpressed := true
var _pad_unpressed := true
var _menu_click := false
var _menu_unpressed := true
var _dragging := false
var _pad_touched := false
var _pad_untouched := true
var _grip_pressed := false
var _last_touched := 4
var selected_percent := 4
var _was_pad_pressed_last_frame := false
var _pad_released := false
var _magnet_planet: Planet = null
var _previous_position_r := Vector3.ZERO
var _base_rig_scale := 1.0
var _base_distance := 0.0
var _base_rig_pos := Vector3.ZERO
var _pos_base := Vector3.ZERO
var _previous_position := Vector3.ZERO
var _left_grip_pressed := false
var _left_grip_not_pressed := false

var _audio: AudioStreamPlayer

# UI objects
var paused_text: Label3D
var percent_selector: MeshInstance3D
var finger_sphere: MeshInstance3D
var quarter_text: Label3D
var half_text: Label3D
var three_text: Label3D
var whole_text: Label3D
var vert_line: MeshInstance3D
var hor_line: MeshInstance3D
var selection_label: Label3D
var player_color_disc: MeshInstance3D
var tips: Array = []   # [Node3D tip, Line3D, Label3D]
var laser_holder: Node3D

const PERCENT_COLOR := 4280793625 # TextMesh colour of the % texts


func setup(p_level, p_rig: PlayerRig, p_master: MasterController) -> void:
	level = p_level
	rig = p_rig
	hand = rig.right
	master = p_master
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	if not rig.vr:
		distance = 1000.0 # mouse pointing reaches the whole map
	_build_ui()
	_enlarge_text(whole_text)


func _build_ui() -> void:
	var ui := hand.ui
	var white := Color.WHITE
	paused_text = UI3D.make(ui, "Game Paused", "pixel", 27, 100, 7, white, Vector3(0, 0.02, 0), Quaternion(0.7071, 0, 0, 0.7071), Vector3(0.0002, 0.0002, 0.0002), false)

	percent_selector = MeshInstance3D.new()
	percent_selector.mesh = A.mesh("cylinder")
	percent_selector.material_override = A.car_paint_black()
	U.place(percent_selector, Vector3(0, 0.005, -0.05), Quaternion(0.06105, -1.742e-05, -1.065e-06, -0.9981), Vector3(0.045, 0.0001, 0.045))
	ui.add_child(percent_selector)

	finger_sphere = MeshInstance3D.new()
	finger_sphere.mesh = A.mesh("sphere")
	var blinn := StandardMaterial3D.new()
	blinn.albedo_color = Color(0.882, 0.195, 0.195)
	finger_sphere.material_override = blinn
	U.place(finger_sphere, Vector3(0, 0, 0), Quaternion(0, 0.7071, 0, 0.7071), Vector3(0.08, 50, 0.08))
	finger_sphere.visible = false
	percent_selector.add_child(finger_sphere)

	var pc := U.rgba32(PERCENT_COLOR)
	var rot20 := Quaternion(0.1736, 0, 0, 0.9848)
	quarter_text = UI3D.make(percent_selector, "25", "pixel", 75, 100, 4, pc, Vector3(-0.2, 10, -0.15), rot20, Vector3(0.0005, 1, 0.001), false)
	half_text = UI3D.make(percent_selector, "50", "pixel", 75, 100, 4, pc, Vector3(-0.2, 10, 0.2), rot20, Vector3(0.0005, 1, 0.001), false)
	whole_text = UI3D.make(percent_selector, "100", "pixel", 75, 100, 4, pc, Vector3(0.2, 10, -0.15), rot20, Vector3(0.0005, 0.001, 0.001), true)
	three_text = UI3D.make(percent_selector, "75", "pixel", 75, 100, 4, pc, Vector3(0.2, 10, 0.2), rot20, Vector3(0.0005, 1, 0.001), false)
	_text_state[quarter_text] = {"pos": Vector3(-0.2, 10, -0.15), "scale": Vector3(0.0005, 1, 0.001)}
	_text_state[half_text] = {"pos": Vector3(-0.2, 10, 0.2), "scale": Vector3(0.0005, 1, 0.001)}
	_text_state[whole_text] = {"pos": Vector3(0.2, 10, -0.15), "scale": Vector3(0.0005, 0.001, 0.001)}
	_text_state[three_text] = {"pos": Vector3(0.2, 10, 0.2), "scale": Vector3(0.0005, 1, 0.001)}

	vert_line = MeshInstance3D.new()
	vert_line.mesh = A.mesh("cube")
	vert_line.material_override = A.default_material()
	U.place(vert_line, Vector3(0, 5, 0), Quaternion.IDENTITY, Vector3(0.02, 0.05, 1))
	vert_line.visible = false
	percent_selector.add_child(vert_line)
	hor_line = MeshInstance3D.new()
	hor_line.mesh = A.mesh("cube")
	hor_line.material_override = A.default_material()
	U.place(hor_line, Vector3(0, 5, 0), Quaternion(0, 0.7071, 0, 0.7071), Vector3(0.02, 0.05, 1))
	hor_line.visible = false
	percent_selector.add_child(hor_line)
	selection_label = UI3D.make(percent_selector, "% of ships", "pixel", 27, 100, 4, white, Vector3(-1, 0, 0), rot20, Vector3(0.001, 0.005, 1), false)

	player_color_disc = MeshInstance3D.new()
	player_color_disc.mesh = A.mesh("ring")
	player_color_disc.material_override = A.car_paint(Settings.player_color)
	U.place(player_color_disc, Vector3(-0.0075, -0.018, 0.04), Quaternion(0.4772, 0, 0, 0.8788), Vector3(40, 10, 40))
	ui.add_child(player_color_disc)

	var rotx90 := Quaternion(0.7071, 0, 0, 0.7071)
	tips.append(_make_tip(ui, "PercentTip", "Select % of Ships", Vector3(0.05, 0.02, -0.05), rotx90, Vector3(-0.05, 0.0, 0.013), Vector3(-0.003, -0.008, 0)))
	tips.append(_make_tip(ui, "ScaleTip", "Drag World / \nPinch to Zoom", Vector3(0.072, -0.03, -0.12), rotx90, Vector3(-0.05, 0.035, -0.015), Vector3(-0.003, -0.008, 0)))
	tips.append(_make_tip(ui, "TriggerTip", "Click once to select or\nClick and drag to link", Vector3(0.055, -0.028, 0), rotx90, Vector3(-0.05, -0.04, 0), Vector3(-0.003, -0.008, 0)))

	laser_holder = Node3D.new()
	laser_holder.name = "LaserHolder"
	ui.add_child(laser_holder)
	if rig.vr:
		var lp := LaserPointer.new()
		laser_holder.add_child(lp)
		lp.setup(rig, hand, 0.015, 2.0)


static func _make_tip(parent: Node3D, n: String, txt: String, pos: Vector3, rot: Quaternion, a: Vector3, b: Vector3) -> Array:
	var tip := Node3D.new()
	tip.name = n
	U.place(tip, pos, rot)
	parent.add_child(tip)
	var l := Line3D.new(false, A.tex("one"), 0.01)
	l.set_tint(Color(0.5, 0.5, 0.5, 0.5)) # Font shader: plain white
	tip.add_child(l)
	l.set_local_points(Vector3(a.x, a.y, -a.z), Vector3(b.x, b.y, -b.z))
	var label := UI3D.make(tip, txt, "pixel", 0.0005, 500, 0, Color.WHITE, Vector3.ZERO, Quaternion.IDENTITY, Vector3.ONE)
	return [tip, l, label]


func set_player_color(c: Color) -> void:
	(player_color_disc.material_override as StandardMaterial3D).albedo_color = c


func set_tips_visible(v: bool) -> void:
	for t in tips:
		t[1].visible = v
		t[2].visible = v


func set_tip_width(w: float) -> void:
	for t in tips:
		t[1].width = w


func _process(_delta: float) -> void:
	if master == null:
		return
	_init_clicks_per_frame()
	if _menu_click:
		_toggle_pause()
	paused_text.visible = GameTime.paused() # versus: either player can pause
	var origin := hand.pointer_origin()
	var dir := hand.pointer_dir()
	var hits := Picker.raycast_all(origin, dir, distance)
	var flag := false
	var flag4 := false
	for hit in hits:
		var col: Picker.Col = hit["col"]
		var tag := col.tag
		if tag == "menuPlanet" or tag == "endPlanet" or tag == "pausePlanet" or tag == "mutePlanet":
			flag4 = true
			if _colliding_menu == null:
				_play(A.sfx("click_electronic_01"), 0.1)
				_colliding_menu = col.owner
				_colliding_menu.on_pointer_enter(true)
			if not _trigger_clicked:
				break
			if tag == "pausePlanet":
				_toggle_pause()
			elif tag == "mutePlanet":
				level.toggle_music_mute()
			else:
				GameTime.time_scale = 1.0
				_play(A.sfx("click_electronic_14"), 0.5)
				hand.vibrate(0.02, 0.02)
				level.return_to_menu()
			break
		if tag != "Planet" or not (GameTime.time_scale > 0.0):
			continue
		flag = true
		var pc: PlanetController = col.owner
		var sel = master.player["selected_planet"]
		if _trigger_clicked:
			hand.vibrate(0.05, 0.2)
			if sel == null:
				_dragging = true
			elif sel.node.global_position == pc.global_position:
				_dragging = true
				break
			_select(pc, false)
			break
		if _trigger_unpressed and _dragging:
			if sel != null and sel.node.global_position == pc.global_position:
				_dragging = false
			else:
				_dragging = false
				_select(pc, true)
		if _colliding_planet != null:
			if _colliding_planet.global_position == pc.global_position:
				break
			_colliding_planet.on_pointer_exit(false)
		_colliding_planet = pc
		_colliding_planet.on_pointer_enter(false)
		hand.vibrate(0.05, 0.2)
		_play(A.sfx("click_electronic_01"), 0.1)
		break
	if _pad_clicked or _trigger_clicked:
		left_handler.set_first_action_performed(true)
	_grip_logic()
	if GameTime.paused():
		return
	_pad_logic()
	if _pad_released:
		hand.vibrate(0.05, 0.2)
		selected_percent = _last_touched
	var sel2 = master.player["selected_planet"]
	if _trigger_unpressed and _dragging:
		if _magnet_planet != null:
			if sel2 != null and sel2.node.global_position == _magnet_planet.position:
				_dragging = false
			else:
				_dragging = false
				_select(_magnet_planet.node, true)
			_magnet_planet = null
		else:
			_dragging = false
			if sel2 != null:
				sel2.node.erase_line()
				sel2.node.erase_link()
				master.command_unlink(sel2)
	sel2 = master.player["selected_planet"]
	if _dragging and not flag and sel2 != null:
		var vector2 := _drag_point(sel2)
		sel2.node.draw_link_to_point(vector2)
		if GameTime.crossed(5):
			var hp := hand.global_position
			var num5 := _previous_position_r.distance_to(hp) / 2.0
			var num6: float = sel2.node.global_position.distance_to(hp)
			if rig.scale_factor() > 1.0:
				num6 /= rig.scale_factor() * 0.2
			hand.vibrate(num6 * num6 * 0.0005, num5 * num6 * 0.1)
			_previous_position_r = hp
		_magnet_planet = null
		for planet in master.get_planets():
			if _magnet_check(planet, vector2):
				sel2.node.draw_link_to_point(planet.position, planet)
				_magnet_planet = planet
				break
	if _dragging and flag and sel2 != null:
		sel2.node.erase_line()
	_after_pause_return(flag, flag4)
	if not flag and _trigger_clicked:
		_play(A.sfx("slide_electronic_01"), 0.3)
		_deselect()


func _after_pause_return(flag: bool, flag4: bool) -> void:
	if not flag4 and _colliding_menu != null:
		_colliding_menu.on_pointer_exit(false)
		_colliding_menu = null
	if not flag and _colliding_planet != null:
		_colliding_planet.on_pointer_exit(false)
		_colliding_planet = null


## Where the dragged link ends: VR = controller.position + forward * distance.
## Desktop: along the mouse ray, at the selected planet's distance from the camera.
func _drag_point(sel) -> Vector3:
	if rig.vr:
		return hand.global_position + hand.pointer_dir() * distance
	var o := hand.pointer_origin()
	var d := hand.pointer_dir()
	var depth: float = (sel.node.global_position - o).length()
	return o + d * depth


func _magnet_check(planet: Planet, tip: Vector3) -> bool:
	if rig.vr:
		return planet.position.distance_to(tip) < 1.5
	# desktop: snap to planets close to the mouse ray
	var o := hand.pointer_origin()
	var d := hand.pointer_dir().normalized()
	var t := (planet.position - o).dot(d)
	if t < 0.0:
		return false
	return (o + d * t).distance_to(planet.position) < maxf(1.5 * 0.35, planet.scale * 0.6)


func _toggle_pause() -> void:
	master.command_pause()
	paused_text.visible = GameTime.paused()


func _grip_logic() -> void:
	if not rig.vr:
		return
	if hand.gripped:
		if left_handler.is_gripped():
			var lp: Vector3 = rig.left.rig_local_position()
			var rp := hand.rig_local_position()
			if not _grip_pressed or not _left_grip_pressed:
				_grip_pressed = true
				_left_grip_pressed = true
				_base_rig_scale = rig.scale_factor()
				_base_distance = lp.distance_to(rp)
			var num := _base_distance - lp.distance_to(rp)
			var num2 := _base_rig_scale + num * SCALE_RATE
			if num2 > MIN_SCALE and num2 < MAX_SCALE:
				rig.set_scale_factor(num2)
			else:
				num2 = clampf(num2, MIN_SCALE, MAX_SCALE)
			if GameTime.crossed(5):
				var strength := (MAX_SCALE - num2) * SCALE_VIBRATION_STRENGTH
				hand.vibrate(0.05555, strength)
				rig.left.vibrate(0.05555, strength)
		else:
			_left_grip_pressed = false
		if not left_handler.is_gripped():
			if not _grip_pressed or not _left_grip_not_pressed:
				_grip_pressed = true
				_left_grip_not_pressed = true
				_base_rig_pos = rig.rig_position()
				_pos_base = hand.rig_local_position()
				_previous_position = hand.rig_local_position()
			var s := rig.scale_factor()
			var num3 := minf(s * 0.1, 1.0)
			var v := hand.rig_local_position() - _pos_base
			var p2 := _base_rig_pos + v * s * -1.0 / num3
			if absf(p2.x) < MOVEABLE_RANGE and absf(p2.y) < MOVEABLE_RANGE and absf(p2.z) < MOVEABLE_RANGE:
				rig.set_rig_position(p2)
			if GameTime.crossed(5):
				var num4 := _previous_position.distance_to(hand.rig_local_position())
				hand.vibrate(num4, num4)
				_previous_position = hand.rig_local_position()
		else:
			_left_grip_not_pressed = false
	else:
		_grip_pressed = false


func _pad_logic() -> void:
	if hand.pad_touched:
		_pad_touched = true
		if _pad_untouched:
			_pad_untouched = false
			hand.vibrate(0.05, 0.2)
			percent_selector.visible = true
			finger_sphere.visible = true
			for t in [whole_text, three_text, half_text, quarter_text]:
				t.visible = true
			vert_line.visible = true
			hor_line.visible = true
			selection_label.visible = true
		var axis := hand.pad_axis
		U.place(finger_sphere, Vector3(axis.x * 0.4, 0, axis.y * 0.4), Quaternion(0, 0.7071, 0, 0.7071), Vector3(0.08, 50, 0.08))
		for t in [quarter_text, half_text, three_text, whole_text]:
			_set_text_scale(t, Vector3(0.0005, 0.001, 0))
		_shrink_text(quarter_text, Vector3(-0.2, 10, -0.15))
		_shrink_text(half_text, Vector3(-0.2, 10, 0.15))
		_shrink_text(three_text, Vector3(0.2, 10, 0.15))
		_shrink_text(whole_text, Vector3(0.2, 10, -0.15))
		if axis.x < 0.0 and axis.y < 0.0:
			_set_text_scale(quarter_text, Vector3(0.0007, 0.0014, 0))
			_last_touched = 1
		if axis.x < 0.0 and axis.y > 0.0:
			_set_text_scale(half_text, Vector3(0.0007, 0.0014, 0))
			_last_touched = 2
		if axis.x > 0.0 and axis.y > 0.0:
			_set_text_scale(three_text, Vector3(0.0007, 0.0014, 0))
			_last_touched = 3
		if axis.x > 0.0 and axis.y < 0.0:
			_set_text_scale(whole_text, Vector3(0.0007, 0.0014, 0))
			_last_touched = 4
	else:
		_pad_untouched = true
		if _pad_touched:
			_pad_touched = false
			finger_sphere.visible = false
			whole_text.visible = selected_percent == 4
			three_text.visible = selected_percent == 3
			half_text.visible = selected_percent == 2
			quarter_text.visible = selected_percent == 1
			vert_line.visible = false
			hor_line.visible = false
			selection_label.visible = false
			_enlarge_text(whole_text)
			_enlarge_text(three_text)
			_enlarge_text(half_text)
			_enlarge_text(quarter_text)


# The texts keep their own (Unity) local TRS; we rebuild it whenever scale/position changes.
var _text_state := {}


func _text_rec(t: Label3D) -> Dictionary:
	if not _text_state.has(t):
		_text_state[t] = {"pos": Vector3.ZERO, "scale": Vector3.ONE}
	return _text_state[t]


func _apply_text(t: Label3D) -> void:
	var r := _text_rec(t)
	var s: Vector3 = r["scale"]
	if s.z == 0.0:
		s.z = 1.0
	U.place(t, r["pos"], Quaternion(0.1736, 0, 0, 0.9848), s)


func _set_text_scale(t: Label3D, s: Vector3) -> void:
	_text_rec(t)["scale"] = s
	_apply_text(t)


func _enlarge_text(t: Label3D) -> void:
	var r := _text_rec(t)
	r["scale"] = Vector3(0.0009, 0.0018, 0)
	r["pos"] = Vector3(0, 10, 0)
	_apply_text(t)
	t.text += "%"


func _shrink_text(t: Label3D, pos: Vector3) -> void:
	t.text = t.text.rstrip("%")
	_text_rec(t)["pos"] = pos
	_apply_text(t)


func get_percentage() -> float:
	return float(selected_percent) * 0.25


func is_gripped() -> bool:
	return hand.gripped


func _play(stream: AudioStream, volume: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = linear_to_db(volume)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _init_clicks_per_frame() -> void:
	# leftClickThisFrame
	if not hand.trigger_pressed:
		_trigger_unpressed = true
		_trigger_clicked = false
	else:
		_trigger_clicked = hand.trigger_pressed and _trigger_unpressed
		_trigger_unpressed = false
	# padPressedThisFrame
	if not hand.pad_pressed:
		_pad_unpressed = true
		_pad_clicked = false
	else:
		_pad_clicked = hand.pad_pressed and _pad_unpressed
		_pad_unpressed = false
	# menuClickThisFrame
	if not hand.menu_pressed:
		_menu_unpressed = true
		_menu_click = false
	else:
		_menu_click = hand.menu_pressed and _menu_unpressed
		_menu_unpressed = false
	# padReleasedThisFrame
	_pad_released = not hand.pad_pressed and _was_pad_pressed_last_frame
	_was_pad_pressed_last_frame = hand.pad_pressed


func _deselect() -> void:
	var sel = master.player["selected_planet"]
	if sel != null:
		sel.node.deselect()
		sel.node.erase_link()
		master.command_unlink(sel)


func _select(pc: PlanetController, link: bool) -> void:
	var sel = master.player["selected_planet"]
	var me := master.local_player
	if sel == null and pc.parent.player == me:
		pc.erase_link()
		master.command_unlink(pc.parent)
	if sel != null:
		if sel == pc.parent:
			_play(A.sfx("slide_electronic_01"), 0.3)
			pc.erase_link()
			master.command_unlink(pc.parent)
			pc.deselect()
			return
		var selected_planet: Planet = sel
		if selected_planet.player != me:
			return
		if selected_planet.node.planet_range < selected_planet.node.global_position.distance_to(pc.global_position):
			_play(A.sfx("click_electronic_16"), 0.3)
			return
		if master.get_planet_assignment(pc.parent) == selected_planet:
			pc.parent.node.erase_link()
		# send_wave + link bookkeeping (forwarded to the host in versus mode)
		master.command_send(selected_planet, pc.parent, get_percentage(), link)
		selected_planet.node.deselect()
		selected_planet.node.erase_link()
		if link:
			_play(A.sfx("click_electronic_14"), 0.5)
			selected_planet.node.draw_link_to_planet(pc.parent)
		else:
			_play(A.sfx("click_electronic_14"), 0.5)
	elif pc.parent.player == me:
		if link:
			_play(A.sfx("slide_electronic_01"), 0.3)
			pc.erase_link()
			master.command_unlink(pc.parent)
		else:
			_play(A.sfx("click_electronic_14"), 0.5)
			master.player["selected_planet"] = pc.parent
			pc.select()
