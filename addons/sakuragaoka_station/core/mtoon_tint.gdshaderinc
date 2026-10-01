// godot-vrm's MToon (mtoon_common.gdshaderinc, included unchanged after this) with the palette colour
// times the MultiMesh instance colour, which reaches the fragment as COLOR (linear).
uniform bool tint_emission = false;

#define texture(S, UV) S##_tint(UV)
#define _MainTex_tint(UV) (textureLod(_MainTex, UV, 0.0) * vec4(COLOR.rgb, 1.0))
#define _ShadeTexture_tint(UV) (textureLod(_ShadeTexture, UV, 0.0) * vec4(COLOR.rgb, 1.0))
#define _EmissionMap_tint(UV) (textureLod(_EmissionMap, UV, 0.0) * (tint_emission ? vec4(COLOR.rgb, 1.0) : vec4(1.0)))
#define _UvAnimMaskTexture_tint(UV) textureLod(_UvAnimMaskTexture, UV, 0.0)
#define _BumpMap_tint(UV) textureLod(_BumpMap, UV, 0.0)
#define _SphereAdd_tint(UV) textureLod(_SphereAdd, UV, 0.0)
#define _RimTexture_tint(UV) textureLod(_RimTexture, UV, 0.0)
#define _ShadingGradeTexture_tint(UV) textureLod(_ShadingGradeTexture, UV, 0.0)
#define _ReceiveShadowTexture_tint(UV) textureLod(_ReceiveShadowTexture, UV, 0.0)
