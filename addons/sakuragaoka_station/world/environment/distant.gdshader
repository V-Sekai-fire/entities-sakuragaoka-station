// environment/shaders.js's distantMaterial: painted forest hills with a 3-step cel light and lavender
// shadow, forest-type patches, jittered crowns lit from the sun that fade with their screen footprint,
// distance haze, valley mist and the scene fog at a fraction of the depth. It fogs itself, so it writes
// roughness 0 and core/fog.gd skips it. Ridge rings take crowns in (arc, height) from their angle.
shader_type spatial;
render_mode unshaded, fog_disabled;

uniform sampler2D palette : source_color, filter_nearest;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float lit_k = 1.0;
uniform float mid_k = 0.87;
uniform float shade_k = 0.74;
uniform vec3 shade_tint : source_color = vec3(0.706, 0.722, 0.886);
uniform vec3 haze : source_color = vec3(0.788, 0.843, 0.918);
uniform float haze_min = 0.0;
uniform float haze_max = 0.92;
uniform float haze_k = 0.0012;
uniform vec3 mist : source_color = vec3(0.886, 0.918, 0.953);
uniform float mist_y0 = 0.0;
uniform float mist_y1 = 30.0;
uniform float mist_amt = 0.5;
uniform vec3 pink : source_color = vec3(0.937, 0.765, 0.824);
uniform float pink_amt = 0.0;
uniform vec3 young : source_color = vec3(0.706, 0.812, 0.525);
uniform float young_amt = 0.0;
uniform vec3 dark : source_color = vec3(0.365, 0.482, 0.4);
uniform float dark_amt = 0.0;
uniform float crown = 9.0;
uniform float crown_amt = 0.0;
uniform float patch_scale = 0.0142857;
uniform bool arc = false;
uniform float wrap = 1e6;
uniform float fog_mul = 0.35;
uniform float rim = 0.0;
uniform vec3 fog_colour : source_color = vec3(0.812, 0.863, 0.925);
uniform float fog_density = 0.0026;

varying vec3 w_pos;
varying vec3 w_nrm;
varying vec3 tint;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
	tint = COLOR.rgb;
}

float d_h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 d_h22(vec2 p) {
	float a = d_h21(p);
	return vec2(a, d_h21(p + a * 17.17 + 3.1));
}

float d_vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(d_h21(i), d_h21(i + vec2(1.0, 0.0)), f.x), mix(d_h21(i + vec2(0.0, 1.0)), d_h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec4 d_crowns(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = -9.0;
	vec4 res = vec4(0.0, 0.0, 0.0, 0.5);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 ci = i + g;
			if (arc) {
				ci.x = mod(ci.x, wrap);
			}
			vec2 h = d_h22(ci);
			vec2 c = g + 0.18 + 0.64 * h;
			float rad = 0.6 + 0.26 * fract(h.x * 7.13 + h.y);
			vec2 o = (f - c) / rad;
			float r2 = dot(o, o);
			if (r2 < 1.0) {
				float hd = sqrt(1.0 - r2);
				float front = arc ? -c.y : c.y;
				float score = front * 0.55 + h.x * 0.5 + hd * 0.25;
				if (score > best) {
					best = score;
					res = vec4(o, hd, fract(h.x * 0.61 + h.y * 0.39 + 0.13));
				}
			}
		}
	}
	return res;
}

void fragment() {
	vec3 n = normalize(w_nrm);
	vec3 s = normalize(sun_dir);
	vec3 base = texture(palette, UV).rgb * tint;
	vec2 pp = w_pos.xz * patch_scale;
	float pa = d_vn(pp) * 0.7 + d_vn(pp * 2.7 + 5.3) * 0.3;
	float pb = d_vn(pp * 1.6 + 11.7) * 0.65 + d_vn(pp * 4.1 + 2.2) * 0.35;
	base = mix(base, dark, smoothstep(0.56, 0.7, pa) * dark_amt);
	base = mix(base, young, smoothstep(0.58, 0.74, pb) * young_amt);
	vec3 t = vec3(1.0, 0.0, 0.0);
	vec3 b = vec3(0.0, 0.0, 1.0);
	vec2 q = w_pos.xz / crown;
	float fw = length(fwidth(q));
	if (arc) {
		float th = atan(w_pos.x, -w_pos.z);
		float th0 = th < 0.0 ? th + 2.0 * PI : th;
		q = vec2(th0 / (2.0 * PI) * wrap, w_pos.y / crown);
		fw = min(length(fwidth(q)), length(fwidth(vec2(th / (2.0 * PI) * wrap, q.y))));
		t = vec3(cos(th0), 0.0, sin(th0));
		b = normalize(vec3(0.0, 1.0, 0.0) - n * n.y);
	}
	float detail = crown_amt * (1.0 - smoothstep(0.22, 0.62, fw));
	float d_macro = dot(n, s);
	float d = d_macro;
	float gap = 0.0;
	float rim_d = 0.0;
	if (detail > 0.001) {
		vec4 c = d_crowns(q);
		float cover = step(0.0001, c.z);
		vec3 cn = normalize(n * (c.z * 1.05 + 0.2) + (t * c.x + b * c.y) * 0.95);
		d = mix(d_macro, mix(d_macro, dot(cn, s), 0.72), detail * cover);
		gap = (1.0 - cover) * detail;
		rim_d = (1.0 - smoothstep(0.0, 0.32, c.z)) * cover * detail;
		float idc = c.w;
		base *= 1.0 + (idc - 0.5) * 0.16 * detail * cover;
		float pz = d_vn(pp * 1.3 + 31.0);
		float is_pink = step(idc, pink_amt * smoothstep(0.6, 0.78, pz)) * cover;
		float pink_vis = detail * detail * (1.0 - smoothstep(320.0, 650.0, length(w_pos - CAMERA_POSITION_WORLD)));
		base = mix(base, pink, is_pink * pink_vis * 0.85);
	}
	vec3 light_k = d < 0.02 ? shade_tint * shade_k : (d < 0.3 ? vec3(mid_k) : vec3(lit_k));
	vec3 col = base * light_k;
	col = mix(col, base * shade_tint * shade_k * 0.92, gap * 0.85);
	col *= 1.0 - rim_d * 0.08;
	col += vec3(1.0, 0.93, 0.82) * rim * smoothstep(0.55, 0.85, d_macro) * 0.1;
	float dist = length(w_pos - CAMERA_POSITION_WORLD);
	col = mix(col, haze, clamp(haze_min + (1.0 - exp(-dist * haze_k)), 0.0, haze_max));
	col = mix(col, mist, (1.0 - smoothstep(mist_y0, mist_y1, w_pos.y)) * mist_amt);
	float fd = -VERTEX.z * fog_mul;
	col = mix(col, fog_colour, 1.0 - exp(-fog_density * fog_density * fd * fd));
	ALBEDO = col;
	ROUGHNESS = 0.0;
}
