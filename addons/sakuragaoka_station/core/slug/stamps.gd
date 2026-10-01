# Stamp layers (FX-Map-style instancing) for core/slug/slug.gdshaderinc: the textures behind a layer
# whose record (atlas.gd's "layers", 24 floats) has blend mode slot 15 == STAMP_BLEND, slot 14 being
# its index into stamp_layers. Built from the same slug_atlas() Dictionary atlas.gd reads, whose
# extra fields are:
#   stamp_protos     PackedFloat32Array 2 per prototype: kind (0 curve shape, 1 ellipse: the unit
#                    circle at the origin, 2 rect: the 0..1 square), layer (kind 0: the index into
#                    "layers" of a band layer whose canvas em is the prototype's frame; else -1)
#   stamp_instances  PackedFloat32Array 12 per instance: inverse affine a, b, c, d, e, f, mapping the
#                    key's canvas em point (x, y) (after the stamp layer's own em offset, slots
#                    12..13) to q = (a x + c y + e, b x + d y + f) in the prototype's frame; proto
#                    id; paint (0 solid colour, > 0 a 1-based id into "gradients", evaluated at q,
#                    i.e. fixed to the instance, times the colour); colour, linear straight RGBA
#   stamp_layers     PackedInt32Array 5 per stamp layer: G (grid G x G over the key's UV, three.js
#                    convention, cell (i, j) = floor(uv * G), index j * G + i), first cell texel
#                    (into stamp_cells), first instance, instance count, max instances per cell (<= 32;
#                    the guest splits a deeper run into consecutive stamp layers)
#   stamp_cells      PackedByteArray, cell texels (encode_cells()'s encoding, RG16UI: 4 bytes a
#                    texel, two little-endian u16). Per stamp layer from its first cell texel B:
#                    G * G texels (list start, count), the start in u16 elements from 2 * B; then the
#                    lists, two instance indices (from the layer's first instance) a texel, in paint
#                    order. An instance is listed in every cell its AA-padded bbox touches.
#   stamp_means      PackedByteArray 4 per cell: the cell's mean premultiplied colour, RGBA8, stamp
#                    layers in order, cells in index order
#
# Textures (texelFetch only, SLUG_STAMP_WIDTH = WIDTH texels wide, linear texel index):
#   stamps  FORMAT_RGBAF: per stamp layer 2 texels (G, cell texel, first instance texel, count),
#           (max per cell, mean texel, 0, 0); then per instance 3 texels (a, b, c, d),
#           (e, f, shape, paint), (r, g, b, a), shape -2 rect, -1 ellipse, else the curve
#           prototype's layer (the prototype folded into the instance), paint -1 or the texel of a
#           gradient record; then per gradient 3 texels (xx, yx, xy, yy), (dx, dy, inner radius,
#           stop count), (type, first stop texel in atlas.gd's data texture, 0, 0): the fields
#           atlas.gd gives a gradient layer, its stops shared with the atlas.
#   cells   stamp_cells as encode_cells() stores it, then the means as RGBA8 texels.
# and a stamp layer's texel 3.zw in atlas.gd's data texture is (-2, stamp index), the value
# slug.gdshaderinc branches on (atlas.gd writes it; slot 14 is not read as a gradient there).
#
# Limits of the RG16UI cell encoding: per stamp layer, list starts below 65536 u16 elements and
# instance indices below 65536 (the guest splits bigger runs into consecutive stamp layers).
#
# The arrays are packed by Kernels.pack_stamps (core/slug/slug_kernels.sgd, compiled); this wrapper
# makes the textures. The atlas is duck-typed: atlas.gd marks stamp layers itself (marks_stamps);
# any other atlas with a .data ImageTexture is patched here.
#   var r = guest.call_fn("slug_atlas")         # the Dictionary atlas.gd builds from
#   var s = Stamps.build(r, atlas)               # null when there are no stamp layers
#   atlas.bind(sm, info, ...); if s: s.bind(sm)  # or Stamps.from_guest(guest, atlas)
extends RefCounted

const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const STAMP_BLEND := 100
const MAX_PER_CELL := 32
const WIDTH := 1024
const LAYER_STRIDE := 24
const LAYER_TEXELS := 8
const DATA_WIDTH := 1024
const KIND_CURVE := 0
const KIND_ELLIPSE := 1
const KIND_RECT := 2

var stamps: ImageTexture
var cells: ImageTexture
var stamp_layer_count := 0
var instance_count := 0
## global layer index -> stamp layer index, for every stamp layer in "layers"
var stamp_of_layer := {}


## build() over a fresh slug_atlas() call (a loader that already holds the Dictionary calls build()).
static func from_guest(g, atlas):
	var r = g.call_fn("slug_atlas") if g != null and atlas != null else null
	return build(r, atlas) if r is Dictionary else null


## The stamp textures from a slug_atlas() Dictionary, patching atlas's data texture so the shader
## sees which layers are stamp layers. null when there are none or the arrays are inconsistent.
static func build(r: Dictionary, atlas):
	var layers: PackedFloat32Array = r.get("layers", PackedFloat32Array())
	var sl: PackedInt32Array = r.get("stamp_layers", PackedInt32Array())
	if sl.size() < 5:
		return null
	var s = new()
	return s if s._build(r, layers, sl, atlas) else null


## The one place that knows the cell texel encoding (with slug_stamp_cell() in the shader): the
## guest's RG16UI bytes, reinterpreted losslessly as RGBA8, as atlas.gd does for bands; the RGBA8
## means follow the guest's cells. Switching to another format changes this and slug_stamp_cell().
static func encode_cells(bytes: PackedByteArray, means: PackedByteArray) -> Image:
	var px := PackedByteArray(bytes)
	px.append_array(means)
	var rows := maxi(1, ceili(float(maxi(px.size() / 4, 1)) / WIDTH))
	px.resize(WIDTH * rows * 4)
	return Image.create_from_data(WIDTH, rows, false, Image.FORMAT_RGBA8, px)


## Reads cell texel i back as its two u16 fields (CPU mirror of slug_stamp_cell()).
static func cell_fields(bytes: PackedByteArray, i: int) -> Vector2i:
	return Vector2i(bytes.decode_u16(i * 4), bytes.decode_u16(i * 4 + 2))


func _build(r: Dictionary, layers: PackedFloat32Array, sl: PackedInt32Array, atlas) -> bool:
	var grads: PackedFloat32Array = r.get("gradients", PackedFloat32Array([0]))
	var stops: PackedInt32Array = atlas.gradient_stops if atlas != null and atlas.get("gradient_stops") != null 			else Kernels.gradient_stops(layers.size() / LAYER_STRIDE, grads)
	var k := Kernels.pack_stamps(r, stops)
	if k.error != "":
		push_warning("slug stamps: " + k.error)
		return false
	stamp_layer_count = k.stamp_layer_count
	instance_count = k.instance_count
	stamps = ImageTexture.create_from_image(Image.create_from_data(WIDTH, k.rows, false, Image.FORMAT_RGBAF, k.px.to_byte_array()))
	cells = ImageTexture.create_from_image(Image.create_from_data(WIDTH, k.cell_rows, false, Image.FORMAT_RGBA8, k.cells))
	var sol: PackedInt32Array = k.stamp_of_layer
	for i in range(0, sol.size(), 2):
		stamp_of_layer[sol[i]] = sol[i + 1]
	# atlas.gd marks the stamp layers in its data texture itself (texel 3.zw = (-2, stamp index));
	# an atlas without that mark gets it here
	if atlas != null and atlas.get("data") != null and not atlas.get("marks_stamps"):
		var img: Image = atlas.data.get_image()
		for li in stamp_of_layer:
			var t: int = li * LAYER_TEXELS + 3
			var v := img.get_pixel(t % DATA_WIDTH, t / DATA_WIDTH)
			img.set_pixel(t % DATA_WIDTH, t / DATA_WIDTH, Color(v.r, v.g, -2.0, stamp_of_layer[li]))
		atlas.data.update(img)
	return true


## Sets the stamp textures on a material using slug.gdshaderinc (after the atlas's bind()). fade:
## the footprint (px) where a cell is all mean colour and where it is all stamps.
func bind(sm: ShaderMaterial, fade := Vector2(0.75, 1.5)) -> void:
	sm.set_shader_parameter("slug_stamps", stamps)
	sm.set_shader_parameter("slug_stamp_cells", cells)
	sm.set_shader_parameter("slug_stamp_fade", fade)
