// Camera-facing line segment, equivalent to a 2-point Unity LineRenderer.
// UV.x runs 0..1 along the segment, UV.y 0..1 across it.
// Colour model follows Unity's legacy particle shaders:
//   "Particles/Alpha Blended": col = 2 * vertexColor * _TintColor * tex   (blend_mode = mix)
//   "Particles/Additive":      col = 2 * vertexColor * _TintColor * tex   (blend_mode = add, rgb *= a)

#include "res://shaders/color_space.gdshaderinc"

uniform vec3 p0 = vec3(0.0);
uniform vec3 p1 = vec3(0.0, 0.0, 1.0);
uniform float width = 0.2;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
// Linear-space tint (already gamma->linear converted, HDR allowed, like Unity in linear colour space)
uniform vec4 tint = vec4(1.0);
uniform vec4 vcolor : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);

varying vec2 v_uv;

void vertex() {
	vec3 pos = mix(p0, p1, UV.x);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 dir = p1 - p0;
	vec3 to_cam = cam - pos;
	vec3 side = cross(dir, to_cam);
	float l = length(side);
	if (l < 1e-8) {
		side = vec3(0.0, 1.0, 0.0);
	} else {
		side /= l;
	}
	pos += side * (UV.y - 0.5) * width;
	VERTEX = (VIEW_MATRIX * vec4(pos, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	v_uv = vec2(UV.x * uv_scale.x + uv_offset.x, UV.y * uv_scale.y + uv_offset.y);
}

void fragment() {
	vec4 t = texture(tex, v_uv);
	t.rgb = IN_LINEAR(t.rgb);
	vec4 vc = vec4(IN_LINEAR(vcolor.rgb), vcolor.a);
	vec4 c = 2.0 * vc * tint * t;
	c = clamp(c, vec4(0.0), vec4(1.0));
#ifdef LINE_ADDITIVE
	ALBEDO = OUT_COLOR(c.rgb * c.a);
#else
	ALBEDO = OUT_COLOR(c.rgb);
	ALPHA = c.a;
#endif
}
