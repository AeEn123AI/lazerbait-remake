shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
#define PARTICLE_ADDSMOOTH
#include "res://shaders/particle_common.gdshaderinc"
