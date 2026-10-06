// Approximation of the original "sun" surface shader used by the red_star material:
// an 8x8 animated atlas (AnimateTiledTexture) with saturation / contrast / brightness controls.
shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled;
#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 tile_scale = vec2(0.125, 0.125);
uniform vec2 tile_offset = vec2(0.0, 0.875);   // Unity UV space (origin bottom-left)
uniform float saturation = 0.554;
uniform float contrast = 1.64;
uniform float brightness = 0.512;
uniform vec4 tint : source_color = vec4(1.0, 0.959, 0.404, 0.502);

void fragment() {
	vec2 uu = vec2(UV.x, 1.0 - UV.y) * tile_scale + tile_offset;
	uu = vec2(uu.x, 1.0 - uu.y);
	vec3 c = texture(tex, uu).rgb;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	c = cs_to_srgb(c);
#endif
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c *= brightness * 2.0;
	c *= mix(vec3(1.0), tint.rgb * 2.0, tint.a);
	c = clamp(c, vec3(0.0), vec3(1.0));
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	c = cs_to_linear(c);
#endif
	ALBEDO = c;
}
