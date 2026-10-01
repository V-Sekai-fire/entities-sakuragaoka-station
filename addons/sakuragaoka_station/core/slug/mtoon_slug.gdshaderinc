// godot-vrm's MToon (addons/Godot-MToon-Shader/mtoon_common.gdshaderinc, included unchanged) with
// its lit texture drawn by Slug. Included BEFORE mtoon_common.gdshaderinc: MToon samples every map
// as texture(<sampler>, uv), so texture() is redefined to paste the sampler's name onto _slug and
// each sampler gets its own expansion below:
//   _MainTex       the texture key's layers at the mesh's own UV (through repeat/offset, fract()
//                  for repeating textures), straight alpha, times the alpha map's green when one is
//                  bound, times the vertex tint (COLOR, sRGB-encoded material x vertex colour)
//   _ShadeTexture  the same colour (MToon's mainTex local, so Slug runs once per fragment); MToon
//                  still multiplies it by _ShadeColor
//   _EmissionMap   the same colour when slug_emission (an unlit "basic" material), else the map
//   the rest       MToon's own optional maps at mip 0 (the station sets none, so they read their
//                  1x1 defaults exactly as texture() would)
// Shading, shade colour, rim, matcap, emission, cutout/blend and the outline path are MToon's.
// Stamp layers (slug.gdshaderinc) draw in the map and the alpha map alike: bind core/slug/stamps.gd's
// textures beside the atlas's (Stamps.bind(sm); slug_stamp_fade sets the VR distance fade).

#include "./slug.gdshaderinc"

uniform ivec2 slug_alpha_key = ivec2(0, 0);   // .y == 0: no alpha map
uniform vec4 slug_alpha_frame = vec4(1.0, -1.0, 0.0, 1.0);
uniform vec4 slug_alpha_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform bool slug_alpha_wrap = false;
uniform bool slug_has_map = true;              // false: only the alpha map is drawn
uniform bool slug_emission = false;

vec3 slug_srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec4 slug_main(vec2 uv, vec4 tint) {
	vec4 c = slug_has_map ? slug_unpremultiply(slug_texture(slug_key, slug_frame, slug_uv, slug_wrap, uv)) : vec4(1.0);
	if (slug_alpha_key.y > 0) {
		c.a *= slug_texture(slug_alpha_key, slug_alpha_frame, slug_alpha_uv, slug_alpha_wrap, uv).g;
	}
	return c * vec4(slug_srgb_to_linear(tint.rgb), tint.a);
}

#define texture(S, UV) S##_slug(UV)
#define _MainTex_slug(UV) slug_main(UV, COLOR)
#define _ShadeTexture_slug(UV) vec4(mainTex.rgb, 1.0)
#define _EmissionMap_slug(UV) (slug_emission ? mainTex : textureLod(_EmissionMap, UV, 0.0))
#define _UvAnimMaskTexture_slug(UV) textureLod(_UvAnimMaskTexture, UV, 0.0)
#define _BumpMap_slug(UV) textureLod(_BumpMap, UV, 0.0)
#define _SphereAdd_slug(UV) textureLod(_SphereAdd, UV, 0.0)
#define _RimTexture_slug(UV) textureLod(_RimTexture, UV, 0.0)
#define _ShadingGradeTexture_slug(UV) textureLod(_ShadingGradeTexture, UV, 0.0)
#define _ReceiveShadowTexture_slug(UV) textureLod(_ReceiveShadowTexture, UV, 0.0)
