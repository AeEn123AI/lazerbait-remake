class_name TouchControls
extends CanvasLayer
## Touch input for phones/tablets (non-VR). Replaces the mouse/keyboard emulation of the desktop rig:
##   one finger          pointer (tap = click, drag = link / drag-to-link)
##   two fingers drag    look around or pan (toggle with the "Pan"/"Look" button)
##   two fingers pinch   move forward / back
## plus on-screen buttons for what the keyboard did (% of ships, mini-map, in-game menu, pause).

signal join_requested

const BUTTON_COLOR := Color(0.1, 0.12, 0.14, 0.55)
const BUTTON_DOWN := Color(0.35, 0.55, 0.75, 0.75)
const BUTTON_ON := Color(0.2, 0.5, 0.35, 0.7)

var rig: PlayerRig
var layout := "menu"            # "menu" | "game"
var two_finger_look := true     # two-finger drag looks (true) or pans (false)

var _canvas: Control
var _buttons: Array = []        # {id, label, rect, hold, toggle}
var _button_touch := {}         # touch index -> button id
var _world_touch := {}          # touch index -> position
var _gesture := false
var _last_centre := Vector2.ZERO
var _last_dist := 0.0
var _pending_press := false     # single finger down, waiting to see whether a second one follows
var _pending_time := 0.0
var _press_frames := 0          # frames left to keep the pointer trigger held after a quick tap
var _map_held := false
var _px := 1.0


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_buttons)
	add_child(_canvas)
	get_viewport().size_changed.connect(_layout)
	DisplayServer.screen_set_keep_on(true)
	_layout()


func set_layout(l: String) -> void:
	layout = l
	two_finger_look = l == "menu"
	_layout()


func map_held() -> bool:
	return _map_held


## True if a screen position is on one of our buttons (the emulated mouse click must be ignored there).
func over_button(p: Vector2) -> bool:
	for b in _buttons:
		if b["rect"].grow(8).has_point(p):
			return true
	return false


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var u := clampf(minf(vs.x, vs.y) * 0.13, 52.0, 110.0)
	_px = u
	var m := u * 0.25
	_buttons.clear()
	var add := func(id: String, label: String, x: float, y: float, w := 1.0, hold := false, toggle := false) -> void:
		_buttons.append({"id": id, "label": label, "rect": Rect2(x, y, u * w, u), "hold": hold, "toggle": toggle})
	add.call("mode", "Look" if two_finger_look else "Pan", vs.x - u - m, m)
	if layout == "game":
		add.call("pause", "||", vs.x - 2.0 * (u + m), m)
		add.call("menu", "Menu", m, vs.y - u - m, 1.4, false, true)
		add.call("map", "Map", m + u * 1.4 + m, vs.y - u - m, 1.2, true)
		for i in 4:
			add.call("pct%d" % (i + 1), "%d%%" % (25 * (i + 1)), vs.x - u - m, vs.y - (4 - i) * (u + m) - m * 0.0)
	else:
		add.call("join", "Join", vs.x - 2.0 * (u + m) - u * 0.4, m, 1.4)
	_canvas.queue_redraw()


func _draw_buttons() -> void:
	var font := A.font("pixel")
	for b in _buttons:
		var r: Rect2 = b["rect"]
		var down: bool = _button_touch.values().has(b["id"])
		var on: bool = b["id"] == "menu" and rig != null and rig.left.desktop_pad_latched
		var style := StyleBoxFlat.new()
		style.bg_color = BUTTON_DOWN if down else (BUTTON_ON if on else BUTTON_COLOR)
		style.set_corner_radius_all(int(_px * 0.2))
		style.border_color = Color(1, 1, 1, 0.5)
		style.set_border_width_all(2)
		_canvas.draw_style_box(style, r)
		var fs := int(_px * 0.42)
		var sz := font.get_string_size(b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		_canvas.draw_string(font, r.position + Vector2((r.size.x - sz.x) * 0.5, (r.size.y + sz.y * 0.55) * 0.5), b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))


func _button_at(p: Vector2) -> Dictionary:
	for b in _buttons:
		if b["rect"].grow(8).has_point(p):
			return b
	return {}


func _input(event: InputEvent) -> void:
	if rig == null:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _world_touch.has(d.index):
			_world_touch[d.index] = d.position
			if _gesture:
				_update_gesture()


func _touch_down(idx: int, pos: Vector2) -> void:
	var b := _button_at(pos)
	if not b.is_empty():
		_button_touch[idx] = b["id"]
		_press_button(b["id"], true)
		_canvas.queue_redraw()
		return
	_world_touch[idx] = pos
	if _world_touch.size() == 1:
		_pending_press = true
		_pending_time = 0.0
	elif _world_touch.size() >= 2:
		# A second finger: this is a camera gesture, not a click.
		_pending_press = false
		_press_frames = 0
		rig.right.desktop_trigger = false
		_gesture = true
		_reset_gesture()


func _touch_up(idx: int) -> void:
	if _button_touch.has(idx):
		var id: String = _button_touch[idx]
		_button_touch.erase(idx)
		_press_button(id, false)
		_canvas.queue_redraw()
		return
	if not _world_touch.has(idx):
		return
	_world_touch.erase(idx)
	if _pending_press and _world_touch.is_empty():
		# Quick tap: hold the trigger for a few frames so the click registers.
		_pending_press = false
		rig.right.desktop_trigger = true
		_press_frames = 3
	elif _world_touch.is_empty():
		rig.right.desktop_trigger = false
		_gesture = false
	elif _world_touch.size() == 1 and _gesture:
		_reset_gesture() # keep the gesture alive for the remaining finger (no accidental click)


func _reset_gesture() -> void:
	var pts := _world_touch.values()
	if pts.size() >= 2:
		_last_centre = (pts[0] + pts[1]) * 0.5
		_last_dist = pts[0].distance_to(pts[1])
	elif pts.size() == 1:
		_last_centre = pts[0]
		_last_dist = 0.0


func _update_gesture() -> void:
	if not rig.desktop_controls_enabled:
		return
	var pts := _world_touch.values()
	if pts.size() < 2:
		return
	var centre: Vector2 = (pts[0] + pts[1]) * 0.5
	var dist: float = pts[0].distance_to(pts[1])
	rig.touch_camera(centre - _last_centre, dist - _last_dist, two_finger_look)
	_last_centre = centre
	_last_dist = dist


func _press_button(id: String, down: bool) -> void:
	match id:
		"map":
			_map_held = down
		"mode":
			if down:
				two_finger_look = not two_finger_look
				_layout()
		"menu":
			if down:
				rig.left.desktop_pad_latched = not rig.left.desktop_pad_latched
		"pause":
			if down:
				rig.right.desktop_press_menu()
		"join":
			if down:
				join_requested.emit()
		_:
			if down and id.begins_with("pct"):
				rig.right.desktop_select_percent(int(id.substr(3)))


func _process(delta: float) -> void:
	if rig == null:
		return
	if _pending_press:
		_pending_time += delta
		if _pending_time > 0.07:
			# Still a single finger: start the press now so dragging (links) works.
			_pending_press = false
			rig.right.desktop_trigger = true
	if _press_frames > 0:
		_press_frames -= 1
		if _press_frames == 0:
			rig.right.desktop_trigger = false
	_canvas.queue_redraw()
