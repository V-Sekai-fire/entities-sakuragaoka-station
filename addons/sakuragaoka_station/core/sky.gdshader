// src/core/sky.js's dome: horizon to mid to zenith by elevation, a warm glow toward a low sun, the sun's
// glow and disc, wind-stretched cirrus with low cumulus, and the fog colour below the horizon.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.31, 0.561, 0.839);
uniform vec3 mid : source_color = vec3(0.561, 0.741, 0.914);
uniform vec3 horizon : source_color = vec3(0.875, 0.914, 0.949);
uniform vec3 warm : source_color = vec3(0.984, 0.89, 0.812);
uniform vec3 fog_colour : source_color = vec3(0.812, 0.863, 0.925);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float wind_time = 0.0;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	for (int i = 0; i < 5; i++) {
		s += a * vn(p);
		p = m * p;
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon, mid, smoothstep(0.0, 0.22, h));
	col = mix(col, zenith, smoothstep(0.18, 0.95, h));
	float sd = max(dot(d, normalize(sun_dir)), 0.0);
	col = mix(col, warm, pow(sd, 3.0) * (1.0 - smoothstep(0.0, 0.5, h)) * 0.55);
	col += vec3(1.0, 0.93, 0.82) * (pow(sd, 18.0) * 0.22 + pow(sd, 300.0) * 0.9);
	col += vec3(1.0) * smoothstep(0.9993, 0.9997, sd) * 2.2;
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12);
		vec2 w = normalize(vec2(0.93, 0.36));
		vec2 q = vec2(dot(uv, w), dot(uv, vec2(-w.y, w.x)));
		q.x += wind_time * 0.004;
		float streak = fbm(vec2(q.x * 0.55, q.y * 6.5) + 5.0);
		float detail = fbm(vec2(q.x * 1.8, q.y * 11.0) + 17.0);
		float cir = smoothstep(0.50, 0.70, streak * 0.8 + detail * 0.35);
		cir *= smoothstep(0.30, 0.58, fbm(q * 0.35 + 2.0));
		vec2 cq = vec2(q.x * 0.9, q.y * 2.2);
		float cu = fbm(cq * 0.9 + 31.0) * 0.7 + fbm(cq * 2.3 + 7.0) * 0.35;
		float cum = smoothstep(0.60, 0.66, cu) * (1.0 - smoothstep(0.06, 0.26, h));
		float cum_core = smoothstep(0.66, 0.76, cu);
		float shade = smoothstep(0.0, 0.06, fbm(cq * 2.3 + 7.0 + normalize(sun_dir.xz) * 0.08) * 0.35 - fbm(cq * 2.3 + 7.0) * 0.35 + 0.02);
		vec3 lit = mix(vec3(0.99, 0.985, 0.97), vec3(1.0, 0.93, 0.84), pow(sd, 5.0));
		vec3 under = vec3(0.83, 0.85, 0.94);
		float fade_h = smoothstep(0.01, 0.12, h);
		col = mix(col, mix(lit, vec3(0.93, 0.95, 1.0), 0.25), cir * 0.8 * fade_h);
		col = mix(col, mix(lit, under, shade * (1.0 - cum_core * 0.5)), cum * 0.9 * fade_h);
		col += vec3(1.0, 0.9, 0.76) * (cir * 0.35 + cum * 0.5) * pow(sd, 8.0) * 0.6 * fade_h;
	}
	COLOR = mix(col, fog_colour, 1.0 - smoothstep(-0.12, 0.02, h));
}
