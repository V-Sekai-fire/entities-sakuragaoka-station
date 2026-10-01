# realize.gd's side of mtoon_ramp_sakura.gdshaderinc: which materials take it, a blossom mass's arrays and
# the per-material params from user_data.sakura (world/sakura/materials.gd).
extends RefCounted

const FORMAT := Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT


static func band(m) -> bool:
	return m.user_data.has("sakura") and m.user_data["sakura"].get("band", false) and not m.transparent \
			and m.alpha_test == 0.0 and m.side == "front"


static func wants(m, cutout: bool = false) -> bool:
	var s: Dictionary = m.user_data.get("sakura", {})
	return m.type == "toon" and not m.transparent and (cutout or m.alpha_test == 0.0) and (s.get("band", false) or s.get("edgeFade", false)
			or s.get("sway", false) or s.get("octNormal", false) or s.has("speck") or float(s.get("rim", 0.0)) > 0.0
			or float(s.get("shade", 0.0)) > 0.0)


## sakura.js's blobDepth: the mass casts from its back faces (three's shadowSide for a front-side material).
static func dapple(o) -> bool:
	return bool(o.user_data.get("customDepthMaterial", {}).get("dapple", false))


static func band_ok(m, g, gd: Dictionary) -> bool:
	var ca = g.get_attribute("color")
	return m.type == "toon" and band(m) and ca != null and ca.item_size == 3 and gd.uv.size() == ca.count()


## A blossom mass as the original draws it: indexed, its colour attribute in CUSTOM0, uv in UV2, UV at white.
static func arrays(g, gd: Dictionary, idx: PackedInt32Array, white: Vector2) -> Array:
	var a: Array = gd.arrays.duplicate()
	var uv := PackedVector2Array()
	uv.resize(gd.uv.size())
	uv.fill(white)
	a[Mesh.ARRAY_TEX_UV] = uv
	a[Mesh.ARRAY_TEX_UV2] = gd.uv
	a[Mesh.ARRAY_CUSTOM0] = g.get_attribute("color").array
	a[Mesh.ARRAY_INDEX] = idx
	return a


static func params(sm: ShaderMaterial, m, slug) -> void:
	var s: Dictionary = m.user_data["sakura"]
	sm.set_shader_parameter("ramp_rim_k", float(s.get("rim", 0.0)))
	sm.set_shader_parameter("ramp_sheen_k", float(s.get("sheen", 0.0)))
	sm.set_shader_parameter("ramp_shade_k", float(s.get("shade", 0.0)))
	sm.set_shader_parameter("ramp_env_rim", bool(s.get("envRim", false)))
	sm.set_shader_parameter("ramp_oct", bool(s.get("octNormal", false)))
	sm.set_shader_parameter("ramp_band", bool(s.get("band", false)))
	sm.set_shader_parameter("ramp_sway", bool(s.get("sway", false)))
	sm.set_shader_parameter("ramp_edge_fade", bool(s.get("edgeFade", false)))
	sm.set_shader_parameter("ramp_edge_cutoff", m.alpha_test if m.alpha_test > 0.0 else 0.5)
	var t = s.get("speck")
	var key := str(t.user_data.get("key", "")) if t != null else ""
	var drawn: bool = key != "" and slug != null and slug.has(key)
	sm.set_shader_parameter("ramp_speck_k", float(s.get("speckK", 1.0)) if drawn else 0.0)
	if drawn:
		slug.bind(sm, slug.key_info(key, t.width, t.height), Vector2.ONE, Vector2.ZERO, true, "speck_")
