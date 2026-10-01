# environment/textures.js: the canvas textures (ground, levee, masonry, fields ...). The port draws
# none of them; every key is a sized stand-in so materials keep distinct maps.
extends RefCounted


static func create_env_textures(ctx):
	return ctx.tex.bag()
