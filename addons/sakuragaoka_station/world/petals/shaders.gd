# petals/shaders.js as Godot: the airborne and floating petal ShaderMaterials. The GLSL is ported to
# fall.gdshaderinc (FALL_VERT / FALL_FRAG; fall.gdshader, and soft.gdshader with SOFT) and
# float.gdshaderinc (FLOAT_VERT / FLOAT_FRAG; float.gdshader, and rafts.gdshader with SHEET).
#
# The build describes each material as a T.Mat of type "shader" (shader_kind "petals-fall",
# "petals-soft", "petals-glint", "petals-rafts", "petals-floating") with its uniforms in
# user_data.petals: {"shader": <file stem>, "uniforms": {...}, "shared": ctx.shared, "live": {...}}.
# "shared" holds uTime / uWind / uGust / uSunDir (ctx.shared, advanced by station.gd each frame) and
# "live" holds uTr / uTr2 / uResY (written by the module's on_update). The instanced petals carry
# per-instance vec4 attributes aA, aB, aC (and aD for floating petals) in geometry.attributes,
# listed in geometry.user_data.instanced; the instance matrices are identity, as in the original.
#
# realize.gd turns an InstancedMesh whose material has user_data.petals into node(o) below (aA into
# INSTANCE_CUSTOM, aB into COLOR, aC / aD into the instance basis, where the shaders read them) and
# lists it in live_shaders; station.gd pushes the shared and live uniforms each frame (update(sm, m)).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")

const SHADERS := {
	"fall": "res://addons/sakuragaoka_station/world/petals/fall.gdshader",
	"soft": "res://addons/sakuragaoka_station/world/petals/soft.gdshader",
	"float": "res://addons/sakuragaoka_station/world/petals/float.gdshader",
	"rafts": "res://addons/sakuragaoka_station/world/petals/rafts.gdshader",
}


static func _mat(kind: String, shader: String, uniforms: Dictionary, shared: Dictionary, live: Dictionary) -> T.Mat:
	var m := T.Mat.new()
	m.type = "shader"
	m.shader_kind = kind
	m.key = kind
	m.name = kind
	m.side = "double"
	m.user_data["petals"] = {"shader": shader, "uniforms": uniforms, "shared": shared, "live": live}
	return m


## fallMaterial(o) of petals.js: o = {name, minPx, far, soft, opacity}.
static func fall_material(o: Dictionary, uniforms: Dictionary, shared: Dictionary, live: Dictionary) -> T.Mat:
	var u := uniforms.duplicate()
	u["uMinPx"] = o.minPx
	u["uFar"] = o.far
	u["uOpacity"] = o.get("opacity", 1.0)
	var soft: bool = o.get("soft", false)
	var m := _mat("petals-" + o.name, "soft" if soft else "fall", u, shared, live)
	m.transparent = soft
	m.depth_write = not soft
	if not soft:
		m.alphaToCoverage = true
	return m


## floatMaterial(sheet, map) of petals.js.
static func float_material(sheet: bool, uniforms: Dictionary, shared: Dictionary, live: Dictionary) -> T.Mat:
	var m := _mat("petals-rafts" if sheet else "petals-floating", "rafts" if sheet else "float", uniforms, shared, live)
	m.alphaToCoverage = true
	return m


static func _value(v):
	if v is T.Tex:
		var img = v.user_data.get("image")
		return ImageTexture.create_from_image(img) if img != null else null
	if v is Color:
		return Vector3(v.r, v.g, v.b)
	return v


## The Godot ShaderMaterial for one of these materials.
static func material(m) -> ShaderMaterial:
	var p: Dictionary = m.user_data.get("petals", {})
	if p.is_empty():
		return null
	var sm := ShaderMaterial.new()
	sm.shader = load(SHADERS[p.shader])
	for k in p.uniforms:
		sm.set_shader_parameter(k, _value(p.uniforms[k]))
	if m.transparent:
		sm.render_priority = 3
	update(sm, m)
	return sm


## Per frame: the uniforms the original shares by reference (time, wind, gust, sun) and the ones its
## on_update writes (train slots, drawing-buffer height).
static func update(sm: ShaderMaterial, m) -> void:
	var p: Dictionary = m.user_data.get("petals", {})
	for k in ["uTime", "uWind", "uGust", "uSunDir"]:
		if p.shared.has(k):
			sm.set_shader_parameter(k, p.shared[k])
	for k in p.live:
		sm.set_shader_parameter(k, p.live[k])


## An InstancedMesh with petal attributes as a MultiMeshInstance3D: aA -> INSTANCE_CUSTOM, aB -> COLOR,
## aC -> (basis.x, basis.z.x), aD -> (basis.y, basis.z.y) of the instance transform; the origin stays
## zero, so all sixteen numbers ride in the basis the shaders read back from MODEL_MATRIX.
static func node(o) -> MultiMeshInstance3D:
	var g: T.Geometry = o.geometry
	var a := Mesh.ARRAY_MAX
	var arr := []
	arr.resize(a)
	arr[Mesh.ARRAY_VERTEX] = g.position().vec3_array()
	if g.has_attribute("normal"):
		arr[Mesh.ARRAY_NORMAL] = g.get_attribute("normal").vec3_array()
	if g.has_attribute("uv"):
		var uv: PackedFloat32Array = g.get_attribute("uv").array
		var uv2 := PackedVector2Array()
		for i in uv.size() / 2:
			uv2.append(Vector2(uv[i * 2], uv[i * 2 + 1]))
		arr[Mesh.ARRAY_TEX_UV] = uv2
	if g.indexed:
		var ix := g.index.duplicate()
		for i in range(0, ix.size(), 3):  # three.js fronts are CCW, Godot's CW
			var t := ix[i + 1]
			ix[i + 1] = ix[i + 2]
			ix[i + 2] = t
		arr[Mesh.ARRAY_INDEX] = ix
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = am
	var cnt: int = o.count
	mm.instance_count = cnt
	var A: PackedFloat32Array = g.get_attribute("aA").array
	var B: PackedFloat32Array = g.get_attribute("aB").array
	var C: PackedFloat32Array = g.get_attribute("aC").array
	var D: PackedFloat32Array = g.get_attribute("aD").array if g.has_attribute("aD") else PackedFloat32Array()
	for i in cnt:
		var k := i * 4
		var bx := Vector3(C[k], C[k + 1], C[k + 2])
		var by := Vector3(D[k], D[k + 1], D[k + 2]) if not D.is_empty() else Vector3(0, 1, 0)
		var bz := Vector3(C[k + 3], D[k + 3] if not D.is_empty() else 0.0, 0.0)
		mm.set_instance_transform(i, Transform3D(Basis(bx, by, bz), Vector3.ZERO))
		mm.set_instance_color(i, Color(B[k], B[k + 1], B[k + 2], B[k + 3]))
		mm.set_instance_custom_data(i, Color(A[k], A[k + 1], A[k + 2], A[k + 3]))
	mm.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))  # frustumCulled = false
	var mmi := MultiMeshInstance3D.new()
	mmi.name = o.name
	mmi.multimesh = mm
	mmi.material_override = material(o.material)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi
