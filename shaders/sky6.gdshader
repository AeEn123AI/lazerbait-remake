// Unity "Skybox/6 Sided" equivalent. Face orientation was verified by matching the
// seams of the original BluePinkNebular textures (front=+Z, left=+X, back=-Z, right=-X in Unity space).
// Unity's _Tint 0.5 with the shader's x2 and _Exposure 1 => textures are shown as-is.
shader_type sky;

uniform sampler2D front_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D back_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D left_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D right_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D up_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D down_tex : source_color, filter_linear, repeat_disable;
uniform float exposure = 1.0;

vec3 sample_face(vec3 d) {
	// Godot -> Unity coordinates (mirror Z)
	vec3 u = vec3(d.x, d.y, -d.z);
	vec3 a = abs(u);
	vec2 st;
	vec3 c;
	if (a.z >= a.x && a.z >= a.y) {
		if (u.z > 0.0) {
			st = vec2(0.5 + 0.5 * u.x / a.z, 0.5 - 0.5 * u.y / a.z);
			c = textureLod(front_tex, st, 0.0).rgb;
		} else {
			st = vec2(0.5 - 0.5 * u.x / a.z, 0.5 - 0.5 * u.y / a.z);
			c = textureLod(back_tex, st, 0.0).rgb;
		}
	} else if (a.x >= a.y) {
		if (u.x > 0.0) {
			st = vec2(0.5 - 0.5 * u.z / a.x, 0.5 - 0.5 * u.y / a.x);
			c = textureLod(left_tex, st, 0.0).rgb;
		} else {
			st = vec2(0.5 + 0.5 * u.z / a.x, 0.5 - 0.5 * u.y / a.x);
			c = textureLod(right_tex, st, 0.0).rgb;
		}
	} else {
		if (u.y > 0.0) {
			st = vec2(0.5 + 0.5 * u.x / a.y, 0.5 + 0.5 * u.z / a.y);
			c = textureLod(up_tex, st, 0.0).rgb;
		} else {
			st = vec2(0.5 + 0.5 * u.x / a.y, 0.5 - 0.5 * u.z / a.y);
			c = textureLod(down_tex, st, 0.0).rgb;
		}
	}
	return c;
}

void sky() {
	COLOR = sample_face(EYEDIR) * exposure;
}
