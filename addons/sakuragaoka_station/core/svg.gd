# The canvas textures src/core/textures.js draws, as vector content for the headset. Rasterized
# vector art blurs in VR, so nothing here becomes a bitmap: a sign takes its background colour on
# its own mesh, and its frame and text are to arrive as meshes triangulated from SVG paths and
# glyph outlines with core/earcut.gd, one flat colour per fill, or as Slug curves where a fill is
# a gradient.
extends RefCounted


## The linear colour a sign's mesh takes, or null when the texture is not a sign.
static func sign_colour(t):
	if t == null or not t.user_data.has("sign"):
		return null
	return Color.html(str(t.user_data["sign"].get("bg", "#ffffff"))).srgb_to_linear()
