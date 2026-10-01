// src/core/sky.js's dome: horizon to mid to zenith by elevation, a warm glow toward a low sun, and
// the fog colour below the horizon so it meets the distant terrain. The clouds are not ported.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.31, 0.561, 0.839);
uniform vec3 mid : source_color = vec3(0.561, 0.741, 0.914);
uniform vec3 horizon : source_color = vec3(0.875, 0.914, 0.949);
uniform vec3 warm : source_color = vec3(0.984, 0.89, 0.812);
uniform vec3 fog_colour : source_color = vec3(0.812, 0.863, 0.925);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon, mid, smoothstep(0.0, 0.22, h));
	col = mix(col, zenith, smoothstep(0.18, 0.95, h));
	float sd = max(dot(d, normalize(sun_dir)), 0.0);
	col = mix(col, warm, pow(sd, 3.0) * (1.0 - smoothstep(0.0, 0.5, h)) * 0.55);
	COLOR = mix(col, fog_colour, 1.0 - smoothstep(-0.12, 0.02, h));
}
