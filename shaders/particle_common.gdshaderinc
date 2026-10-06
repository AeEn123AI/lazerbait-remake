// Unity legacy particle shaders on Godot GPU particles.
// PARTICLE_ADD       : "Particles/Additive"         col = 2*color*_TintColor*tex, out = rgb*a (add)
// PARTICLE_ADDSMOOTH : "Particles/Additive (Soft)"  col = color*tex, out = rgb*a (add)
// PARTICLE_PREMUL    : "Particles/Alpha Blended Premultiply" col = color*tex*color.a (premultiplied)
// PARTICLE_BILLBOARD : camera facing quads; PARTICLE_FLIPBOOK : texture sheet animation
#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint = vec4(0.5, 0.5, 0.5, 0.5); // linear-space _TintColor (already gamma->linear converted)
uniform int h_frames = 1;
uniform int v_frames = 1;
uniform bool use_texture = true;

void vertex() {
#ifdef PARTICLE_BILLBOARD
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mat_world = mat_world * mat4(vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0), vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
#endif
#ifdef PARTICLE_FLIPBOOK
	float hf = float(h_frames);
	float vf = float(v_frames);
	float total = hf * vf;
	float frame = floor(INSTANCE_CUSTOM.z * total);
	frame = mod(frame, total);
	UV /= vec2(hf, vf);
	UV += vec2(mod(frame, hf) / hf, floor((frame + 0.5) / hf) / vf);
#endif
}

void fragment() {
	vec4 vc = vec4(cs_to_linear(COLOR.rgb), COLOR.a); // particle colours are sRGB
	vec4 t = use_texture ? texture(tex, UV) : vec4(1.0);
	t.rgb = IN_LINEAR(t.rgb);
#ifdef PARTICLE_ADD
	vec4 c = clamp(2.0 * vc * tint * t, vec4(0.0), vec4(1.0));
	ALBEDO = OUT_COLOR(c.rgb * c.a);
#endif
#ifdef PARTICLE_ADDSMOOTH
	vec4 c = clamp(vc * t, vec4(0.0), vec4(1.0));
	ALBEDO = OUT_COLOR(c.rgb * c.a);
#endif
#ifdef PARTICLE_PREMUL
	vec4 c = vc * t * vc.a;
	ALBEDO = OUT_COLOR(c.rgb);
	ALPHA = clamp(c.a, 0.0, 1.0);
#endif
}
