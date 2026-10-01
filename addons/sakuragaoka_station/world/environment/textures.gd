# environment/textures.js: the canvas textures at the original's sizes, keys and repeat, each key drawn
# from its SVG in the Slug pack; the ones not keyed yet are sized stand-ins.
extends RefCounted


class EnvTextures extends RefCounted:
	var masonry
	var path
	var _rest

	func _init(ctx) -> void:
		var T = ctx.tex
		_rest = T.bag()
		masonry = T.draw(512, 512, null, {"key": "env-masonry2", "repeat": [1, 1]})
		path = T.draw(512, 512, null, {"key": "env-path", "repeat": [1, 1]})

	func _get(p: StringName):
		return _rest.get(p)

	func sub(name: String):
		return _rest.sub(name)


static func create_env_textures(ctx):
	return EnvTextures.new(ctx)
