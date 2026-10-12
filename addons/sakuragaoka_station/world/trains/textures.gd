# trains/textures.js: canvas atlases for the trains (decals: logo, numbers, stickers, ads; LED/LCD
# displays; petals). The port draws no canvases, so each atlas is a sized stand-in under the
# original's key; the atlas cell tables and UV mapping are the original's.
extends RefCounted

const DEC_W := 1024
const DEC_H := 1024
const LED_W := 1024
const LED_H := 256

const DEC_RECTS := {
	"emblem": [0, 0, 256, 256],
	"wordmark": [256, 0, 512, 128],
	"jakurei": [768, 0, 256, 128],
	"priority": [256, 128, 512, 128],
	"wheelchair": [768, 128, 128, 128],
	"stroller": [896, 128, 128, 128],
	"doorCaution": [0, 256, 128, 128],
	"mascot": [128, 256, 128, 128],
	"kids": [256, 256, 128, 128],
	"prioritySign": [384, 256, 256, 64],
	"crewSign": [384, 320, 256, 64],
	"routeMap": [640, 256, 384, 128],
	"num0": [0, 384, 256, 64], "num1": [256, 384, 256, 64], "num2": [512, 384, 256, 64], "num3": [768, 384, 256, 64],
	"num4": [0, 448, 256, 64], "num5": [256, 448, 256, 64], "num6": [512, 448, 256, 64], "num7": [768, 448, 256, 64],
	"ad0": [0, 512, 256, 160], "ad1": [256, 512, 256, 160], "ad2": [512, 512, 256, 160], "ad3": [768, 512, 256, 160],
	"ad4": [0, 672, 256, 160], "ad5": [256, 672, 256, 160],
	"hang0": [512, 672, 256, 128], "hang1": [768, 672, 256, 128], "hang2": [0, 832, 256, 128], "hang3": [256, 832, 256, 128],
	"emergency": [512, 832, 128, 64], "plate": [640, 832, 128, 64], "gangway": [768, 832, 128, 128], "cabPanel": [896, 832, 128, 128],
	"jumperWarn": [512, 896, 128, 64],
}
const LED_RECTS := {
	"destA": [0, 0, 512, 128], "destB": [512, 0, 512, 128],
	"runA": [0, 128, 128, 64], "runB": [128, 128, 128, 64],
	"lcdA": [256, 128, 256, 64], "lcdB": [512, 128, 256, 64],
	"cab": [768, 128, 128, 64], "cab2": [896, 128, 128, 64],
	"sideA": [0, 192, 384, 64], "sideB": [384, 192, 384, 64],
}
const CAR_NUMBERS := {"A": ["5001", "5101"], "B": ["5002", "5102"]}


static func to_uv(r: Array, W: float, H: float) -> Dictionary:
	return {"u0": r[0] / W, "u1": (r[0] + r[2]) / W, "v0": 1.0 - (r[1] + r[3]) / H, "v1": 1.0 - r[1] / H}


static func dec(k: String) -> Dictionary:
	return to_uv(DEC_RECTS[k], DEC_W, DEC_H)


static func led_uv(k: String) -> Dictionary:
	return to_uv(LED_RECTS[k], LED_W, LED_H)


# ------------------------------------------------------------------ atlases
static func create_train_textures(ctx) -> Dictionary:
	var Tx = ctx.tex
	var decal = Tx.draw(DEC_W, DEC_H, null, {"key": "trains.decal", "anisotropy": 8})
	var led = Tx.draw(LED_W, LED_H, null, {"key": "trains.led", "anisotropy": 8})
	var petal = Tx.draw(64, 64, null, {"key": "trains.petal"})
	return {"decal": decal, "led": led, "petal": petal, "dec": dec_static(), "ledUV": led_static()}


static func dec_static() -> Callable:
	return func(k: String) -> Dictionary: return to_uv(DEC_RECTS[k], DEC_W, DEC_H)


static func led_static() -> Callable:
	return func(k: String) -> Dictionary: return to_uv(LED_RECTS[k], LED_W, LED_H)
