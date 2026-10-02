// The lab's procedural albedo: hue by 0.5 m cell in world space, a lighter band every 2/3 m in y.
vec3 albedo_at(vec3 p) {
	vec3 cell = floor(p * 2.0);
	vec3 hue = 0.5 + 0.45 * cos(6.2831853 * (vec3(0.0, 0.33, 0.67) + dot(cell, vec3(0.13, 0.07, 0.29))));
	return mix(hue, vec3(0.92), 0.35 * step(0.5, fract(p.y * 1.5)));
}
