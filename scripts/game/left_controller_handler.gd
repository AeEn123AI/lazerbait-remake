class_name LeftControllerHandler
extends Node
## Port of LeftControllerHandler.cs plus the objects under "Controller (left)" in the sample
## scene: ship limit texts, the in-game menu planets (Quit to Menu / Pause / Mute Music),
## tooltips and the mini-map.

const MOVEABLE_RANGE := 100.0
const CHANGE_FRAMES := 15
const TIME_BETWEEN_UPDATES := 1.0

var rig: PlayerRig
var hand: Hand
var master: MasterController
var right_controller: ClickHandler

var ship_count_text: Label3D
var ship_count_label: Label3D
var menu_planet: PlanetController
var pause_planet: PlanetController
var mute_planet: PlanetController
var menu_text: Label3D
var pause_text: Label3D
var mute_text: Label3D
var menu_tip: Array            # [tip node, line, label]
var tool_tips: Array = []      # MiniMapTip, TriggerTip, ScaleTip, PercentTip, DragTip -> [node, line, label]

var _mini_map := {}            # Vector3 -> MeshInstance3D
var _mini_list: Array = []
var _color_map := {}           # Color(html) -> MeshInstance3D
var _text_map := {}            # Color(html) -> Label3D
var _color_counts: Array = []  # [[Color, count], ...] in insertion order
var _original_scale := 0.01
var _first := true
var _last_updated_time := 0.0
var _trigger_unpressed := true
var _left_click := false
var _right_click := false
var _pad_unpressed := true
var _growing := false
var _shrinking := false
var _current_frames := 0
var _grip_pressed := false
var _camera_pos := Vector3.ZERO
var _pos_base := Vector3.ZERO
var _previous_position := Vector3.ZERO
var first_action_performed := false


func setup(p_rig: PlayerRig, p_master: MasterController, p_right: ClickHandler) -> void:
	rig = p_rig
	hand = rig.left
	master = p_master
	right_controller = p_right
	_build_ui()
	# Start(): the right controller's "% of ships" label is coloured red
	right_controller.selection_label.modulate = Color.RED
	_enable_tips()


func _build_ui() -> void:
	var ui := hand.ui
	var w := Color.WHITE
	var rotx90 := Quaternion(0.7071, 0, 0, 0.7071)
	var rotx60 := Quaternion(0.5, 0, 0, 0.866)
	ship_count_text = UI3D.make(ui, "0/0", "pixel", 27, 100, 7, w, Vector3(0, 0.01, 0.05), rotx90, Vector3(0.00025, 0.00025, 0.01))
	ship_count_label = UI3D.make(ui, "Ship Limit", "pixel", 27, 100, 7, w, Vector3(0, 0.01, 0.1), rotx90, Vector3(0.00017, 0.00017, 0.01))
	menu_text = UI3D.make(ui, "Quit to Menu", "pixel", 27, 100, 4, w, Vector3(0.05, 0.02, 0.1), rotx60, Vector3(0.0001, 0.0001, 0.001), false)
	menu_planet = _menu_sphere(ui, "ReturnToMenuPlanet", Vector3(0.05, 0.01, 0.05), "endPlanet")
	pause_planet = _menu_sphere(ui, "PausePlanet", Vector3(-0.05, 0.01, 0.05), "pausePlanet")
	pause_text = UI3D.make(ui, "Pause", "pixel", 27, 100, 4, w, Vector3(-0.05, 0.02, 0.1), rotx60, Vector3(0.0001, 0.0001, 0.001), false)
	mute_planet = _menu_sphere(ui, "MutePlanet", Vector3(0, 0.05, 0.14), "mutePlanet")
	mute_text = UI3D.make(ui, "Mute Music", "pixel", 27, 100, 4, w, Vector3(0, 0.06, 0.2), rotx60, Vector3(0.0001, 0.0001, 0.001), false)
	menu_tip = ClickHandler._make_tip(ui, "MenuTip", "Menu", Vector3(0.05, 0.02, -0.03), rotx90, Vector3(-0.05, -0.015, 0.013), Vector3(-0.003, -0.008, 0))
	var drag_tip := ClickHandler._make_tip(ui, "DragTip", "Drag World / \nPinch to Zoom", Vector3(0.072, -0.03, -0.085), rotx90, Vector3(-0.05, 0, -0.015), Vector3(-0.003, -0.008, 0))
	var mini_tip := ClickHandler._make_tip(ui, "MiniMapTip", "Map / Stats", Vector3(0.055, -0.028, 0), rotx90, Vector3(-0.05, -0.04, 0), Vector3(-0.003, -0.008, 0))
	# ToolTips = MiniMapTip, TriggerTip, ScaleTip, PercentTip, DragTip
	var rt: Array = right_controller.tips # PercentTip, ScaleTip, TriggerTip
	tool_tips = [mini_tip, rt[2], rt[1], rt[0], drag_tip]
	if not rig.vr:
		# no grips on desktop: those tips would be misleading
		var hint := "Two fingers:\nmove the view" if rig.touch else "Move: WASD/QE\nLook: Right Mouse"
		for t in [drag_tip, rt[1]]:
			t[2].text = hint


func _menu_sphere(parent: Node3D, n: String, pos: Vector3, tag: String) -> PlanetController:
	var p := PlanetController.new()
	p.name = n
	U.place(p, pos, Quaternion.IDENTITY, Vector3(0.06, 0.06, 0.06))
	parent.add_child(p)
	p.build(false, Color(0, 0.192, 0.287, 1), 0.7, tag)
	p.start()
	p.mesh.visible = false
	p.set_collider_enabled(false)
	return p


func set_first_action_performed(v: bool) -> void:
	first_action_performed = v


func is_gripped() -> bool:
	return hand.gripped


func _process(_delta: float) -> void:
	if master == null:
		return
	_init_clicks_per_frame()
	if GameTime.crossed(10):
		var x := rig.scale_factor()
		for t in tool_tips:
			t[1].width = 0.001 * x
		menu_tip[1].width = 0.001 * x
	if _first and not master.planets.is_empty(): # a versus client waits for the map
		_init_mini_map()
		_first = false
	if _last_updated_time + TIME_BETWEEN_UPDATES < GameTime.realtime():
		_last_updated_time = GameTime.realtime()
		_update_mini_map()
		_update_ship_count_text()
	if _left_click:
		_enable_mini_map()
		_shrinking = false
		_growing = true
	elif _trigger_unpressed:
		_growing = false
		_shrinking = true
	if _growing and _current_frames < CHANGE_FRAMES:
		_current_frames += 1
		_grow_map()
	else:
		_growing = false
	if _shrinking and _current_frames > 0:
		_current_frames -= 1
		_shrink_map()
	elif _shrinking and _current_frames <= 0:
		_shrinking = false
		_disable_mini_map()
	if rig.vr and hand.gripped and not right_controller.is_gripped():
		if not _grip_pressed:
			_grip_pressed = true
			_camera_pos = rig.rig_position()
			_pos_base = hand.rig_local_position()
			_previous_position = hand.rig_local_position()
		var s := rig.scale_factor()
		var num := minf(s * 0.1, 1.0)
		var v := hand.rig_local_position() - _pos_base
		var p := _camera_pos + v * s * -1.0 / num
		if absf(p.x) < MOVEABLE_RANGE and absf(p.y) < MOVEABLE_RANGE and absf(p.z) < MOVEABLE_RANGE:
			rig.set_rig_position(p)
		if GameTime.crossed(5):
			var num2 := _previous_position.distance_to(hand.rig_local_position())
			hand.vibrate(num2, num2)
			_previous_position = hand.rig_local_position()
	else:
		_grip_pressed = false
	if hand.trigger_pressed:
		first_action_performed = true
		ship_count_text.visible = false
		ship_count_label.visible = false
	if hand.pad_pressed:
		first_action_performed = true
		_enable_menu_planet()
		_enable_tips()
		ship_count_text.visible = false
		ship_count_label.visible = false
	elif not hand.trigger_pressed:
		_disable_menu_planet()
		_disable_tips()
		ship_count_text.visible = true
		ship_count_label.visible = true
	else:
		_disable_tips()
	if not first_action_performed:
		_enable_tips()


func _update_ship_count_text() -> void:
	var count := master.get_player_ship_count(master.local_player)
	var num := master.get_player_ship_limit(master.local_player) + 1
	ship_count_text.text = "%d/%d" % [count, num]
	ship_count_text.modulate = Color.RED if count > num else Color.WHITE


func _col_key(c: Color) -> String:
	return c.to_html(true)


## InitMiniMap(). The original placed the mini planets using world axes at the moment the
## game started; we use the controller's own axes (as if it was held level at start).
func _init_mini_map() -> void:
	var ui := hand.ui
	var max_x := master.environment.max_x
	var q_u := Quaternion(Vector3(1, 0, 0), deg_to_rad(60.0)) * Quaternion(Vector3(0, 1, 0), deg_to_rad(-90.0))
	for item in master.get_mini_map():
		var g: Vector3 = item[0]
		var key_u := Vector3(g.x, g.y, -g.z)
		var local_u := Vector3(max_x / 200.0, 0, 0) + key_u * 0.01
		local_u = q_u * local_u
		var mi := MeshInstance3D.new()
		mi.mesh = A.mesh("sphere")
		mi.material_override = A.lambert1(item[1])
		mi.position = Vector3(local_u.x, local_u.y, -local_u.z)
		mi.scale = Vector3.ONE * _original_scale
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ui.add_child(mi)
		_mini_map[g] = mi
		_mini_list.append(mi)
	_update_mini_map()
	var num := 0.0
	for cc in _color_counts:
		num += 1.0
		var c: Color = cc[0]
		if c.is_equal_approx(Color(1, 1, 1, 1)):
			continue
		var g2 := MeshInstance3D.new()
		g2.mesh = A.mesh("sphere")
		g2.material_override = A.lambert1(c)
		var num2 := num * -0.018
		g2.position = Vector3(0.05, 0, -num2)
		g2.scale = Vector3.ONE * 0.01
		g2.visible = false
		ui.add_child(g2)
		_color_map[_col_key(c)] = g2
		var t := UI3D.make(ui, str(cc[1]), "arial", 1.0, 16, 0, Color.WHITE, Vector3(0.06, 0, num2 + 0.007), Quaternion(0.7071, 0, 0, 0.7071), Vector3(0.01, 0.01, 0.01), false)
		_text_map[_col_key(c)] = t


func _update_mini_map() -> void:
	_color_counts.clear()
	for item in master.get_mini_map():
		var g: Vector3 = item[0]
		var c: Color = item[1]
		if _mini_map.has(g):
			(_mini_map[g].material_override as StandardMaterial3D).albedo_color = c
		var found := false
		for cc in _color_counts:
			if (cc[0] as Color).is_equal_approx(c):
				cc[1] += 1
				found = true
				break
		if not found:
			_color_counts.append([c, 1])
	for k in _text_map.keys():
		_text_map[k].text = "0"
	for cc in _color_counts:
		var c: Color = cc[0]
		if not c.is_equal_approx(Color(1, 1, 1, 1)) and _text_map.has(_col_key(c)):
			_text_map[_col_key(c)].text = str(cc[1])


func _enable_tips() -> void:
	for t in tool_tips:
		t[1].visible = true
		t[2].visible = true


func _disable_tips() -> void:
	for t in tool_tips:
		t[1].visible = false
		t[2].visible = false


func _enable_mini_map() -> void:
	menu_tip[1].visible = false
	menu_tip[2].visible = false
	for m in _mini_list:
		m.visible = true
	for m in _color_map.values():
		m.visible = true
	for t in _text_map.values():
		t.visible = true


func _disable_mini_map() -> void:
	menu_tip[1].visible = true
	menu_tip[2].visible = true
	for m in _mini_list:
		m.visible = false
	for m in _color_map.values():
		m.visible = false
	for t in _text_map.values():
		t.visible = false


func _enable_menu_planet() -> void:
	for p in [menu_planet, pause_planet, mute_planet]:
		p.mesh.visible = true
		p.set_collider_enabled(true)
	for t in [menu_text, pause_text, mute_text]:
		t.visible = true


func _disable_menu_planet() -> void:
	for p in [menu_planet, pause_planet, mute_planet]:
		p.mesh.visible = false
		p.set_collider_enabled(false)
	for t in [menu_text, pause_text, mute_text]:
		t.visible = false


func _grow_map() -> void:
	for m in _mini_list:
		if m.scale.x < _original_scale - 1e-6:
			m.scale = m.scale + Vector3.ONE * 0.01


func _shrink_map() -> void:
	for m in _mini_list:
		if m.scale.x > 1e-6:
			m.scale = (m.scale - Vector3.ONE * 0.01).max(Vector3.ONE * 1e-6)
		else:
			_disable_mini_map()


func _init_clicks_per_frame() -> void:
	if not hand.trigger_pressed:
		_trigger_unpressed = true
		_left_click = false
	else:
		_left_click = hand.trigger_pressed and _trigger_unpressed
		_trigger_unpressed = false
	if not hand.pad_pressed:
		_pad_unpressed = true
		_right_click = false
	else:
		_right_click = hand.pad_pressed and _pad_unpressed
		_pad_unpressed = false
