// Full screen fade (SteamVR_LoadLevel / SteamVR_Fade). Works for mono and stereo views.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 0.0);

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
