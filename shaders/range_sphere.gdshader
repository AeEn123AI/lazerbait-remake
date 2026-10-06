// The "backface" shader on the planet range sphere: a faint translucent shell.
shader_type spatial;
render_mode blend_mix, unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.307, 1.0, 0.25, 0.196);

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
