// src/core/materials.js's toon material (three.js r170's MeshToonMaterial with the original's gradient
// map and hand-paint patch, lit by core/sky.js's sun and hemisphere light) as a hook on godot-vrm's
// MToon (addons/Godot-MToon-Shader/mtoon_common.gdshaderinc, included unchanged). Included BEFORE
// mtoon_common.gdshaderinc: by the palette variants (./mtoon_ramp*.gdshader) and, after
// core/slug/mtoon_slug.gdshaderinc, by the Slug ones (core/slug/mtoon_slug*.gdshader).
//
// Godot gives built-ins (VERTEX, ALBEDO, LIGHT, ...) only to the functions named vertex, fragment and
// light (servers/rendering/shader_language.cpp), so MToon's stage functions cannot be renamed and
// wrapped, nor its light() renamed out of the way: a renamed copy no longer compiles. Instead, as
// mtoon_slug.gdshaderinc redefines texture(), three tokens MToon uses exactly once, each in one stage,
// are redefined to paste this file's code into that stage:
//   BINORMAL       vertex, `vec3 worldBitangent = mat3(MODELVIEW_MATRIX)*BINORMAL;`: the world position
//                  and world normal varyings (MToon's bitangent, which only a normal map reads, is 0)
//   METALLIC       fragment, `METALLIC = 0.0;`, after MToon writes ALBEDO and EMISSION: the painted
//                  albedo, the emissive plus the hemisphere light, the shading normal for light(); and
//                  MToon's lit, shade and rim varyings zeroed, so MToon's own light() code adds 0
//   isDirectional  light, `bool isDirectional = true;`, its first statement: the gradient-mapped light
// Per light, three's RE_Direct_Toon (irradiance = G(N.L) * light colour * shadow, times BRDF_Lambert):
//   DIFFUSE_LIGHT += G(N.L) * ATTENUATION * LIGHT_COLOR / PI      (Godot multiplies it by ALBEDO)
// LIGHT_COLOR is the light's linear colour times energy times pi, so the station's sun (#fff0dc,
// energy 2.75 / pi) gives three's 2.75 * #fff0dc / pi. ATTENUATION is the directional shadow (Godot's
// PCF, 8-bit) times nothing else; for an omni or spot light it carries distance and cone falloff too,
// as three's directLight.color does. The shadow scales the stepped value; it never enters the dot.
// Ambient: Godot's own is off (ambient_light_disabled: no environment ambient, sky reflection or GI),
// and RE_IndirectDiffuse_Toon's hemisphere light goes in through EMISSION:
//   EMISSION = emissive + albedo * mix(ground, sky, 0.5 * N.y + 0.5) * 1.62 / PI
// No MToon rim, matcap, shade colour, light-from-up ratio or outline. MToon's NORMAL output (its bent
// indirect normal) is left as MToon writes it: only the normal buffer reads it now, for core/composite.gd.
// Controls for the calibration (tools/toon_ramp_check.gd), defined before this include:
//   RAMP_CONTROL_STEP     MToon's step in place of G: the port's _ShadeShift/_ShadeToony ramp of the
//                         shadowed N.L, mixing from _ShadeColor to 1, as MToon's calculateLighting does
//   RAMP_CONTROL_NO_HEMI  no hemisphere light
//   RAMP_CONTROL_NO_PAINT no hand-paint noise
render_mode ambient_light_disabled;

/// materials.js toon()'s `paint` (patchPaint's uPaint), 0.05 unless the material says otherwise. Its
/// `grime` reaches the original's shader as uGrime, which no line reads, so it has no counterpart here.
uniform float ramp_paint = 0.05;
/// three.js flips a double-sided material's normal on back faces (normal_fragment_begin); the sakura
/// cards and flora replace that chunk (sakura/materials.js NOFLIP) and keep the front normal.
uniform bool ramp_flip = true;

varying vec3 ramp_world;   // vertex to fragment: the world position, materials.js's vPWorld
varying vec3 ramp_normal;  // vertex to fragment: the world normal, normalized per vertex as vNormal is
varying vec3 ramp_n;       // fragment to light: the shading normal in view space

// materials.js NOISE_GLSL
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

/// patchPaint's addition after map_fragment, on the diffuse colour at world position p.
vec3 ramp_painted(vec3 c, vec3 p, float paint) {
	float pn = paintNoise(p);
	c *= 1.0 + paint * pn;
	return mix(c, c * vec3(0.93, 0.93, 0.97), paint * 2.0 * clamp(pn * 1.5, 0.0, 1.0));
}

/// makeGradientMap(): 16 texels, texel i holding the step's value at dotNL = (i + 0.5) / 16 * 2 - 1 as
/// 8-bit red (0; 0.42 -> 107/255; 0.8 -> 204/255; 1), read by getGradientIrradiance with NEAREST
/// filtering and clamp-to-edge at u = dotNL * 0.5 + 0.5. The texel grid moves the generator's breaks at
/// 0.12 and 0.42 to 0.125 and 0.375.
float ramp_gradient(float dot_nl) {
	float i = clamp(floor((dot_nl * 0.5 + 0.5) * 16.0), 0.0, 15.0);
	return i < 8.0 ? 0.0 : (i < 9.0 ? 107.0 / 255.0 : (i < 11.0 ? 204.0 / 255.0 : 1.0));
}

/// sky.js's HemisphereLight('#a9b3ee', '#d9c6c8', 1.62) from its default up direction
/// (getHemisphereLightIrradiance), linear, times BRDF_Lambert's 1 / pi.
const vec3 RAMP_SKY = vec3(0.396755231, 0.450785783, 0.854992608);
const vec3 RAMP_GROUND = vec3(0.693871761, 0.564711506, 0.577580440);

vec3 ramp_hemisphere(float up) {
	return mix(RAMP_GROUND, RAMP_SKY, 0.5 * up + 0.5) * (1.62 / PI);
}

// vertex: VERTEX is in view space here (MToon's skip_vertex_transform), MODEL_MATRIX includes a
// MultiMesh instance's transform; the normal goes through the inverse transpose as three's
// normalMatrix (and its instanceMatrix scaling) does.
#define BINORMAL vec3(0.0); RAMP_VERTEX vec3 ramp_unused_bitangent = vec3(0.0)
#define RAMP_VERTEX ramp_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz; ramp_normal = normalize(transpose(inverse(mat3(MODEL_MATRIX))) * NORMAL);

// fragment: lit is MToon's mainTex * _Color (the palette colour, or Slug's texture times its tint);
// _EmissionMap goes through mtoon_slug.gdshaderinc's texture() where that is included.
#define METALLIC RAMP_FRAGMENT float ramp_unused_metallic
#define RAMP_FRAGMENT { vec3 ramp_nw = normalize(ramp_normal) * (ramp_flip && !FRONT_FACING ? -1.0 : 1.0); vec3 ramp_albedo = RAMP_ALBEDO; ALBEDO = ramp_albedo; EMISSION = texture(_EmissionMap, mainUv).rgb * _EmissionColor.rgb * _EmissionMultiplier RAMP_HEMI; ramp_n = mat3(VIEW_MATRIX) * ramp_nw; lit = vec4(0.0); shade = vec4(0.0); rim = vec3(0.0); }
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

// light
#define isDirectional ramp_unused_directional = true; RAMP_LIGHT bool ramp_unused_directional2
#ifdef RAMP_CONTROL_STEP
#define RAMP_LIGHT DIFFUSE_LIGHT += mix(_ShadeColor.rgb, vec3(1.0), clamp(((dot(ramp_n, LIGHT) * 0.5 + 0.5) * ATTENUATION * 2.0 - 1.0 - _ShadeShift) / max(EPS_COL, mix(1.0, _ShadeShift, _ShadeToony) - _ShadeShift), 0.0, 1.0)) * LIGHT_COLOR / PI;
#else
#define RAMP_LIGHT DIFFUSE_LIGHT += ramp_gradient(dot(ramp_n, LIGHT)) * ATTENUATION * LIGHT_COLOR / PI;
#endif
