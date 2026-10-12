# poles/atlas.js: canvas atlases for the poles module: concrete shaft strip, tiger-stripe sleeve,
# yellow guard, transformer wrap, enamel pole ads and telecom plates (atlas A, opaque) and pole
# number plates, stickers, pole-mounted signs (atlas B, alpha-tested die-cuts). The port draws no
# canvases: each atlas is a sized stand-in under the original's key; the cell tables are the
# original's, so every part samples the same UV rect.
extends RefCounted

const AW := 1024

# rects (px, top-left origin)
const RA := {
	"shaft": [1, 0, 127, 1024],
	"white": [128, 0, 160, 32],
	"sleeve": [160, 0, 416, 256],
	"cover": [416, 0, 480, 256],
	"trans": [128, 256, 448, 512],
	"guard": [160, 32, 416, 256],  # re-use of the sleeve stripes for guy guards
}

const RB := {
	"mascot0": [0, 0, 160, 160], "mascot1": [160, 0, 320, 160], "mascot2": [320, 0, 480, 160],
	"camera": [480, 0, 608, 96], "suido": [480, 96, 608, 160],
	"harigami": [608, 0, 672, 160], "poisute": [672, 0, 768, 128], "hittakuri": [768, 0, 864, 128],
	"tako": [864, 0, 960, 144], "scrap": [960, 0, 1024, 64], "scrap2": [960, 64, 1024, 128],
	"diamond": [0, 160, 192, 352], "aux": [192, 160, 384, 224], "station": [192, 224, 448, 320],
	"hydrant": [448, 160, 544, 320], "dog": [544, 160, 656, 272], "koatsu": [656, 160, 784, 224],
	"noboruna": [784, 160, 880, 288], "kodomo": [880, 144, 976, 272], "lampTag": [656, 224, 784, 256],
}

# ad content (fictional advertisers); only the canvas drawing reads it
const ADS := [
	{"band": "一丁目", "bg": "#fbf5ee", "fg": "#c64a6e", "main": "さくら内科", "sub": "内科・小児科", "foot": "この先100m", "arrow": 1},
	{"band": "一丁目", "bg": "#2f6fb5", "fg": "#ffffff", "main": "水道修理", "sub": "桜ヶ丘水道サービス", "foot": "24時間受付"},
	{"band": "二丁目", "bg": "#f5f0dc", "fg": "#2f7a4f", "main": "はるかぜ不動産", "sub": "賃貸・売買・管理", "foot": "駅前 徒歩2分"},
	{"band": "二丁目", "bg": "#ef9a47", "fg": "#ffffff", "main": "学習塾さくらゼミ", "sub": "小・中・高 個別指導", "foot": "無料体験"},
	{"band": "三丁目", "bg": "#fff3cf", "fg": "#8a5a1f", "main": "山吹歯科医院", "sub": "予約優先", "foot": "50m", "arrow": -1},
	{"band": "一丁目", "bg": "#e6f1f6", "fg": "#2d5d86", "main": "白鳥クリーニング", "sub": "ワイシャツ一枚から", "foot": "駅前店"},
	{"band": "二丁目", "bg": "#6d5690", "fg": "#ffffff", "main": "桜川整骨院", "sub": "各種保険取扱", "foot": "この先右折", "arrow": 1},
	{"band": "三丁目", "bg": "#f3ece0", "fg": "#8c3b2e", "main": "御食事処はな", "sub": "定食・丼もの", "foot": "この先30m", "arrow": 1},
	{"band": "二丁目", "bg": "#3f8f5b", "fg": "#ffffff", "main": "はなまる薬局", "sub": "処方せん受付", "foot": "駐車場有"},
	{"band": "一丁目", "bg": "#fbe4ec", "fg": "#b3445f", "main": "美容室ひだまり", "sub": "カット・カラー", "foot": "予約制"},
	{"band": "四丁目", "bg": "#f7f3e8", "fg": "#2f64b5", "main": "ことり保育園", "sub": "園児募集中", "foot": "見学随時"},
	{"band": "三丁目", "bg": "#394a6b", "fg": "#f7e6b0", "main": "ピアノ教室", "sub": "ドルチェ音楽院", "foot": "体験レッスン"},
]


static func ad_rect(i: int) -> Array:
	var c := i % 6
	var r := i / 6
	return [480 + c * 88, r * 448, 568 + c * 88, 448 + r * 448]


static func tel_plate_rect(i: int) -> Array:
	var c := i % 5
	var r := i / 5
	return [128 + c * 64, 512 + r * 160, 192 + c * 64, 672 + r * 160]


static func plate_rect(i: int) -> Array:
	var c := i % 21
	var r := i / 21
	return [c * 48, 384 + r * 192, 48 + c * 48, 576 + r * 192]


## px rect -> uv rect [u0, v0, u1, v1] (canvas flipY).
static func uv_of(r: Array) -> Array:
	var aw := float(AW)
	return [r[0] / aw, 1.0 - r[3] / aw, r[2] / aw, 1.0 - r[1] / aw]


static func white_uv() -> Array:
	return [(RA.white[0] + 16) / float(AW), 1.0 - (RA.white[1] + 16) / float(AW)]


## makeAtlases(ctx, {plates, telPlates}): the two 1024 px atlases (drawn with their own rng streams,
## 'poles:atlasA' / 'poles:atlasB', which the stand-ins never draw from).
static func make_atlases(ctx, _plates: Array, _tel_plates: Array) -> Dictionary:
	var A = ctx.tex.draw(AW, AW, null, {"key": "poles:atlasA", "anisotropy": 8})
	var B = ctx.tex.draw(AW, AW, null, {"key": "poles:atlasB", "anisotropy": 8})
	return {"A": A, "B": B}
