// sakura/materials.js's extend() on the toon ramp (after mtoon_ramp.gdshaderinc), each option a material
// parameter; lit in the fragment from the sun globals, as the sakura masses and cards receive no shadow.
#include "res://addons/sakuragaoka_station/core/slug/slug.gdshaderinc"

uniform ivec2 slug_speck_key = ivec2(0, 0);
uniform vec4 slug_speck_frame = vec4(1.0, -1.0, 0.0, 1.0);
uniform vec4 slug_speck_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform bool slug_speck_wrap = true;
uniform float ramp_speck_k = 0.0;
uniform float ramp_rim_k = 0.0;
uniform float ramp_sheen_k = 0.0;
uniform bool ramp_env_rim = false;
uniform float ramp_shade_k = 0.0;
uniform bool ramp_oct = false;
uniform bool ramp_band = false;
uniform bool ramp_sway = false;
uniform bool ramp_edge_fade = false;
uniform float ramp_edge_cutoff = 0.5;
uniform bool ramp_dapple = false;
global uniform vec3 ramp_sun_dir;    // toward the station's DirectionalLight3D (station.gd)
global uniform vec3 ramp_sun_color;  // its linear colour times energy times pi, Godot's LIGHT_COLOR
uniform float ramp_time = 0.0;
uniform vec2 ramp_wind = vec2(0.9, 0.35);
uniform float ramp_gust = 0.66998654;  // main.js's gust at the shots' t = 0

varying vec2 ramp_tone;     // colour.r tone, colour.g peach + 2 * palette
varying vec3 ramp_shading;  // world shading normal

const vec3 RAMP_BAND_N0 = vec3(0.783537792, 0.309468923, 0.445201195);
const vec3 RAMP_BAND_N1 = vec3(0.896269353, 0.502886458, 0.610495571);
const vec3 RAMP_BAND_N2 = vec3(0.947306537, 0.686685312, 0.760524505);
const vec3 RAMP_BAND_N3 = vec3(0.973445290, 0.814846572, 0.863157213);
const vec3 RAMP_BAND_W0 = vec3(0.715693501, 0.219526200, 0.356400144);
const vec3 RAMP_BAND_W1 = vec3(0.814846572, 0.337163615, 0.473531496);
const vec3 RAMP_BAND_W2 = vec3(0.887923118, 0.527115126, 0.630757136);
const vec3 RAMP_BAND_W3 = vec3(0.938685728, 0.723055129, 0.791297940);
const vec3 RAMP_PEACH = vec3(0.921581856, 0.571124829, 0.479320183);

vec3 ramp_sway_offset(vec3 wp) {
	float ph = dot(wp, vec3(0.37, 0.61, 0.23));
	float g = 0.35 + 0.65 * ramp_gust;
	float s1 = sin(ramp_time * 1.25 + ph);
	float s2 = sin(ramp_time * 3.1 + ph * 2.7);
	return vec3(ramp_wind.x * (0.034 * s1 + 0.012 * s2) * g, 0.012 * sin(ramp_time * 2.2 + ph * 1.9) * g,
			ramp_wind.y * 0.034 * s1 * g + 0.010 * s2 * g);
}

bool ramp_dapple_at(vec3 p) {
	return pn_noise(p * 3.1) * 0.62 + pn_noise(p * 7.3 + 5.1) * 0.38 > 0.66;
}

vec3 ramp_band_colour(vec2 t, vec3 p) {
#ifdef RAMP_CONTROL_SAKURA_NO_WOBBLE
	float tn = t.x;
#else
	float tn = t.x + (pn_noise(p * 2.3) - 0.5) * 0.09 + (pn_noise(p * 6.1 + 3.7) - 0.5) * 0.05;
#endif
	float bw = max(fwidth(tn) * 0.8, 0.012);
	float pal = step(1.5, t.y);
	float pch = t.y - 2.0 * pal;
	vec3 bc = mix(mix(RAMP_BAND_N0, RAMP_BAND_W0, pal), mix(RAMP_BAND_N1, RAMP_BAND_W1, pal), smoothstep(0.25 - bw, 0.25 + bw, tn));
	bc = mix(bc, mix(RAMP_BAND_N2, RAMP_BAND_W2, pal), smoothstep(0.5 - bw, 0.5 + bw, tn));
	bc = mix(bc, mix(RAMP_BAND_N3, RAMP_BAND_W3, pal), smoothstep(0.75 - bw, 0.75 + bw, tn));
	return mix(bc, RAMP_PEACH, pch);
}

vec3 ramp_speck_at(vec2 uv) {
	return slug_unpremultiply(slug_texture(slug_speck_key, slug_speck_frame, slug_speck_uv, slug_speck_wrap, uv)).rgb;
}

vec3 ramp_speck(vec3 p) {
#ifdef RAMP_CONTROL_SAKURA_NO_SPECK
	return vec3(1.0);
#else
	if (ramp_speck_k <= 0.0) {
		return vec3(1.0);
	}
	vec3 nt = abs(normalize(cross(dFdx(p), dFdy(p))));
	nt = nt * nt * nt * nt;
	nt /= nt.x + nt.y + nt.z;
	vec3 sp = ramp_speck_at(p.zy * 1.1) * nt.x + ramp_speck_at(p.xz * 1.1) * nt.y + ramp_speck_at(p.xy * 1.1) * nt.z;
	vec3 sp2 = ramp_speck_at(p.zy * 0.43 + 0.37) * nt.x + ramp_speck_at(p.xz * 0.43 + 0.37) * nt.y + ramp_speck_at(p.xy * 0.43 + 0.37) * nt.z;
	sp = sp * mix(vec3(1.0), sp2, 0.55) * 1.04;
	return mix(vec3(1.0), sp, ramp_speck_k);
#endif
}

vec3 ramp_sakura(vec3 dc, vec3 n, vec3 ne, vec3 v, vec3 emissive) {
	vec3 s = normalize(ramp_sun_dir);
	vec3 em = emissive;
#ifndef RAMP_CONTROL_SAKURA_NO_RIM
	if (ramp_rim_k > 0.0) {
		vec3 nr = ramp_env_rim ? ne : n;
		float back = clamp(dot(-v, s) * 1.15, 0.0, 1.0);
		back *= back;
		float ndv = clamp(abs(dot(nr, v)), 0.0, 1.0);
		float rimv = pow(1.0 - ndv, 2.2);
		float trans = clamp(0.45 - dot(n, s) * 0.55, 0.0, 1.0);
		float sheen = pow(1.0 - ndv, 4.0) * ramp_sheen_k;
		vec3 glow = vec3(1.0, 0.64, 0.75) * (0.62 * rimv + 0.26 * trans) * back + vec3(0.9, 0.85, 1.0) * sheen;
		em += glow * dc * ramp_rim_k;
		em += dc * vec3(0.13, 0.12, 0.17) * (0.75 + 0.25 * trans);
		em += dc * vec3(0.11, 0.055, 0.075) * clamp(-dot(n, s) + 0.2, 0.0, 1.0);
	}
#endif
	vec3 direct = ramp_gradient(dot(n, s)) * ramp_sun_color * (dc / PI);
	vec3 col = direct + ramp_hemisphere(n.y) * dc + em;
#ifndef RAMP_CONTROL_SAKURA_NO_SHADE
	if (ramp_shade_k > 0.0) {
		float full = dot(dc * ramp_sun_color, vec3(1.0)) / PI;
		float lt = clamp(dot(direct, vec3(1.0)) / max(full, 1e-4), 0.0, 1.0);
		col = mix(col, dot(col, vec3(0.3, 0.52, 0.18)) * vec3(0.97, 0.9, 1.1), (1.0 - lt) * ramp_shade_k);
	}
#endif
	return col;
}

#ifdef RAMP_CONTROL_SAKURA_NO_OCT
#define RAMP_OCT false
#else
#define RAMP_OCT ramp_oct
#endif
#ifdef RAMP_CONTROL_SAKURA_NO_DAPPLE
#define RAMP_DAPPLE false
#else
#define RAMP_DAPPLE ramp_dapple
#endif
#define RAMP_VERTEX_EXTRA if (ramp_sway) { vec3 ramp_ofs = mat3(MODEL_MATRIX) * ramp_sway_offset(ramp_world); ramp_world += ramp_ofs; VERTEX += mat3(VIEW_MATRIX) * ramp_ofs; } ramp_tone = CUSTOM0.xy; ramp_shading = normalize(transpose(inverse(mat3(MODEL_MATRIX))) * (RAMP_OCT ? normalize(vec3(UV2.x, CUSTOM0.z, UV2.y) + vec3(0.0, 1e-4, 0.0)) : NORMAL));
#define RAMP_SAKURA_FRAGMENT { RAMP_SAKURA_DISCARD RAMP_SAKURA_SHADE ALBEDO = vec3(0.0); ramp_n = vec3(0.0, 0.0, 1.0); lit = vec4(0.0); shade = vec4(0.0); rim = vec3(0.0); }
#define RAMP_SAKURA_DISCARD vec3 ramp_v = normalize(CAMERA_POSITION_WORLD - ramp_world); if (ramp_edge_fade) { alpha *= smoothstep(0.1, 0.38, abs(dot(normalize(cross(dFdx(ramp_world), dFdy(ramp_world))), ramp_v))); if (alpha < ramp_edge_cutoff) { discard; } } if (RAMP_DAPPLE && PROJECTION_MATRIX[3][3] != 0.0 && (FRONT_FACING == (PROJECTION_MATRIX[1][1] < 0.0) || ramp_dapple_at(ramp_world))) { discard; }
#define RAMP_SAKURA_SHADE float ramp_fs = ramp_flip && !FRONT_FACING ? -1.0 : 1.0; vec3 ramp_dc = ramp_painted(lit.rgb, ramp_world, ramp_paint) * (ramp_band ? ramp_band_colour(ramp_tone, ramp_world) : vec3(1.0)) * ramp_speck(ramp_world); EMISSION = ramp_sakura(ramp_dc, normalize(ramp_shading) * ramp_fs, normalize(ramp_normal), ramp_v, texture(_EmissionMap, mainUv).rgb * _EmissionColor.rgb * _EmissionMultiplier);
