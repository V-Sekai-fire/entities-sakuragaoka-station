// three.js MeshToonMaterial with materials.js's ramp on linear vertex colour: N.L below 0 is
// dark, to 0.12 is 0.42, to 0.42 is 0.8, above is full; ambient light fills the dark band.
// realize.gd specializes the marked lines per material (cull side, alpha, unshaded, decal).
shader_type spatial;
render_mode cull_back, specular_disabled;

uniform vec4 albedo = vec4(1.0);
uniform vec3 emission = vec3(0.0);
uniform float alpha_scissor = 0.0;

void vertex() {
	// DECAL
}

void fragment() {
	vec4 c = albedo * COLOR;
	if (alpha_scissor > 0.0 && c.a < alpha_scissor) {
		discard;
	}
	ALBEDO = c.rgb;
	EMISSION = emission;
	// ALPHA
}

void light() {
	float d = dot(NORMAL, LIGHT);
	float v = d < 0.0 ? 0.0 : (d < 0.12 ? 0.42 : (d < 0.42 ? 0.8 : 1.0));
	DIFFUSE_LIGHT += v * ATTENUATION * LIGHT_COLOR / PI;
}
