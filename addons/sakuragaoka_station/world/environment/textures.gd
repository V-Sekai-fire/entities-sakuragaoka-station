# environment/textures.js: the canvas textures at the original's sizes, keys and repeat, each key drawn
# from its SVG in the Slug pack; the ones not keyed yet are sized stand-ins.
extends RefCounted


class EnvTextures extends RefCounted:
	var ground
	var tufts
	var flowers
	var mats
	var reeds
	var _rest

	func _init(ctx) -> void:
		var T = ctx.tex
		_rest = T.bag()
		ground = T.draw(512, 512, null, {"key": "env-ground", "repeat": [1, 1]})
		tufts = T.draw(1024, 512, null, {"key": "env-tufts2"})
		flowers = T.draw(1024, 512, null, {"key": "env-flowers2"})
		mats = T.draw(512, 512, null, {"key": "env-mats"})
		reeds = T.draw(512, 512, null, {"key": "env-reeds2"})

	func _get(p: StringName):
		return _rest.get(p)

	func sub(name: String):
		return _rest.sub(name)


static func create_env_textures(ctx):
	return EnvTextures.new(ctx)
