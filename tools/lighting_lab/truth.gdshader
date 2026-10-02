// The original's toon lighting as a parameterised truth: three.js MeshToonMaterial's stepped sun
// term (levels at dotNL thresholds, shadow scaling the step) plus HemisphereLight's ambient, over
// a procedural world-space albedo, so a planted parameter change is a defect with a known fix.
shader_type spatial;
render_mode specular_disabled, ambient_light_disabled, fog_disabled;

uniform vec3 sky : source_color = vec3(0.663, 0.702, 0.933);
uniform vec3 ground : source_color = vec3(0.851, 0.776, 0.784);
uniform float hemi_energy = 1.62;
uniform vec3 thresholds = vec3(0.0, 0.12, 0.42);
uniform vec4 levels = vec4(0.0, 0.42, 0.8, 1.0);
uniform float sun_gain = 1.0;

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

#include "res://tools/lighting_lab/albedo.gdshaderinc"

void fragment() {
	ALBEDO = albedo_at(w_pos);
	EMISSION = ALBEDO * mix(ground, sky, 0.5 * normalize(w_nrm).y + 0.5) * hemi_energy / PI;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float g = ndl < thresholds.x ? levels.x : (ndl < thresholds.y ? levels.y : (ndl < thresholds.z ? levels.z : levels.w));
	DIFFUSE_LIGHT += LIGHT_COLOR * g * ATTENUATION * sun_gain / PI;
}
