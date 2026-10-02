# street/textures.js: the street's canvas textures and atlas cell tables. The port draws no canvases, so
# each texture is a sized stand-in under the original's key; the cell tables are the original's.
extends RefCounted

const ATLAS := 1024

const GLYPH := {
	"tomare": {"x": 0, "y": 0, "w": 256, "h": 768},
	"jokou": {"x": 256, "y": 0, "w": 256, "h": 512},
	"n30": {"x": 256, "y": 512, "w": 256, "h": 256},
	"school": {"x": 512, "y": 0, "w": 512, "h": 256},
	"hokou": {"x": 512, "y": 256, "w": 512, "h": 256},
	"tsugaku": {"x": 512, "y": 512, "w": 128, "h": 384},
	"navi": {"x": 640, "y": 512, "w": 128, "h": 256},
	"kids": {"x": 768, "y": 512, "w": 256, "h": 256},
	"diamond": {"x": 640, "y": 768, "w": 128, "h": 256},
	"bike": {"x": 0, "y": 768, "w": 256, "h": 256},
	"tomareS": {"x": 256, "y": 768, "w": 256, "h": 256},
	"arrowUp": {"x": 768, "y": 768, "w": 128, "h": 256},
	"bus": {"x": 896, "y": 768, "w": 128, "h": 256},
	"litter": {"x": 512, "y": 896, "w": 128, "h": 128},
}
const UTIL := {
	"manholeA": {"x": 0, "y": 0, "w": 256, "h": 256},
	"manholeB": {"x": 256, "y": 0, "w": 256, "h": 256},
	"hydrant": {"x": 512, "y": 0, "w": 256, "h": 384},
	"valveR": {"x": 768, "y": 0, "w": 128, "h": 128},
	"valveS": {"x": 896, "y": 0, "w": 128, "h": 128},
	"gas": {"x": 768, "y": 128, "w": 128, "h": 128},
	"drain": {"x": 896, "y": 128, "w": 128, "h": 128},
	"patchA": {"x": 0, "y": 256, "w": 256, "h": 256},
	"patchB": {"x": 256, "y": 256, "w": 256, "h": 256},
	"trench": {"x": 768, "y": 256, "w": 128, "h": 512},
	"seal": {"x": 896, "y": 256, "w": 128, "h": 512},
	"patchC": {"x": 512, "y": 384, "w": 256, "h": 256},
	"oilA": {"x": 0, "y": 512, "w": 128, "h": 128},
	"oilB": {"x": 128, "y": 512, "w": 128, "h": 128},
	"stain": {"x": 256, "y": 512, "w": 256, "h": 128},
	"sprayA": {"x": 0, "y": 640, "w": 256, "h": 256},
	"sprayB": {"x": 256, "y": 640, "w": 256, "h": 256},
	"sprayC": {"x": 512, "y": 640, "w": 256, "h": 256},
	"skid": {"x": 0, "y": 896, "w": 256, "h": 128},
	"wet": {"x": 256, "y": 896, "w": 256, "h": 128},
	"fresh": {"x": 512, "y": 896, "w": 256, "h": 128},
	"manholeC": {"x": 768, "y": 768, "w": 256, "h": 256},
}
const SIGN := {
	"n30": {"x": 0, "y": 0, "w": 256, "h": 256},
	"noPark": {"x": 256, "y": 0, "w": 256, "h": 256},
	"stop": {"x": 512, "y": 0, "w": 256, "h": 256},
	"cross": {"x": 768, "y": 0, "w": 256, "h": 256},
	"school": {"x": 0, "y": 256, "w": 256, "h": 256},
	"pTsugaku": {"x": 256, "y": 256, "w": 256, "h": 96},
	"p820": {"x": 256, "y": 352, "w": 256, "h": 96},
	"pStop": {"x": 512, "y": 256, "w": 256, "h": 128},
	"pPriority": {"x": 768, "y": 256, "w": 256, "h": 96},
	"pSchool": {"x": 768, "y": 352, "w": 256, "h": 96},
	"pTown": {"x": 256, "y": 448, "w": 256, "h": 64},
	"guide": {"x": 0, "y": 512, "w": 512, "h": 384},
	"hydrant": {"x": 512, "y": 512, "w": 128, "h": 256},
	"back": {"x": 960, "y": 960, "w": 64, "h": 64},
	"pole": {"x": 896, "y": 960, "w": 64, "h": 64},
}


## Atlas cell plus local (u, v in 0..1, v = 1 top) to texture uv.
static func uv_of(cell: Dictionary, u: float, v: float) -> Array:
	return [(cell.x + u * cell.w) / float(ATLAS), 1.0 - (cell.y + (1.0 - v) * cell.h) / float(ATLAS)]


static func make_street_textures(ctx) -> Dictionary:
	var T = ctx.tex
	return {
		"asphalt": T.draw(1024, 1024, null, {"key": "st-asphalt", "repeat": [1, 1], "anisotropy": 16}),
		"pavers": T.draw(1024, 1024, null, {"key": "st-pavers", "repeat": [1, 1], "anisotropy": 8}),
		"curb": T.draw(512, 128, null, {"key": "st-curb", "repeat": [1, 1]}),
		"lgutter": T.draw(256, 64, null, {"key": "st-lgutter", "repeat": [1, 1]}),
		"lid": T.draw(512, 256, null, {"key": "st-lid", "repeat": [1, 1], "anisotropy": 8}),
		"grate": T.draw(256, 256, null, {"key": "st-grate"}),
		"dots": T.draw(256, 256, null, {"key": "st-dots", "repeat": [1, 1]}),
		"bars": T.draw(256, 256, null, {"key": "st-bars", "repeat": [1, 1]}),
		"line": T.draw(512, 512, null, {"key": "st-line", "repeat": [1, 1], "anisotropy": 16}),
		"paint": T.draw(512, 512, null, {"key": "st-paint", "repeat": [1, 1], "anisotropy": 16}),
		"glyphs": T.draw(ATLAS, ATLAS, null, {"key": "st-glyphs", "anisotropy": 16}),
		"util": T.draw(ATLAS, ATLAS, null, {"key": "st-util", "anisotropy": 16}),
		"signs": T.draw(ATLAS, ATLAS, null, {"key": "st-signs", "anisotropy": 8}),
	}
