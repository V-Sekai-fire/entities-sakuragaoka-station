# station/tex.js and tex2.js: the canvas textures and atlases. The port draws none of them; an
# atlas is a texture stand-in whose items all map to the whole sheet (UVs only, never geometry).
extends RefCounted


class Atlas extends RefCounted:
	var tex
	var size := 1024

	func _init(t) -> void:
		tex = t

	func r(_id) -> Dictionary:
		return {"u0": 0.0, "v0": 0.0, "u1": 1.0, "v1": 1.0, "w": 64, "h": 64}


static func create_station_textures(ctx):
	var tx = ctx.tex.bag()
	var atlases := {}
	for name in ["signs", "face", "misc", "P", "B", "I", "TVM", "FOL"]:
		atlases[name] = Atlas.new(ctx.tex.draw(1024, 1024))
	return {"bag": tx, "atlases": atlases}


static func create_interior_textures(ctx, _tx):
	return {"bag": ctx.tex.bag(), "atlases": {"N": Atlas.new(ctx.tex.draw(1024, 1024))}}
