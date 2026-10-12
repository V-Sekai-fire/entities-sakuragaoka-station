# props/shrinetex.js: the shrine's canvas textures. The port draws no canvases, so each is a sized
# stand-in under the original's key and repeat; the ema atlas table and the wish count are the
# original's.
extends RefCounted

const EMA := {"W": 1024, "H": 704, "cw": 204, "ch": 136, "cols": 5, "rows": 5}
## WISHES.length: the wish side of 24 plaques in the ema atlas.
const WISHES := 24

## [name, width, height, key, repeat or null], in the original's draw order
const TEXTURES := [
	["gravel", 512, 512, "props.shrine.gravel", [1, 1]],
	["stoneWall", 512, 256, "props.shrine.stonewall", [1, 1]],
	["stone", 256, 256, "props.shrine.stone", [1, 1]],
	["wood", 256, 256, "props.shrine.wood", [1, 1]],
	["rope", 128, 32, "props.shrine.rope", [6, 1]],
	["gaku", 128, 192, "props.shrine.gaku", null],
	["shagou", 128, 768, "props.shrine.shagou", null],
]


static func make_shrine_textures(ctx) -> Dictionary:
	var T = ctx.tex
	var out := {}
	for t in TEXTURES:
		var opts := {"key": t[3]}
		if t[4] != null:
			opts["repeat"] = t[4]
		out[t[0]] = T.draw(t[1], t[2], null, opts)
	# 奉納 donor names: 山田商店, 桜ヶ丘町内会, 中村家, 鈴木工務店
	out["kennoTex"] = []
	for i in 4:
		out.kennoTex.append(T.draw(64, 256, null, {"key": "props.shrine.kenno%d" % i}))
	# red nobori 正一位稲荷大明神: 桜ヶ丘町内会, 有志一同, 山本米店, 駅前商店会
	out["noboriTex"] = []
	for i in 4:
		out.noboriTex.append(T.draw(128, 512, null, {"key": "props.shrine.nobori%d" % i}))
	out["doors"] = T.draw(256, 256, null, {"key": "props.shrine.doors"})
	out["saisen"] = T.draw(256, 160, null, {"key": "props.shrine.saisen"})
	out["chozu"] = T.draw(256, 128, null, {"key": "props.shrine.chozu"})
	out["water"] = T.draw(256, 128, null, {"key": "props.shrine.water"})
	# 地蔵尊 plaque + 絵馬掛所 board
	out["jizoPlaque"] = T.draw(64, 192, null, {"key": "props.shrine.board.jizo"})
	out["emaSign"] = T.draw(256, 64, null, {"key": "props.shrine.board.ema"})
	out["notice"] = T.draw(1024, 640, null, {"key": "props.shrine.notice", "anisotropy": 8})
	out["noticeHead"] = T.draw(512, 64, null, {"key": "props.shrine.noticehead"})
	out["ema"] = T.draw(EMA.W, EMA.H, null, {"key": "props.shrine.ema", "anisotropy": 8})
	out["emaBack"] = [4 * EMA.cw, 4 * EMA.ch, EMA.cw, EMA.ch]
	out["wishes"] = WISHES
	return out
