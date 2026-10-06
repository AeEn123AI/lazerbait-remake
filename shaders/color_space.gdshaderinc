// The Compatibility renderer shades in sRGB space while Forward+/Mobile shade in linear space.
// Custom shaders do their maths in linear space (like the original, which used Unity's linear
// colour space) and convert at the edges so every renderer shows the same colours.
vec3 cs_to_linear(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
vec3 cs_to_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
#define IN_LINEAR(c) cs_to_linear(c)
#define OUT_COLOR(c) cs_to_srgb(c)
#else
#define IN_LINEAR(c) (c)
#define OUT_COLOR(c) (c)
#endif
