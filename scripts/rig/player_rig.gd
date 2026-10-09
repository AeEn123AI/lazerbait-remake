class_name PlayerRig
extends Node3D
## The SteamVR [CameraRig] equivalent, for both VR and desktop.
##
## Unity scaled the whole [CameraRig] (10x in game) to make the player a giant over the
## map; here VR uses XROrigin3D.world_scale and everything parented to the rig
## (`content`, the hand UIs) is scaled by the same factor.
##
## Desktop: a free camera standing at the same eye height with two "virtual controllers"
## held in view, so the original controller-mounted UI (ship limit, % selector, mini-map,
## in-game menu planets) works the same way with mouse and keyboard.

signal desktop_help_toggled(visible: bool)

const EYE_HEIGHT := 1.7 # metres (rig units) for desktop
var vr := false
var origin: Node3D                 # XROrigin3D in VR, plain Node3D on desktop
var head: Camera3D                 # XRCamera3D in VR
var left: Hand
var right: Hand
var content: Node3D                # children of the Unity [CameraRig]
var _scale := 1.0
var _controller_models: Array = [] # VR controller models (grip pose)

# desktop camera state
var yaw := 0.0
var pitch := 0.0
var _looking := false
var _panning := false
var desktop_hud: CanvasLayer
var touch: TouchControls          # phones/tablets only
var _help_label: Label
var _help_visible := true
var desktop_controls_enabled := true
var desktop_move_speed := 2.0      # metres (rig units) / second
var allow_vertical := true
## Desktop menu: keep `content` where it is so WASD walks through the menu instead of carrying it along.
var content_fixed := false

var _fade_mesh: MeshInstance3D
var _fade_mat: ShaderMaterial
var _fade_alpha := 0.0
var _fade_target := 0.0
var _fade_speed := 1.0


func _ready() -> void:
	vr = XRManager.vr
	content = Node3D.new()
	content.name = "RigContent"
	add_child(content)
	if vr:
		_build_vr()
	else:
		_build_desktop()
	_build_fader()


func _build_vr() -> void:
	var o := XROrigin3D.new()
	o.name = "XROrigin3D"
	add_child(o)
	origin = o
	var cam := XRCamera3D.new()
	cam.name = "XRCamera3D"
	cam.near = 0.05
	cam.far = 20000.0
	o.add_child(cam)
	head = cam
	for is_left in [true, false]:
		var c := XRController3D.new()
		c.name = "LeftController" if is_left else "RightController"
		c.tracker = &"left_hand" if is_left else &"right_hand"
		c.pose = &"aim"
		o.add_child(c)
		var h := Hand.new()
		h.name = "LeftHand" if is_left else "RightHand"
		h.controller = c
		c.add_child(h)
		h.setup(self, is_left, true)
		_add_controller_model(h, is_left)
		if is_left:
			left = h
		else:
			right = h
	cam.current = true


func _add_controller_model(h: Hand, is_left: bool) -> void:
	# SteamVR_RenderModel equivalent. Render models are defined relative to the *grip* pose,
	# while the game's controller UI follows the aim pose, so the model gets its own
	# grip-pose controller. Its scale follows the world scale like the [CameraRig] children did.
	var grip := XRController3D.new()
	grip.name = ("Left" if is_left else "Right") + "GripController"
	grip.tracker = &"left_hand" if is_left else &"right_hand"
	grip.pose = &"grip"
	origin.add_child(grip)
	var model := ControllerModel.new()
	model.name = "Model"
	grip.add_child(model)
	model.setup(is_left)
	_controller_models.append(model)


func _fallback_controller_mesh() -> Node3D:
	# A simple wand-like controller (used when the runtime has no render models, and on desktop).
	var n := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.09)
	mat.roughness = 0.45
	mat.metallic = 0.2
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.016
	cyl.bottom_radius = 0.019
	cyl.height = 0.14
	body.mesh = cyl
	body.material_override = mat
	body.rotation_degrees = Vector3(-90 + 25, 0, 0)
	body.position = Vector3(0, -0.035, 0.075)
	n.add_child(body)
	var head_m := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.022
	tor.outer_radius = 0.035
	head_m.mesh = tor
	head_m.material_override = mat
	head_m.rotation_degrees = Vector3(80, 0, 0)
	head_m.position = Vector3(0, 0.0, -0.005)
	n.add_child(head_m)
	return n


func _build_desktop() -> void:
	origin = Node3D.new()
	origin.name = "DesktopOrigin"
	add_child(origin)
	var cam := Camera3D.new()
	cam.name = "DesktopCamera"
	cam.near = 0.05
	cam.far = 20000.0
	cam.fov = 70.0
	origin.add_child(cam)
	head = cam
	cam.current = true
	for is_left in [true, false]:
		var h := Hand.new()
		h.name = "LeftHand" if is_left else "RightHand"
		cam.add_child(h)
		h.setup(self, is_left, false)
		var model := Node3D.new()
		model.name = "Model"
		model.add_child(_fallback_controller_mesh())
		h.ui.add_child(model)
		if is_left:
			left = h
		else:
			right = h
	_layout_desktop_hands()
	desktop_hud = CanvasLayer.new()
	desktop_hud.layer = 5
	add_child(desktop_hud)
	_help_label = Label.new()
	_help_label.add_theme_font_override("font", A.font("pixel"))
	_help_label.add_theme_font_size_override("font_size", 22)
	_help_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_help_label.add_theme_constant_override("outline_size", 4)
	_help_label.position = Vector2(12, 8)
	desktop_hud.add_child(_help_label)
	set_help_text("")
	if XRManager.touch:
		touch = TouchControls.new()
		touch.name = "TouchControls"
		touch.rig = self
		add_child(touch)
		# Logical pixels follow the display density so text and buttons stay a usable size.
		get_window().content_scale_factor = clampf(DisplayServer.screen_get_scale(), 1.0, 3.0)


## Layout of the on-screen buttons: "menu" or "game". No-op without touch controls.
func set_touch_layout(l: String) -> void:
	if touch:
		touch.set_layout(l)


## Two-finger gesture: `drag` moves the view (look or pan), `pinch` (pixels) moves forward / back.
func touch_camera(drag: Vector2, pinch: float, look: bool) -> void:
	if look:
		yaw -= drag.x * 0.006
		pitch -= drag.y * 0.006
		_apply_look()
	else:
		var b := head.global_transform.basis
		var k := 0.006 * _scale
		set_rig_position(origin.global_position - b.x * drag.x * k + b.y * drag.y * k)
	if absf(pinch) > 0.0:
		var dir := -head.global_transform.basis.z
		if not allow_vertical:
			dir.y = 0.0
			dir = dir.normalized()
		set_rig_position(origin.global_position + dir * pinch * 0.012 * _scale)


func set_help_text(t: String) -> void:
	if _help_label:
		_help_label.text = t
		_help_label.visible = _help_visible and t != ""


func _layout_desktop_hands() -> void:
	# Virtual controllers held in front of the camera (positions in metres, scaled with the rig).
	var s := _scale
	if left:
		left.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(58), deg_to_rad(14), 0)), Vector3(-0.27, -0.22, -0.52) * s)
	if right:
		right.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(58), deg_to_rad(-14), 0)), Vector3(0.27, -0.22, -0.52) * s)


func _build_fader() -> void:
	_fade_mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_fade_mesh.mesh = q
	_fade_mat = ShaderMaterial.new()
	_fade_mat.shader = A.shader("fade")
	_fade_mat.render_priority = 127
	_fade_mesh.material_override = _fade_mat
	_fade_mesh.extra_cull_margin = 16384.0
	_fade_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fade_mesh.position = Vector3(0, 0, -0.1)
	head.add_child(_fade_mesh)
	_set_fade(0.0)


func _set_fade(a: float) -> void:
	_fade_alpha = a
	_fade_mat.set_shader_parameter("color", Color(0, 0, 0, a))
	_fade_mesh.visible = a > 0.001


## SteamVR_Fade: fade to black (1) or back (0) over `duration` seconds.
func fade_to(target: float, duration: float) -> void:
	_fade_target = target
	_fade_speed = 1.0 / maxf(duration, 0.001)


func fade_done() -> bool:
	return is_equal_approx(_fade_alpha, _fade_target)


func set_fade_immediate(a: float) -> void:
	_fade_target = a
	_set_fade(a)


# ------------------------------------------------------------------ rig transform

## Unity: cameraRig.transform.localScale.x
func scale_factor() -> float:
	return _scale


func set_scale_factor(s: float) -> void:
	_scale = s
	if vr:
		(origin as XROrigin3D).world_scale = s
		for m in _controller_models:
			m.scale = Vector3.ONE * s
		head.near = 0.05 * s
	else:
		head.position = Vector3(0, EYE_HEIGHT * s, 0)
		head.near = 0.02 * s
		_layout_desktop_hands()
	_update_content()


## Unity: cameraRig.transform.position
func rig_position() -> Vector3:
	return origin.global_position


func set_rig_position(p: Vector3) -> void:
	origin.global_position = p
	_update_content()


func to_rig_local(world: Vector3) -> Vector3:
	return (world - origin.global_position) / _scale


func head_position() -> Vector3:
	return head.global_position


func _update_content() -> void:
	if content_fixed:
		return
	content.global_transform = Transform3D(origin.global_transform.basis.orthonormalized().scaled(Vector3.ONE * _scale), origin.global_position)


func reset_desktop_view(look_target: Vector3) -> void:
	if vr:
		return
	var from := head.global_position
	var d := (look_target - from)
	if d.length() < 0.001:
		return
	d = d.normalized()
	yaw = atan2(-d.x, -d.z)
	pitch = asin(clampf(d.y, -1.0, 1.0))
	_apply_look()


func set_desktop_yaw_pitch(y: float, p: float) -> void:
	yaw = y
	pitch = p
	_apply_look()


func _apply_look() -> void:
	pitch = clampf(pitch, deg_to_rad(-85), deg_to_rad(85))
	head.basis = Basis.from_euler(Vector3(pitch, yaw, 0), EULER_ORDER_YXZ)


# ------------------------------------------------------------------ desktop input

func mouse_ray_origin() -> Vector3:
	var vp := get_viewport()
	return head.project_ray_origin(vp.get_mouse_position())


func mouse_ray_dir() -> Vector3:
	var vp := get_viewport()
	return head.project_ray_normal(vp.get_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	if vr:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if touch == null: # touch controls drive the pointer themselves
				right.desktop_trigger = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed and desktop_controls_enabled
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed and desktop_controls_enabled
		elif mb.pressed and desktop_controls_enabled and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var dir := -head.global_transform.basis.z
			var step := (1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0) * 0.35 * _scale
			if not allow_vertical:
				dir.y = 0.0
				dir = dir.normalized()
			set_rig_position(origin.global_position + dir * step)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _looking:
			yaw -= mm.relative.x * 0.005
			pitch -= mm.relative.y * 0.005
			_apply_look()
		elif _panning:
			var b := head.global_transform.basis
			var k := 0.004 * _scale
			set_rig_position(origin.global_position - b.x * mm.relative.x * k + b.y * mm.relative.y * k)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_1, KEY_KP_1: right.desktop_select_percent(1)
			KEY_2, KEY_KP_2: right.desktop_select_percent(2)
			KEY_3, KEY_KP_3: right.desktop_select_percent(3)
			KEY_4, KEY_KP_4: right.desktop_select_percent(4)
			KEY_P, KEY_PAUSE: right.desktop_press_menu()
			KEY_ESCAPE: left.desktop_pad_latched = not left.desktop_pad_latched
			KEY_F1, KEY_H:
				_help_visible = not _help_visible
				if _help_label:
					_help_label.visible = _help_visible and _help_label.text != ""
				desktop_help_toggled.emit(_help_visible)
			KEY_F11:
				var w := get_window()
				w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


func _process(delta: float) -> void:
	# fade
	if not is_equal_approx(_fade_alpha, _fade_target):
		_set_fade(move_toward(_fade_alpha, _fade_target, _fade_speed * delta))
	if not vr:
		left.desktop_trigger = Input.is_key_pressed(KEY_TAB) or (touch != null and touch.map_held())
		if desktop_controls_enabled:
			var mv := Vector3.ZERO
			if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): mv.z -= 1
			if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): mv.z += 1
			if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): mv.x -= 1
			if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): mv.x += 1
			if allow_vertical:
				if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE): mv.y += 1
				if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL): mv.y -= 1
			if mv != Vector3.ZERO:
				var basis := Basis(Vector3.UP, yaw)
				var w := basis * Vector3(mv.x, 0, mv.z) + Vector3(0, mv.y, 0)
				var sp := desktop_move_speed * _scale * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
				set_rig_position(origin.global_position + w.normalized() * sp * delta)
	left.poll()
	right.poll()
	_update_content()


## Remove level specific UI from the hands (keeps the controller models).
func clear_hand_ui() -> void:
	content_fixed = false
	if left:
		left.desktop_pad_latched = false
	for h in [left, right]:
		for c in h.ui.get_children():
			if c.name != "Model":
				c.queue_free()
	for c in content.get_children():
		c.queue_free()
