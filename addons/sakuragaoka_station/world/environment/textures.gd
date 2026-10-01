# environment/textures.js: the canvas textures at the original's sizes, keys and repeat, each key drawn
# from its SVG in the Slug pack.
extends RefCounted


class Fields extends RefCounted:
	var dry
	var veg
	var renge
	var wheat
	var nano
	var grass


class EnvTextures extends RefCounted:
	var ground
	var levee
	var masonry
	var path
	var tufts
	var flowers
	var mats
	var reeds
	var fields := Fields.new()
	var railing
	var shrub
	var facade
	var school

	func _init(ctx) -> void:
		var T = ctx.tex
		ground = T.draw(512, 512, null, {"key": "env-ground", "repeat": [1, 1]})
		levee = T.draw(512, 512, null, {"key": "env-levee", "repeat": [1, 1]})
		masonry = T.draw(512, 512, null, {"key": "env-masonry2", "repeat": [1, 1]})
		path = T.draw(512, 512, null, {"key": "env-path", "repeat": [1, 1]})
		tufts = T.draw(1024, 512, null, {"key": "env-tufts2"})
		flowers = T.draw(1024, 512, null, {"key": "env-flowers2"})
		mats = T.draw(512, 512, null, {"key": "env-mats"})
		reeds = T.draw(512, 512, null, {"key": "env-reeds2"})
		for k in ["dry", "veg", "renge", "wheat", "nano", "grass"]:
			fields.set(k, T.draw(256, 256, null, {"key": "env-field-" + k, "repeat": [1, 1]}))
		railing = T.draw(256, 128, null, {"key": "env-railing", "repeat": [1, 1]})
		shrub = T.draw(256, 256, null, {"key": "env-shrub2", "repeat": [1, 1]})
		facade = T.draw(256, 128, null, {"key": "env-facade"})
		school = T.draw(512, 128, null, {"key": "env-school"})

	func sub(name: String):
		return fields if name == "fields" else null


static func create_env_textures(ctx):
	return EnvTextures.new(ctx)
