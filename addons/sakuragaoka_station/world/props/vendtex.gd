# props/vendtex.js: the vending machines' canvas textures and their tables. The port draws no
# canvases, so each texture is a sized stand-in under the original's key; the brand, product,
# shape, label-atlas and swatch tables are the original's.
extends RefCounted

const BRANDS := {
	"haru": {"name": "はるかぜ飲料", "en": "HARUKAZE BEVERAGE", "casing": "#ece7e0", "door": "#f0ece6", "trim": "#e592ad", "stile": "#e9e3dc", "inner": "#f3f0ea"},
	"sakura": {"name": "SAKURA DRINKS", "jp": "さくらドリンクス", "casing": "#d7675f", "door": "#dc6e65", "trim": "#fbf2ec", "stile": "#cf5f58", "inner": "#f6ece6"},
	"aozora": {"name": "あおぞら飲料", "en": "AOZORA DRINK", "casing": "#a6c8e4", "door": "#afcfe8", "trim": "#2f6db8", "stile": "#9dc0de", "inner": "#eef4f9"},
	"midori": {"name": "みどり茶房", "en": "MIDORI SABOU", "casing": "#a3d6bf", "door": "#aadbc5", "trim": "#2d7a57", "stile": "#98cdb5", "inner": "#eef6f1"},
}

# ------------------------------------------------------------------ products
# shape: can350 / can190 / pet500 / pet350 / petHot. cell = label atlas cell. swatches allocated below.
const SHAPES := {
	"can350": {"kind": "can", "r": 0.033, "h": 0.122},
	"can190": {"kind": "can", "r": 0.0265, "h": 0.104},
	"pet500": {"kind": "pet", "r": 0.034, "h": 0.205},
	"pet350": {"kind": "pet", "r": 0.031, "h": 0.165},
	"petHot": {"kind": "pet", "r": 0.032, "h": 0.158},
}

const _PRODUCTS := {
	"coffee": {"shape": "can190", "cell": 0, "price": 130},
	"black": {"shape": "can190", "cell": 1, "price": 130},
	"greenTea": {"shape": "pet500", "cell": 2, "price": 160, "cap": "#3f8a55", "liquid": "#bfcb8e"},
	"greenTeaHot": {"shape": "petHot", "cell": 2, "price": 160, "cap": "#ec8a2c", "liquid": "#bfcb8e"},
	"lemon": {"shape": "can350", "cell": 3, "price": 150},
	"ichigo": {"shape": "pet350", "cell": 4, "price": 150, "cap": "#e57b9b", "liquid": "#f6cdd8"},
	"water": {"shape": "pet500", "cell": 5, "price": 120, "cap": "#5a8fd0", "liquid": "#e4f1f8"},
	"orange": {"shape": "pet500", "cell": 6, "price": 160, "cap": "#ec8d2e", "liquid": "#f7b45a"},
	"sakuraLatte": {"shape": "pet500", "cell": 7, "price": 170, "cap": "#e98aa6", "liquid": "#f6c9d5"},
	"sakuraSoda": {"shape": "can350", "cell": 8, "price": 150},
	"oshiruko": {"shape": "can190", "cell": 9, "price": 140},
	"potage": {"shape": "can190", "cell": 10, "price": 140},
	"mugi": {"shape": "pet500", "cell": 11, "price": 150, "cap": "#8a5a34", "liquid": "#caa05c"},
	"milkTea": {"shape": "petHot", "cell": 12, "price": 160, "cap": "#ec8a2c", "liquid": "#d9ba92"},
	"ion": {"shape": "pet500", "cell": 13, "price": 150, "cap": "#3f7bd0", "liquid": "#e7f0f8"},
	"cider": {"shape": "can350", "cell": 14, "price": 140},
	"cafeLatte": {"shape": "can350", "cell": 15, "price": 140},
}
const ATLAS := {"W": 1024, "H": 1024, "cw": 256, "ch": 128, "swY": 896}
const SWATCH := {"silver": 0, "lid": 1, "dark": 2}

static var _products := {}


## PRODUCTS with the swatches the original allocates at load: capSw / liqSw per capped product.
static func products() -> Dictionary:
	if _products.is_empty():
		_products = _PRODUCTS.duplicate(true)
		var i := 3
		for p in _products.values():
			if p.get("cap"):
				p["capSw"] = i
				i += 1
				p["liqSw"] = i
				i += 1
	return _products


static func swatch_px(i: int) -> Array:
	return [(i % 64) * 16 + 8, ATLAS.swY + floori(i / 64.0) * 16 + 8]


static func cell_px(cell: int) -> Array:
	return [(cell % 4) * ATLAS.cw, floori(cell / 4.0) * ATLAS.ch]


static func make_vend_textures(ctx) -> Dictionary:
	var T = ctx.tex
	# ---------------------------------------------------------------- label atlas
	var atlas = T.draw(ATLAS.W, ATLAS.H, null, {"key": "props.vend.atlas", "anisotropy": 8})
	# ---------------------------------------------------------------- brand headers (1024x224)
	var headers := {}
	for b in ["haru", "sakura", "aozora", "midori"]:
		headers[b] = T.draw(1024, 224, null, {"key": "props.vend.head." + b})
	# ---------------------------------------------------------------- side graphics (384x1024), alpha
	var sides := {}
	for b in ["haru", "sakura", "aozora", "midori"]:
		sides[b] = T.draw(384, 1024, null, {"key": "props.vend.side." + b})
	# ---------------------------------------------------------------- grime (alpha)
	var grime := func(strong: bool): return T.draw(256, 128, null, {"key": "props.vend.grime" + ("S" if strong else "")})
	# price rails: rows of {price, hot, sold}, drawn at the slot xs
	var rails := func(id: String, _rows: Array, _xs: Array): return T.draw(1024, 160, null, {"key": "props.vend.rails." + id, "anisotropy": 8})
	var lower_panel := func(id: String, _brand: String, _ad: String, _opts: Dictionary = {}): return T.draw(512, 448, null, {"key": "props.vend.lower." + id, "anisotropy": 8})
	var ic_face = T.draw(128, 96, null, {"key": "props.vend.ic"})
	var back_panel = T.draw(64, 256, null, {"key": "props.vend.back"})
	var sticker = T.draw(256, 256, null, {"key": "props.sticker.sakurapon"})
	var flag = T.draw(128, 448, null, {"key": "props.flag.sakura"})
	var bin := func(style: String): return T.draw(256, 320, null, {"key": "props.bin." + style})
	var crate := func(c: String): return T.draw(256, 128, null, {"key": "props.crate." + c})
	return {"atlas": atlas, "headers": headers, "sides": sides, "grime": grime, "rails": rails, "lowerPanel": lower_panel,
		"icFace": ic_face, "backPanel": back_panel, "sticker": sticker, "flag": flag, "bin": bin, "crate": crate}
