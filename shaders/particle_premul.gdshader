shader_type spatial;
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
#define PARTICLE_PREMUL
#define PARTICLE_BILLBOARD
#include "res://shaders/particle_common.gdshaderinc"
