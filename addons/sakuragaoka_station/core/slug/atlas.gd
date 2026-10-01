# The slughorn atlas slug.elf holds for every keyed canvas texture (through core/slug/pack.gd's cache), as Godot
# textures for core/slug/slug.gdshaderinc plus a per-key table. Built from one guest call:
#
#   slug_atlas() -> Dictionary
#     tex_width     int    curve and band texture width in texels (slughorn Atlas::getTextureWidth)
#     curve_format  String "RGBA32F" | "RGBA16F" (slughorn PackingStats::curveFormat)
#     curve_height  int
#     curves        PackedByteArray  the curve texture's bytes, row-major, as Atlas::getCurveTextureData
#     band_height   int
#     bands         PackedByteArray  the RG16UI band texture's bytes, row-major (4 bytes a texel)
#     keys          PackedStringArray  texture keys (textures.js keys), in table order
#     key_layers    PackedInt32Array   2 per key: first layer, layer count (into "layers")
#     key_frames    PackedFloat32Array 4 per key: authoring width px, height px, em per px,
#                                      y_down (1: canvas y down, the canvas top at em y 0)
#     layers        PackedFloat32Array LAYER_STRIDE per drawable layer (composites flattened,
#                                      source-over order; hidden/geometry/mask layers dropped):
#        0 band_tex_x  1 band_tex_y  2 band_max_x  3 band_max_y         (slughorn Atlas::Shape)
#        4 band_scale_x  5 band_scale_y  6 band_offset_x  7 band_offset_y
#        8 bearing_x  9 bearing_y  10 width  11 height
#        12 layer transform.x - shape origin_x  13 transform.y - origin_y  (canvas em - this = shape em)
#        14 gradient id (0 none, else 1-based into gradients); for a stamp layer its stamp layer index
#        15 blend mode (Layer::blendMode); 100 marks a stamp layer (core/slug/stamps.gd)
#        16..19 colour, linear RGBA (with a gradient only .a counts)  20..23 zero
#     gradients     PackedFloat32Array [n, per gradient: type (0 linear, 1 radial, 2 sweep,
#                   3 affine radial), xx, yx, xy, yy, dx, dy (GradientInfo::transform),
#                   inner_radius, start_angle, end_angle, stop count k, k * (t, r, g, b, a)]
#
# Textures (texelFetch only: nearest, no mipmaps, no repeat):
#   curves  as is: RGBA32F -> Image.FORMAT_RGBAF, RGBA16F -> FORMAT_RGBAH.
#   bands   the RG16UI bytes reinterpreted as FORMAT_RGBA8 (lossless; the shader rebuilds each
#           texel's R16 = r + g * 256, G16 = b + a * 256).
#   data    FORMAT_RGBAF, DATA_WIDTH wide, linear texel index: LAYER_TEXELS texels per layer
#           (see _data_texture), then each gradient's stops as two texels (t, -, -, -), (rgba).
#
#   var a = SlugAtlas.shared()                       # null without slug.elf
#   var k = a.key_info("st-floor", 512, 512) if a else null   # null when the key is absent
extends RefCounted

const Pack = preload("res://addons/sakuragaoka_station/core/slug/pack.gd")
const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const Stamps = preload("res://addons/sakuragaoka_station/core/slug/stamps.gd")
const LAYER_STRIDE := 24
const LAYER_TEXELS := 8
const DATA_WIDTH := 1024

static var _shared = null
static var _tried := false

var tex_width := 512
var curves: ImageTexture
var bands: ImageTexture
var data: ImageTexture
## key -> {"start", "count", "frame": PackedFloat32Array(4) or null}
var keys := {}
var layer_count := 0
var source := ""
## Texel index of each gradient's first stop in the data texture (gradient id - 1 -> texel).
var gradient_stops := PackedInt32Array()
## The stamp layers' textures (core/slug/stamps.gd), or null when the atlas has none.
var stamps = null
## The data texture marks stamp layers itself (texel 3.zw = (-2, stamp index)); stamps.gd checks this.
var marks_stamps := true


static func shared():
	if not _tried:
		_tried = true
		var g = Pack.shared()
		_shared = from_guest(g) if g != null else null
	return _shared


static func reset() -> void:
	_tried = false
	_shared = null


static func from_guest(g):
	var r = g.call_fn("slug_atlas")
	if not (r is Dictionary) or r.is_empty():
		push_warning("slug: slug_atlas() returned %s" % type_string(typeof(r)))
		return null
	var a = new()
	a.source = str(g.get("name") if g.get("name") != null else "slug.elf")
	return a if a._build(r) else null


func has(key: String) -> bool:
	return keys.has(key) and keys[key].count > 0


## The shader's view of a texture key, or null when the atlas does not hold it. w, h: the texture's
## authoring size in pixels, used when the guest records no frame for the key.
func key_info(key: String, w: int = 1, h: int = 1):
	if not has(key):
		return null
	return {"layers": Vector2i(keys[key].start, keys[key].count), "frame": frame_of(key, w, h)}


## em = frame.zw + uv * frame.xy, uv in three.js convention (v up). Without a recorded frame the
## nanosvg convention: 1 / width em per px, canvas y down.
func frame_of(key: String, w: int, h: int) -> Vector4:
	var f = keys[key].frame
	var fw := float(w)
	var fh := float(h)
	var s := 1.0 / maxf(fw, 1.0)
	var down := true
	if f != null and f[2] > 0.0:
		fw = f[0]
		fh = f[1]
		s = f[2]
		down = f[3] > 0.5
	var ex := fw * s
	var ey := fh * s
	return Vector4(ex, -ey, 0.0, ey) if down else Vector4(ex, ey, 0.0, 0.0)


func _build(r: Dictionary) -> bool:
	tex_width = int(r.get("tex_width", 0))
	var ch := int(r.get("curve_height", 0))
	var bh := int(r.get("band_height", 0))
	var cb: PackedByteArray = r.get("curves", PackedByteArray())
	var bb: PackedByteArray = r.get("bands", PackedByteArray())
	var half := str(r.get("curve_format", "RGBA32F")) == "RGBA16F"
	if tex_width <= 0 or ch <= 0 or bh <= 0 or cb.size() < tex_width * ch * (8 if half else 16) or bb.size() < tex_width * bh * 4:
		push_warning("slug: slug_atlas() textures: width %d, curves %d rows / %d bytes, bands %d rows / %d bytes" % [
				tex_width, ch, cb.size(), bh, bb.size()])
		return false
	curves = ImageTexture.create_from_image(Image.create_from_data(tex_width, ch, false,
			Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF, cb.slice(0, tex_width * ch * (8 if half else 16))))
	bands = ImageTexture.create_from_image(Image.create_from_data(tex_width, bh, false, Image.FORMAT_RGBA8,
			bb.slice(0, tex_width * bh * 4)))
	var names: PackedStringArray = r.get("keys", PackedStringArray())
	var kl: PackedInt32Array = r.get("key_layers", PackedInt32Array())
	var kf: PackedFloat32Array = r.get("key_frames", PackedFloat32Array())
	var layers: PackedFloat32Array = r.get("layers", PackedFloat32Array())
	layer_count = layers.size() / LAYER_STRIDE
	for i in names.size():
		var start := kl[i * 2] if kl.size() > i * 2 + 1 else 0
		var count := kl[i * 2 + 1] if kl.size() > i * 2 + 1 else 0
		if start < 0 or count < 0 or start + count > layer_count:
			push_warning("slug: key %s: layers %d+%d past %d" % [names[i], start, count, layer_count])
			continue
		keys[names[i]] = {"start": start, "count": count, "frame": kf.slice(i * 4, i * 4 + 4) if kf.size() >= i * 4 + 4 else null}
	var grads: PackedFloat32Array = r.get("gradients", PackedFloat32Array([0]))
	data = _data_texture(layers, grads)
	gradient_stops = Kernels.gradient_stops(layer_count, grads)
	if r.get("stamp_layers", PackedInt32Array()).size() >= 5:
		stamps = Stamps.build(r, self)
	return true


## The data texture (packed by Kernels.pack_layers). Per layer, LAYER_TEXELS RGBA float texels for slug.gdshaderinc:
##   0 bandTexX, bandTexY, bandMaxX, bandMaxY
##   1 bandScaleX, bandScaleY, bandOffsetX, bandOffsetY
##   2 colour (linear RGBA)
##   3 em offset x, y, gradient type (-1 none, 0 linear, 1 radial, 2 sweep, 3 affine radial, -2 a stamp
##     layer), first stop texel (a stamp layer: its stamp layer index)
##   4 gradient matrix xx, yx, xy, yy
##   5 gradient matrix dx, dy, inner radius, stop count
##   6 blend mode, 0, 0, 0
##   7 shape bounds in shape em: minX, minY, maxX, maxY
func _data_texture(layers: PackedFloat32Array, grads: PackedFloat32Array) -> ImageTexture:
	var px := Kernels.pack_layers(layers, grads)
	return ImageTexture.create_from_image(Image.create_from_data(DATA_WIDTH, px.size() / (DATA_WIDTH * 4), false, Image.FORMAT_RGBAF, px.to_byte_array()))


## Sets the atlas textures and a key's layers on a material using slug.gdshaderinc. prefix "" for
## the map, "alpha_" for the alpha map.
func bind(sm: ShaderMaterial, info: Dictionary, repeat: Vector2, offset: Vector2, wrap: bool, prefix: String = "") -> void:
	sm.set_shader_parameter("slug_curves", curves)
	sm.set_shader_parameter("slug_bands", bands)
	sm.set_shader_parameter("slug_data", data)
	sm.set_shader_parameter("slug_tex_width", tex_width)
	sm.set_shader_parameter("slug_%skey" % prefix, info.layers)
	sm.set_shader_parameter("slug_%sframe" % prefix, info.frame)
	sm.set_shader_parameter("slug_%suv" % prefix, Vector4(repeat.x, repeat.y, offset.x, offset.y))
	sm.set_shader_parameter("slug_%swrap" % prefix, wrap)
	if stamps != null:
		stamps.bind(sm)
