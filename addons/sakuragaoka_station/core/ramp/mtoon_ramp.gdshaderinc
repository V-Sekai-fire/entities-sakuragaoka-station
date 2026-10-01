// src/core/materials.js's toon material on MToon (included unchanged, after this file): three tokens
// MToon uses once each paste this code into its vertex, fragment and light stages.
render_mode ambient_light_disabled;

uniform float ramp_paint = 0.05;  // toon()'s paint; the original never reads its grime
uniform bool ramp_flip = true;    // three's back-face normal flip, off for the sakura NOFLIP materials

varying vec3 ramp_world;   // world position, vPWorld
varying vec3 ramp_normal;  // world normal, normalized per vertex as vNormal is
varying vec3 ramp_n;       // fragment to light: the shading normal in view space

float pn_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float pn_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(pn_hash(i + vec3(0.0, 0.0, 0.0)), pn_hash(i + vec3(1.0, 0.0, 0.0)), f.x), mix(pn_hash(i + vec3(0.0, 1.0, 0.0)), pn_hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
			mix(mix(pn_hash(i + vec3(0.0, 0.0, 1.0)), pn_hash(i + vec3(1.0, 0.0, 1.0)), f.x), mix(pn_hash(i + vec3(0.0, 1.0, 1.0)), pn_hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float paintNoise(vec3 p) {
	return (pn_noise(p * 0.45) * 0.6 + pn_noise(p * 1.9 + 11.0) * 0.4) * 2.0 - 1.0;
}

vec3 ramp_painted(vec3 c, vec3 p, float paint) {
	float pn = paintNoise(p);
	c *= 1.0 + paint * pn;
	return mix(c, c * vec3(0.93, 0.93, 0.97), paint * 2.0 * clamp(pn * 1.5, 0.0, 1.0));
}

// makeGradientMap()'s 16 8-bit texels read NEAREST: the breaks land at N.L 0, 0.125 and 0.375
float ramp_gradient(float dot_nl) {
	float i = clamp(floor((dot_nl * 0.5 + 0.5) * 16.0), 0.0, 15.0);
	return i < 8.0 ? 0.0 : (i < 9.0 ? 107.0 / 255.0 : (i < 11.0 ? 204.0 / 255.0 : 1.0));
}

const vec3 RAMP_SKY = vec3(0.396755231, 0.450785783, 0.854992608);     // sky.js hemisphere #a9b3ee, linear
const vec3 RAMP_GROUND = vec3(0.693871761, 0.564711506, 0.577580440);  // and #d9c6c8, at 1.62

vec3 ramp_hemisphere(float up) {
	return mix(RAMP_GROUND, RAMP_SKY, 0.5 * up + 0.5) * (1.62 / PI);
}

#define BINORMAL vec3(0.0); RAMP_VERTEX vec3 ramp_unused_bitangent = vec3(0.0)
#define RAMP_VERTEX ramp_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz; ramp_normal = normalize(transpose(inverse(mat3(MODEL_MATRIX))) * NORMAL); RAMP_VERTEX_EXTRA

#define METALLIC RAMP_FRAGMENT float ramp_unused_metallic
#define RAMP_GEOMETRIC_NORMAL NORMAL = mat3(VIEW_MATRIX) * normalize(ramp_normal) * (FRONT_FACING ? 1.0 : -1.0);
#ifdef RAMP_SAKURA
#define RAMP_FRAGMENT RAMP_SAKURA_FRAGMENT
#else
#define RAMP_VERTEX_EXTRA
#define RAMP_FRAGMENT { vec3 ramp_nw = normalize(ramp_normal) * (ramp_flip && !FRONT_FACING ? -1.0 : 1.0); vec3 ramp_albedo = RAMP_ALBEDO; ALBEDO = ramp_albedo; EMISSION = texture(_EmissionMap, mainUv).rgb * _EmissionColor.rgb * _EmissionMultiplier RAMP_HEMI; ramp_n = mat3(VIEW_MATRIX) * ramp_nw; lit = vec4(0.0); shade = vec4(0.0); rim = vec3(0.0); RAMP_GEOMETRIC_NORMAL }
#endif
#ifdef RAMP_CONTROL_NO_PAINT
#define RAMP_ALBEDO lit.rgb
#else
#define RAMP_ALBEDO ramp_painted(lit.rgb, ramp_world, ramp_paint)
#endif
#ifdef RAMP_CONTROL_NO_HEMI
#define RAMP_HEMI
#else
#define RAMP_HEMI + ramp_albedo * ramp_hemisphere(ramp_nw.y)
#endif

#define isDirectional ramp_unused_directional = true; RAMP_LIGHT bool ramp_unused_directional2
#ifdef RAMP_CONTROL_STEP
#define RAMP_LIGHT DIFFUSE_LIGHT += mix(_ShadeColor.rgb, vec3(1.0), clamp(((dot(ramp_n, LIGHT) * 0.5 + 0.5) * ATTENUATION * 2.0 - 1.0 - _ShadeShift) / max(EPS_COL, mix(1.0, _ShadeShift, _ShadeToony) - _ShadeShift), 0.0, 1.0)) * LIGHT_COLOR / PI;
#else
#define RAMP_LIGHT DIFFUSE_LIGHT += ramp_gradient(dot(ramp_n, LIGHT)) * ATTENUATION * LIGHT_COLOR / PI;
#endif
