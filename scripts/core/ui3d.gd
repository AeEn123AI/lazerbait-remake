class_name UI3D
## Unity TextMesh -> Godot Label3D.
## In Unity a TextMesh glyph em is roughly fontSize * characterSize * 0.1 local units,
## so pixel_size = characterSize * 0.1 with font_size = fontSize reproduces the size.

# TextAnchor: 0 UpperLeft, 1 UpperCenter, 2 UpperRight, 3 MiddleLeft, 4 MiddleCenter,
#             5 MiddleRight, 6 LowerLeft, 7 LowerCenter, 8 LowerRight
const H := [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT]
const V := [VERTICAL_ALIGNMENT_TOP, VERTICAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_BOTTOM]


static func text(txt: String, font_name: String, character_size: float, font_size: int, anchor := 0,
		color := Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font = A.font(font_name)
	# keep glyph rasterisation sane; scale pixel_size accordingly
	var fs := font_size
	if fs <= 0:
		fs = 16 # Unity default dynamic font size
	var raster := clampi(fs, 16, 128)
	l.font_size = raster
	l.pixel_size = character_size * 0.1 * float(fs) / float(raster)
	l.horizontal_alignment = H[anchor % 3]
	l.vertical_alignment = V[anchor / 3]
	l.modulate = color
	l.outline_size = 0
	l.double_sided = true
	l.no_depth_test = false
	l.shaded = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.render_priority = 1
	return l


## Convenience: create text from a Unity TextMesh dump entry and place it.
static func make(parent: Node, txt: String, font_name: String, character_size: float, font_size: int,
		anchor: int, color: Color, pos: Vector3, rot: Quaternion, scl: Vector3, visible := true) -> Label3D:
	var l := text(txt, font_name, character_size, font_size, anchor, color)
	var s := scl
	if s.z == 0.0:
		s.z = 1.0
	U.place(l, pos, rot, s)
	l.visible = visible
	parent.add_child(l)
	return l
