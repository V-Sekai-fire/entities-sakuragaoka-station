// The lab's reference passes, one per mode: 0 the procedural albedo as the renders would carry it,
// 1 the sun's 0.5 dotNL + 0.5, its shadow and 0.5 normal y + 0.5, 2 that dotNL to 16 bits as high
// and low bytes, all pre-linearised so the viewport's sRGB encoding stores each as round(255 v).
shader_type spatial;
render_mode specular_disabled, ambient_light_disabled, fog_disabled;

#include "res://tools/lighting_lab/albedo.gdshaderinc"

uniform int mode = 0;

vec3 to_linear(vec3 v) {
	return mix(v / 12.92, pow((v + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), v));
}

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	ALBEDO = mode == 0 ? vec3(0.0) : vec3(1.0);
	EMISSION = mode == 0 ? albedo_at(w_pos) : (mode == 1 ? to_linear(vec3(0.0, 0.0, 0.5 * normalize(w_nrm).y + 0.5)) : vec3(0.0));
}

void light() {
	if (mode == 1) {
		DIFFUSE_LIGHT += to_linear(vec3(0.5 * dot(NORMAL, LIGHT) + 0.5, ATTENUATION, 0.0));
	} else if (mode == 2) {
		float q = floor((0.5 * dot(NORMAL, LIGHT) + 0.5) * 65535.0 + 0.5);
		float hi = floor(q / 256.0);
		DIFFUSE_LIGHT += to_linear(vec3(hi, q - 256.0 * hi, 0.0) / 255.0);
	}
}
