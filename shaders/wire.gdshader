// "UCLA GameLab Double-Sided Wireframe" equivalent. The mesh carries barycentric
// coordinates in COLOR.rgb (see Wire.make_wire_mesh()).
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.106, 0.963, 0.219, 0.059);
uniform float thickness = 0.8;

void fragment() {
	vec3 b = COLOR.rgb;
	vec3 d = fwidth(b);
	vec3 a = smoothstep(vec3(0.0), d * (thickness + 0.5), b);
	float edge = 1.0 - min(min(a.x, a.y), a.z);
	ALBEDO = color.rgb;
	ALPHA = color.a * edge;
}
