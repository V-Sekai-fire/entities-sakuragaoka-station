# shopsB/wagashi.js: E2 和菓子処 桜月堂 (おうげつどう). Showa-era wooden confectioner with plaster upper
# floor, tiled pent roof, carved sign, indigo noren, lit showcase of sweets, enterable interior.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const WagashiInt = preload("res://addons/sakuragaoka_station/world/shopsB/wagashiInt.gd")

const TEXTS := ["和菓子処", "桜月堂", "おうげつどう", "創業昭和廿八年", "御菓子司", "和菓子", "春季限定", "桜もち", "さくらもち", "一個", "円", "三色だんご", "どら焼き", "柏もち", "豆大福", "草もち", "みたらし", "煉羊羹",
	"一八〇円", "一五〇円", "二〇〇円", "一六〇円", "一三〇円", "八〇〇円", "たい焼き", "焼きたて", "あつあつ", "つぶあん", "お花見だんご", "はじめました", "9:00〜18:00", "定休日 水曜日", "煎茶", "玄米茶", "ほうじ茶", "抹茶", "贈答用", "詰め合わせ",
	"ご予約承ります", "4月", "卯月", "日月火水木金土", "桜", "三個入", "540円", "480円", "180円", "150円", "お茶", "器"]


static func build_wagashi(ctx, K, lot) -> Dictionary:
	var C: Dictionary = K.C
	var TX: Dictionary = K.TX
	var F = K.F
	var S = K.space(lot)
	var g = S.g
	var rnd = ctx.rng("shopsB-wagashi")

	# ---------------------------------------------------------------- dimensions (lot local; +Z = street)
	var X0 := -3.5
	var X1 := 3.5
	var ZF := -1.2
	var ZB := -10.4
	var ZI := -5.3  # facade, back wall, interior partition
	var gr: Array = K.g_range(S, X0, X1, ZB, 0)
	var gmin: float = gr[0]
	var gmax: float = gr[1]
	var FL := gmax + 0.14  # shop floor (土間) level
	var H1 := 3.0
	var H2 := 2.45
	var Y1 := FL + H1
	var YE := Y1 + H2
	var PITCH := 0.4
	var OV := 0.7
	var zR := (ZF + ZB) / 2.0
	var yR := YE + 0.06 + PITCH * (ZF - zR)
	var WT := 0.14  # wall thickness

	# ---------------------------------------------------------------- materials
	var mPlaster = K.mt(C.plaster, TX.plaster, {"paint": 0.06})
	var mPlasterSide = K.mt("#e6dcc8", TX.plaster, {"paint": 0.07})
	var mBoard = K.mt("#7d5f49", TX.vboards, {"paint": 0.05})
	var mSiding = K.mt("#8c735f", TX.siding, {"paint": 0.06})
	var mFrame = K.mt(C.frame, TX.grain)
	var mPost = K.mt(C.frameDeep, TX.grain)
	var mBase = K.mt("#b3ada2", TX.concrete, {"paint": 0.08})
	var mRoof = K.mt("#5f6b7b", TX.kawara, {"paint": 0.05})
	var mRoofDark = K.m("#525b69")
	var mApron = K.mt(C.concrete, TX.concrete, {"paint": 0.06})
	var mGravel = K.mt("#b9b2a5", TX.gravel, {"paint": 0.05})
	var mGlass = K.glass({"opacity": 0.2})
	var mGlassShow = K.glass({"opacity": 0.12, "streaks": true})
	var mFrost = K.glass({"frost": true})
	var mGutter = K.m("#8d8a80", {"side": "double"})
	# interior (warm lit)
	var _iFloor = K.im("#c9c0b0", 0.22, {"map": TX.tile})
	var _iWall = K.im("#efe2c9", 0.3, {"map": TX.plaster})
	var _iCeil = K.im("#b8946e", 0.26, {"map": TX.vboards})
	var _iWood = K.im("#a57c58", 0.3, {"map": TX.grain})
	var iWoodDark = K.im("#6e5040", 0.28, {"map": TX.grain})
	var iRed = K.im("#b8423c", 0.26)
	var _iPaper = K.im("#f1ead9", 0.3)

	# ---------------------------------------------------------------- ground: apron, side gaps, back yard
	K.slab(S, -3.75, 3.75, ZF - 0.05, 0, 0.035, mApron, 4)
	K.slab(S, X1, 3.75, ZB, ZF - 0.05, 0.02, mGravel, 1.5)
	K.slab(S, -3.75, X0, ZB, ZF - 0.05, 0.02, mGravel, 1.5)
	K.slab(S, -3.75, 3.75, -14, ZB, 0.02, mGravel, 1.5)
	# stone step at the door (沓脱石)
	var stepTop: float = (FL + S.gl(0.3, ZF + 0.2) + 0.035) / 2.0
	K.tbox(g, 1.5, stepTop - gmin + 0.1, 0.36, K.mt("#a9a59c", TX.concrete), [0.3, (stepTop + gmin - 0.1) / 2.0, ZF + 0.18], 2)
	S.walk(-0.45, ZF, 1.05, ZF + 0.36, stepTop)

	# ---------------------------------------------------------------- foundation + floor
	K.tbox(g, X1 - X0, FL - 0.02 - (gmin - 0.2), ZF - ZB, mBase, [0, (FL - 0.02 + gmin - 0.2) / 2.0, (ZF + ZB) / 2.0], 3)
	K.tbox(g, X1 - X0 - 2 * WT, 0.03, ZF - ZI - WT, _iFloor, [0, FL - 0.015, (ZF - WT + ZI) / 2.0], 2.4)
	S.walk(X0 + WT, ZI, X1 - WT, ZF + 0.02, FL)

	# ---------------------------------------------------------------- ground-floor facade (wood) with openings
	var openA := {"a0": -3.3, "a1": -1.05, "y0": FL + 0.72, "y1": FL + 2.3}  # display window
	var openB := {"a0": -0.85, "a1": 1.35, "y0": FL, "y1": FL + 2.6}  # doors + transom
	var openC := {"a0": 1.6, "a1": 3.3, "y0": FL + 0.9, "y1": FL + 2.3}  # side window
	K.wall(g, mBoard, {"axis": "x", "a0": X0, "a1": X1, "y0": FL - 0.02, "y1": Y1, "c": ZF - WT / 2.0, "t": WT, "holes": [openA, openB, openC], "tile": 1.5})
	# posts (柱) and head beam (差鴨居)
	for x in [X0 + 0.08, -0.95, 1.475, X1 - 0.08]:
		K.box(g, 0.16, H1 + 0.02, 0.2, mPost, [x, FL + H1 / 2.0, ZF - 0.07])
	K.tbox(g, X1 - X0 + 0.02, 0.26, 0.2, mPost, [0, FL + 2.76, ZF - 0.06], 1)
	# sill + kick board under window A
	K.box(g, openA.a1 - openA.a0 + 0.12, 0.05, 0.18, mFrame, [(openA.a0 + openA.a1) / 2.0, openA.y0 - 0.02, ZF + 0.02])
	K.box(g, openC.a1 - openC.a0 + 0.12, 0.05, 0.16, mFrame, [(openC.a0 + openC.a1) / 2.0, openC.y0 - 0.02, ZF + 0.02])

	# display window A: frame, 3 panes, glass
	if true:
		var w: float = openA.a1 - openA.a0
		var h: float = openA.y1 - openA.y0
		var cx: float = (openA.a0 + openA.a1) / 2.0
		var cy: float = (openA.y0 + openA.y1) / 2.0
		for x in [openA.a0 + 0.03, openA.a1 - 0.03, cx - w / 6.0, cx + w / 6.0]:
			K.box(g, 0.05, h, 0.08, mFrame, [x, cy, ZF - 0.05])
		K.box(g, w, 0.05, 0.08, mFrame, [cx, openA.y1 - 0.025, ZF - 0.05])
		K.box(g, w, 0.05, 0.08, mFrame, [cx, openA.y0 + 0.025, ZF - 0.05])
		K.box(g, w, 0.03, 0.06, mFrame, [cx, openA.y0 + h * 0.72, ZF - 0.05])
		var gp = K.box(g, w - 0.06, h - 0.06, 0.006, mGlassShow, [cx, cy, ZF - 0.05])
		gp.cast_shadow = false
		ctx.no_outline(gp)
	# side window C: two sliding sashes with a lattice + bamboo blind (すだれ)
	if true:
		var w: float = openC.a1 - openC.a0
		var h: float = openC.y1 - openC.y0
		var cx: float = (openC.a0 + openC.a1) / 2.0
		K.window(g, {"x": cx, "y0": openC.y0, "z": ZF - 0.06, "w": w, "h": h, "frame": mFrame, "glass": mGlass, "sill": false, "panes": 2, "lattice": 0.085})
		var sh := h * 0.62
		K.tbox(g, w + 0.1, sh, 0.012, K.mt("#d9c08a", TX.bamboo, {"paint": 0.03}), [cx, openC.y1 - sh / 2.0 + 0.02, ZF + 0.05], 0.5)
		K.cyl_x(g, 0.02, w + 0.14, K.m("#b8955e"), [cx, openC.y1 + 0.04, ZF + 0.05], 8)
		K.box(g, w + 0.1, 0.03, 0.02, K.m("#8a6a40"), [cx, openC.y1 - sh + 0.02, ZF + 0.05])
		for x in [openC.a0 + 0.25, openC.a1 - 0.25]:
			var q = S.w2(x, ZF + 0.062)
			ctx.wires.add([[q.x, S.f.y + openC.y1 + 0.04, q.z], [q.x, S.f.y + openC.y1 - sh + 0.02, q.z]], {"width": 0.008, "color": "#7a5d3a"})
	# doors B: sliding glass panels (left fixed in outer track, right one slides open when you approach)
	var doorH := 2.05
	K.box(g, openB.a1 - openB.a0, 0.04, 0.16, mFrame, [(openB.a0 + openB.a1) / 2.0, FL + 0.005, ZF - 0.06])  # 敷居
	K.box(g, openB.a1 - openB.a0, 0.08, 0.16, mFrame, [(openB.a0 + openB.a1) / 2.0, FL + doorH + 0.04, ZF - 0.06])  # 鴨居
	var pw: float = (openB.a1 - openB.a0) / 2.0 + 0.04
	var doorOpts := {"w": pw, "h": doorH, "d": 0.04, "frame": mFrame, "glass": mGlass, "stile": 0.05, "top": 0.06, "bottom": 0.08, "bars": [0.5], "kick": {"h": 0.34, "mat": K.mt("#7d5f49", TX.vboards), "tile": 1.5}}
	var leftDoor = K.panel(g, doorOpts)
	leftDoor.position = Vector3(openB.a0 + pw / 2.0, FL + 0.02, ZF - 0.03)
	var rightDoor = K.panel(S.d, doorOpts)
	rightDoor.position = Vector3(openB.a1 - pw / 2.0, FL + 0.02, ZF - 0.085)
	K.auto_slide(S, rightDoor, {"cx": 0.8, "cz": ZF, "r": 2.4, "dx": -(pw - 0.1), "rest": 1})  # open during business hours
	S.box(openB.a0, ZF - 0.12, openB.a0 + pw, ZF, FL, FL + 2.1)
	# transom (欄間): frosted glass + wooden lattice
	if true:
		var y0 := FL + doorH + 0.08
		var h: float = openB.y1 - y0
		var cx: float = (openB.a0 + openB.a1) / 2.0
		var w: float = openB.a1 - openB.a0
		var gp = K.box(g, w, h, 0.006, mFrost, [cx, y0 + h / 2.0, ZF - 0.08])
		gp.cast_shadow = false
		ctx.no_outline(gp)
		for i in 23:
			K.box(g, 0.022, h, 0.03, mFrame, [openB.a0 + i * w / 22.0, y0 + h / 2.0, ZF - 0.05])
		K.box(g, w, 0.03, 0.03, mFrame, [cx, y0 + h / 2.0, ZF - 0.05])

	# ---------------------------------------------------------------- upper floor facade (plaster between timbers)
	var win2 := [{"a0": -3.05, "a1": -1.95, "y0": Y1 + 0.75, "y1": Y1 + 1.85}, {"a0": 1.95, "a1": 3.05, "y0": Y1 + 0.75, "y1": Y1 + 1.85}]
	K.wall(g, mPlaster, {"axis": "x", "a0": X0, "a1": X1, "y0": Y1, "y1": YE, "c": ZF - WT / 2.0, "t": WT, "holes": win2, "tile": 2.5})
	for x in [X0 + 0.07, X1 - 0.07]:
		K.box(g, 0.15, H2, 0.18, mPost, [x, Y1 + H2 / 2.0, ZF - 0.06])
	K.tbox(g, X1 - X0 + 0.04, 0.2, 0.2, mPost, [0, YE - 0.1, ZF - 0.05], 1)  # 軒桁
	for o in win2:
		var w: float = o.a1 - o.a0
		var h: float = o.y1 - o.y0
		var cx: float = (o.a0 + o.a1) / 2.0
		K.window(g, {"x": cx, "y0": o.y0, "z": ZF - 0.07, "w": w, "h": h, "frame": mFrame, "glass": mGlass, "panes": 2, "lattice": 0.075, "behind": K.shoji(), "behindD": 0.1})
		K.box(g, w + 0.2, 0.05, 0.12, mFrame, [cx, o.y1 + 0.1, ZF + 0.02])  # small drip board
	# carved signboard (彫り看板) with a small tiled cap
	if true:
		var sw := 3.3
		var sh := 0.84
		var sy := Y1 + 1.3
		K.box(g, sw + 0.12, sh + 0.12, 0.08, mPost, [0, sy, ZF + 0.05])
		K.plane(g, sw, sh, K.toon_memo("#ffffff", {"map": sign_tex(K), "paint": 0.03}), [0, sy, ZF + 0.092])
		K.tbox(g, sw + 0.4, 0.06, 0.28, mRoof, [0, sy + sh / 2.0 + 0.12, ZF + 0.08], 2.1, [0.18, 0, 0])
		K.box(g, sw + 0.42, 0.05, 0.05, mRoofDark, [0, sy + sh / 2.0 + 0.1, ZF + 0.22])
		for x in [-1.2, 1.2]:
			K.box(g, 0.07, 0.07, 0.14, mPost, [x, sy + sh / 2.0 + 0.03, ZF + 0.02])
	# projecting vertical lightbox (袖看板) at the north end
	K.sode_sign(g, {"x": X0 + 0.32, "y": Y1 + 0.25, "z": ZF, "w": 0.5, "h": 1.75, "tex": sode_tex(K), "frame": "#e9e2d4"})

	# ---------------------------------------------------------------- pent roof (庇) over the shop front
	K.pent(g, {"x0": X0 - 0.06, "x1": X1 + 0.06, "zWall": ZF, "depth": 1.0, "drop": 0.32, "y": Y1 + 0.12, "mat": mRoof, "tile": 2.1, "fascia": mFrame, "edgeTiles": mRoofDark, "brackets": [X0 + 0.08, -0.95, 1.475, X1 - 0.08], "bracketMat": mPost})
	K.box(g, X1 - X0 + 0.14, 0.12, 0.12, mRoofDark, [0, Y1 + 0.15, ZF + 0.04])  # flashing where it meets the wall
	K.gutter_x(g, X0 - 0.02, X1 + 0.02, Y1 + 0.12 - 0.32 - 0.06, ZF + 1.05, mGutter)
	# small lightbox under the pent roof
	if true:
		K.rbox_r(g, 1.05, 0.3, 0.1, 0.02, K.m("#e8e0d0"), [-2.18, FL + 2.76, ZF + 0.1])
		K.plane(g, 0.98, 0.24, K.memo("emi", "#ffffff", {"map": lightbox_tex(K)}, 1.02), [-2.18, FL + 2.76, ZF + 0.152])
	# noren (暖簾) at the door
	K.noren(S, {"x": (openB.a0 + openB.a1) / 2.0, "y": FL + 2.55, "z": ZF + 0.1, "w": 2.05, "h": 0.92, "n": 3, "tex": noren_tex(K, 2.05, 3), "rodColor": "#5a4032"})
	for x in [openB.a0 - 0.05, openB.a1 + 0.05]:
		K.box(g, 0.04, 0.12, 0.12, mFrame, [x, FL + 2.57, ZF + 0.05])
	# hand-written 営業中 plate + stickers on the fixed door
	K.eigyo_plate(g, leftDoor.position.x, FL + 1.52, ZF + 0.0, 0, "営業中", "")
	var wp := []
	var lx: float = leftDoor.position.x
	var wpts := [S.w2(lx - 0.1, ZF - 0.003), S.w2(lx, ZF - 0.003), S.w2(lx + 0.1, ZF - 0.003)]
	for i in wpts.size():
		wp.append([wpts[i].x, S.f.y + FL + 1.6 + (0.12 if i == 1 else 0.0), wpts[i].z])
	ctx.wires.add(wp, {"width": 0.006, "color": "#5a4032"})
	K.decal(g, K.hours_sticker(["9:00〜18:00", "定休日 水曜日"], "#d9718f"), 0.2, 0.15, [lx + 0.22, FL + 0.95, ZF - 0.004])
	K.decal(rightDoor, K.cashless(), 0.34, 0.106, [0.0, 0.95, 0.024])
	K.decal(g, spring_poster_tex(K, "glass"), 0.36, 0.5, [-1.62, FL + 1.12, ZF - 0.045])

	# ---------------------------------------------------------------- side & back walls
	for x in [X0 + WT / 2.0, X1 - WT / 2.0]:
		K.wall(g, mSiding, {"axis": "z", "a0": ZB, "a1": ZF - WT, "y0": FL - 0.02, "y1": FL + 1.3, "c": x, "t": WT, "tile": 1.8})
		K.wall(g, mPlasterSide, {"axis": "z", "a0": ZB, "a1": ZF - WT, "y0": FL + 1.3, "y1": YE, "c": x, "t": WT, "tile": 2.5})
		K.box(g, WT + 0.02, 0.05, ZF - ZB - WT, mFrame, [x, FL + 1.3, (ZF - WT + ZB) / 2.0])
		K.gable_end(g, mPlasterSide, x, ZB, ZF, YE - 0.001, zR, yR - 0.08, WT, 2.5)
		S.box(x - WT / 2.0, ZB, x + WT / 2.0, ZF, FL - 0.1, YE)
		var sx: float = x + T.sign(x) * (WT / 2.0 + 0.015)
		var z := ZB + 0.08
		while z <= ZF - WT:
			K.box(g, 0.04, YE - FL - 1.3, 0.12, mPost, [sx, (YE + FL + 1.3) / 2.0, z])
			z += (ZF - WT - ZB - 0.08) / 5.0
		K.box(g, 0.05, 0.14, ZF - ZB, mPost, [sx, Y1 + 0.05, (ZF + ZB) / 2.0])
		K.box(g, 0.05, 0.16, ZF - ZB, mPost, [sx, YE - 0.08, (ZF + ZB) / 2.0])
	K.wall(g, mPlasterSide, {"axis": "x", "a0": X0 + WT, "a1": X1 - WT, "y0": FL - 0.02, "y1": YE, "c": ZB + WT / 2.0, "t": WT, "holes": [{"a0": 1.6, "a1": 2.5, "y0": FL, "y1": FL + 1.9}, {"a0": -2.6, "a1": -1.4, "y0": FL + 1.0, "y1": FL + 1.8}, {"a0": -1.2, "a1": 0.2, "y0": Y1 + 0.7, "y1": Y1 + 1.7}], "tile": 2.5})
	K.box(g, 0.9, 1.9, 0.05, K.mt("#7d6250", TX.vboards), [2.05, FL + 0.95, ZB - 0.02])  # back door
	K.window(g, {"x": -2.0, "y0": FL + 1.0, "z": ZB - 0.03, "w": 1.2, "h": 0.8, "frame": K.m(C.aluDark), "glass": mFrost, "panes": 2, "rotY": PI})
	K.window(g, {"x": -0.5, "y0": Y1 + 0.7, "z": ZB - 0.03, "w": 1.4, "h": 1.0, "frame": K.m(C.aluDark), "glass": mGlass, "panes": 2, "rotY": PI, "behind": K.curtain("#e9d9c9")})
	S.box(X0, ZB, X1, ZI, FL - 0.1, YE)  # back rooms are solid
	S.box(X0, ZF - WT, openB.a0, ZF, FL - 0.1, Y1)  # facade left of the door
	S.box(openB.a1, ZF - WT, X1, ZF, FL - 0.1, Y1)  # facade right of the door

	# ---------------------------------------------------------------- main roof (平入り, kawara)
	K.gable_x(g, {"x0": X0 - 0.22, "x1": X1 + 0.22, "zf": ZF + OV, "zb": ZB - OV, "yE": YE + 0.06 - PITCH * OV, "yR": yR, "zR": zR, "t": 0.12, "mat": mRoof, "tile": 2.1, "fascia": mFrame, "edgeTiles": mRoofDark})
	K.ridge_x(g, X0 - 0.22, X1 + 0.22, yR + 0.02, zR, mRoofDark, K.m("#4a525e"))
	for x in [X0 - 0.2, X1 + 0.2]:
		for side in [1, -1]:  # barge boards (破風)
			var ze := ZF + OV if side > 0 else ZB - OV
			var run := absf(ze - zR)
			var rise := yR - (YE + 0.06 - PITCH * OV)
			var length := Vector2(run, rise).length()
			var ang := atan2(rise, run)
			K.box(g, 0.05, 0.2, length, mFrame, [x, (yR + YE + 0.06 - PITCH * OV) / 2.0 - 0.02, (ze + zR) / 2.0], [side * ang, 0, 0])
	K.gutter_x(g, X0 - 0.2, X1 + 0.2, YE + 0.06 - PITCH * OV - 0.1, ZF + OV + 0.05, mGutter)
	K.downpipe(g, X0 - 0.12, ZF + 0.25, YE - 0.1, S.gl(X0 - 0.12, ZF + 0.25) + 0.02, mGutter, 0.12)
	K.box(g, 0.07, 0.07, OV - 0.2, mGutter, [X0 - 0.12, YE - 0.2, ZF + 0.55])

	# ---------------------------------------------------------------- side-gap clutter (AC unit, meters, pipes)
	K.ac_unit(g, X1 + 0.02, S.gl(X1, -7) + 0.02, -7.0, PI / 2.0)
	if true:
		var wallG := T.Group.new()
		wallG.position = Vector3(X1, 0, 0)
		wallG.rotation.y = PI / 2.0
		g.add(wallG)
		K.meter(wallG, 3.2, FL + 1.55, 0)  # on the +x side wall, local x along -z
		K.gas_meter(wallG, 4.4, FL + 0.95, 0)
		K.pipe_run(g, [[X1 + 0.05, S.gl(X1, -6.2) + 0.05, -6.2], [X1 + 0.05, FL + 0.6, -6.2], [X1 + 0.05, FL + 0.6, -5.4]], 0.018, K.m("#c9c2b0"))
	S.box(X1, -7.4, 3.75, -6.6, 0, 0.7)

	# ---------------------------------------------------------------- interior
	WagashiInt.build_wagashi_interior(ctx, K, S, {"FL": FL, "ZF": ZF, "ZI": ZI, "WT": WT, "X0": X0, "X1": X1})
	# display window tiers (ひな壇) inside window A
	var dz0 := ZF - WT - 0.02
	for t in [[0.0, 0.62, 0.7], [0.22, 0.42, 0.95], [0.4, 0.26, 1.18]]:
		var off: float = t[0]
		var dep: float = t[1]
		var y: float = t[2]
		K.box(g, openA.a1 - openA.a0 + 0.1, 0.04, dep, iRed, [(openA.a0 + openA.a1) / 2.0, FL + y, dz0 - off - dep / 2.0])
		K.box(g, openA.a1 - openA.a0 + 0.1, y - 0.02, 0.02, iWoodDark, [(openA.a0 + openA.a1) / 2.0, FL + y / 2.0, dz0 - off - dep])
	K.box(g, openA.a1 - openA.a0 + 0.1, 0.7, 0.62, iWoodDark, [(openA.a0 + openA.a1) / 2.0, FL + 0.34, dz0 - 0.31])
	S.box(X0, dz0 - 0.7, openA.a1 + 0.05, ZF, FL, FL + 1.3)
	# items on the tiers
	gift_box(g, K, -2.9, FL + 0.72, dz0 - 0.2, 0.36, 0.1, 0.26, 20)
	gift_box(g, K, -2.9, FL + 0.82, dz0 - 0.2, 0.32, 0.08, 0.22, 21)
	gift_box(g, K, -1.45, FL + 0.72, dz0 - 0.22, 0.34, 0.12, 0.26, 22)
	platter(g, K, "sakura", -2.2, FL + 0.72, dz0 - 0.22, rnd)
	platter(g, K, "dango", -2.6, FL + 0.97, dz0 - 0.4, rnd)
	platter(g, K, "kashiwa", -1.75, FL + 0.97, dz0 - 0.4, rnd)
	gift_box(g, K, -2.25, FL + 1.2, dz0 - 0.55, 0.4, 0.14, 0.2, 23)
	sakura_spray(g, K, -1.3, FL + 1.2, dz0 - 0.55, 0.75, rnd)
	K.plane(g, 0.2, 0.1, K.im("#ffffff", 0.3, {"map": K.card(["桜もち", "三個入 540円"], {"w": 192, "h": 96, "font": F.serif, "fg": "#4a2e2a", "fg2": "#a33a36"})}), [-2.2, FL + 0.8, dz0 - 0.02], 0, -0.2)

	# ---------------------------------------------------------------- outside furniture
	var ag := func(x, z): return S.gl(x, z) + 0.035
	# red bench (縁台) with red felt (毛氈) + tea & dango
	if true:
		var bx := 2.45
		var bz := -0.78
		var length := 1.5
		var dep := 0.5
		var sh := 0.42
		var y0: float = ag.call(bx, bz)
		var bg := T.Group.new()
		bg.position = Vector3(bx, y0, bz)
		g.add(bg)
		var wood = K.mt("#9a6a48", TX.grain)
		var felt = K.m("#cf5048", {"paint": 0.07})
		for sx in [-length / 2.0 + 0.1, length / 2.0 - 0.1]:
			for sz in [-dep / 2.0 + 0.07, dep / 2.0 - 0.07]:
				K.box(bg, 0.06, sh - 0.05, 0.06, wood, [sx, (sh - 0.05) / 2.0, sz])
		for sx in [-length / 2.0 + 0.1, length / 2.0 - 0.1]:
			K.box(bg, 0.05, 0.05, dep - 0.1, wood, [sx, 0.1, 0])
		K.tbox(bg, length, 0.04, dep, wood, [0, sh - 0.03, 0], 1)
		K.box(bg, length + 0.05, 0.012, dep + 0.05, felt, [0, sh - 0.004, 0])
		K.box(bg, length + 0.05, 0.13, 0.012, felt, [0, sh - 0.07, dep / 2.0 + 0.025])
		K.box(bg, length + 0.05, 0.13, 0.012, felt, [0, sh - 0.07, -dep / 2.0 - 0.025])
		# tray with tea + dango
		K.box(bg, 0.3, 0.02, 0.2, K.m("#7a4a38"), [-0.3, sh + 0.012, 0.02])
		K.cyl(bg, 0.032, 0.07, K.m("#8aa39a"), [-0.38, sh + 0.057, 0.03], 10, null, 0.028)
		K.cyl(bg, 0.027, 0.004, K.m("#9fb46a"), [-0.38, sh + 0.09, 0.03], 10)
		K.cyl(bg, 0.07, 0.012, K.m("#ece6d8"), [-0.24, sh + 0.028, 0.02], 14)
		dango(bg, K, -0.24, sh + 0.05, 0.02, 0.4, false)
		dango(bg, K, -0.23, sh + 0.05, 0.05, 0.25, false)
		S.box(bx - length / 2.0 - 0.03, bz - dep / 2.0 - 0.03, bx + length / 2.0 + 0.03, bz + dep / 2.0 + 0.03, y0, y0 + sh)
	# wooden display stand (陳列台) in front of the show window
	if true:
		var x := -2.3
		var z := -0.62
		var w := 1.5
		var dep := 0.55
		var y0: float = ag.call(x, z)
		var sg := T.Group.new()
		sg.position = Vector3(x, y0, z)
		g.add(sg)
		var wood = K.mt("#b08560", TX.grain)
		var dark = K.mt("#7a5a42", TX.grain)
		for sx in [-w / 2.0 + 0.05, w / 2.0 - 0.05]:
			for sz in [-dep / 2.0 + 0.05, dep / 2.0 - 0.05]:
				K.box(sg, 0.05, 0.72, 0.05, dark, [sx, 0.36, sz])
		K.tbox(sg, w, 0.04, dep, wood, [0, 0.72, 0], 1)
		K.tbox(sg, w, 0.04, 0.26, wood, [0, 0.92, -0.14], 1)
		for sx in [-w / 2.0 + 0.05, w / 2.0 - 0.05]:
			K.box(sg, 0.04, 0.2, 0.26, dark, [sx, 0.82, -0.14])
		K.box(sg, w - 0.1, 0.04, dep - 0.1, dark, [0, 0.16, 0])
		# packaged sakura-mochi in clear packs + gift boxes + price cards
		for i in 4:
			var px := -0.52 + i * 0.3
			K.box(sg, 0.22, 0.01, 0.15, K.m("#6a8a58"), [px, 0.745, 0.12])
			for j in 3:
				sakura_mochi(sg, K, px - 0.06 + j * 0.06, 0.755, 0.12, 0.2 * j)
			var lid = K.box(sg, 0.23, 0.05, 0.16, K.glass({"opacity": 0.15, "streaks": false}), [px, 0.765, 0.12])
			lid.cast_shadow = false
			ctx.no_outline(lid)
			K.box(sg, 0.08, 0.05, 0.002, K.m("#f3d7df"), [px + 0.07, 0.77, 0.201])
		for i in 3:
			gift_box(sg, K, -0.45 + i * 0.45, 0.94, -0.14, 0.34, 0.1, 0.2, 30 + i)
		for i in 3:
			K.box(sg, 0.14, 0.004, 0.14, K.m("#f7f3ea"), [-0.55 + i * 0.52, 0.745, -0.07])
		K.plane(sg, 0.26, 0.14, K.mt("#ffffff", K.card(["桜もち", "三個入 540円"], {"w": 192, "h": 104, "font": F.serif, "fg": "#4a2e2a", "fg2": "#a33a36", "bg": "#fbeef2", "border": "#e38aa6"})), [0.52, 1.03, 0.0], 0, -0.3)
		K.plane(sg, 0.26, 0.14, K.mt("#ffffff", K.card(["柏もち", "一個 160円"], {"w": 192, "h": 104, "font": F.serif, "fg": "#35502e", "fg2": "#35502e", "bg": "#eef2e4", "border": "#7fa36b"})), [-0.52, 1.03, 0.0], 0, -0.3)
		S.box(x - w / 2.0, z - dep / 2.0, x + w / 2.0, z + dep / 2.0, y0, y0 + 1.0)
	# maneki-neko by the door on a small stool
	if true:
		var x := -1.18
		var z := -0.98
		var y0: float = ag.call(x, z)
		var st = K.mt("#8a6446", TX.grain)
		K.box(g, 0.3, 0.04, 0.3, st, [x, y0 + 0.4, z])
		for sx in [-0.12, 0.12]:
			for sz in [-0.12, 0.12]:
				K.box(g, 0.035, 0.38, 0.035, st, [x + sx, y0 + 0.19, z + sz])
		K.box(g, 0.25, 0.03, 0.25, K.m("#c9463e"), [x, y0 + 0.435, z])
		maneki_neko(g, K, x, y0 + 0.45, z, 0.35, 0.3)
		S.box(x - 0.16, z - 0.16, x + 0.16, z + 0.16, y0, y0 + 0.8)
	# pink standing poster 春季限定 桜もち
	if true:
		var x := -3.45
		var z := -0.32
		var y0: float = ag.call(x, z)
		var rot := 0.55
		var pg := T.Group.new()
		pg.position = Vector3(x, y0, z)
		pg.rotation.y = rot
		g.add(pg)
		var fm = K.m("#e8e1d4")
		for sx in [-0.23, 0.23]:
			K.box(pg, 0.03, 1.2, 0.03, fm, [sx, 0.6, 0])
		K.box(pg, 0.5, 0.03, 0.03, fm, [0, 1.19, 0])
		K.box(pg, 0.44, 0.04, 0.3, K.m("#8d949b"), [0, 0.02, 0])
		K.box(pg, 0.44, 0.64, 0.015, K.m("#f3e4e8"), [0, 0.84, -0.005])
		K.plane(pg, 0.42, 0.62, K.toon_memo("#ffffff", {"map": spring_poster_tex(K, "stand")}), [0, 0.84, 0.004])
		S.box(x - 0.25, z - 0.2, x + 0.25, z + 0.2, y0, y0 + 1.2)
	# taiyaki nobori (animated) at the south corner
	K.nobori(S, {"x": 3.52, "z": -0.2, "rot": -0.35, "tex": taiyaki_nobori_tex(K), "w": 0.45, "h": 1.65, "poleH": 2.55, "flip": true})
	# potted plants + wooden bucket (手桶) with ladle by the door
	K.plant(g, 1.55, ag.call(1.55, -0.95), -0.95, {"r": 0.17, "h": 0.28, "pot": "#6f7f8f", "leaf": "#5f8c5c", "leaf2": "#78a466", "flowers": "#f0a9bf", "n": 6})
	if true:
		K.cyl(g, 0.14, 0.22, K.mt("#b89468", TX.vboards), [-3.2, ag.call(-3.2, -1.05) + 0.11, -1.05], 14, null, 0.12)
		K.cyl(g, 0.145, 0.025, K.m("#6d747c"), [-3.2, ag.call(-3.2, -1.05) + 0.17, -1.05], 14)
		K.cyl(g, 0.008, 0.36, K.m("#a88a60"), [-3.14, ag.call(-3.2, -1.05) + 0.3, -1.05], 6, [0, 0, -0.5])
		K.cyl(g, 0.035, 0.04, K.m("#a88a60"), [-3.07, ag.call(-3.2, -1.05) + 0.44, -1.05], 8)

	return {"FL": FL, "S": S}


# ============================================================================ sweets & small goods

static func sakura_mochi(p, K, x: float, y: float, z: float, rot: float = 0.0, interior := false) -> void:
	var pink = K.im("#f1a9bd", 0.3) if interior else K.m("#f1a9bd")
	var leaf = K.im("#8c8f4c", 0.25) if interior else K.m("#8c8f4c")
	K.sph(p, 0.026, pink, [x, y + 0.017, z], 8, [1.3, 0.7, 0.9])
	var l = K.sph(p, 0.028, leaf, [x + 0.004, y + 0.012, z - 0.006], 8, [1.35, 0.55, 1.0])
	l.rotation.y = rot


static func dango(p, K, x: float, y: float, z: float, rot: float = 0.0, interior := true) -> void:
	var g := T.Group.new()
	g.position = Vector3(x, y, z)
	g.rotation.y = rot
	p.add(g)
	var f := func(c): return K.im(c, 0.3) if interior else K.m(c)
	K.cyl_x(g, 0.003, 0.17, f.call("#d9c08a"), [0, 0.012, 0], 5)
	var cs := ["#f2a7bb", "#f3efe4", "#9cc27a"]
	for i in cs.size():
		K.sph(g, 0.017, f.call(cs[i]), [-0.035 + i * 0.034, 0.014, 0], 8)


static func sweets_tray(p, K, kind: String, x: float, y: float, z: float, w: float, d: float, rnd, interior: bool) -> void:
	var f := func(c): return K.im(c, 0.3) if interior else K.m(c)
	var cols := 2 if kind == "dango" else 3
	var rows := 4 if kind == "dango" else 3
	for i in cols:
		for j in rows:
			var px: float = x - w / 2.0 + w * (i + 0.5) / cols + rnd.range(-0.008, 0.008)
			var pz: float = z - d / 2.0 + d * (j + 0.5) / rows
			if kind == "sakura":
				sakura_mochi(p, K, px, y, pz, rnd.f() * 0.5, interior)
			elif kind == "dango":
				dango(p, K, px, y, pz, 0.08 * (rnd.f() - 0.5), interior)
			elif kind == "dora":
				K.sph(p, 0.038, f.call("#b8793f"), [px, y + 0.018, pz], 10, [1, 0.3, 1])
				K.sph(p, 0.037, f.call("#c98a4e"), [px, y + 0.034, pz], 10, [1, 0.26, 1])
			elif kind == "kashiwa":
				K.sph(p, 0.03, f.call("#6f8a4a"), [px, y + 0.012, pz], 8, [1.35, 0.5, 1.0])
				K.sph(p, 0.024, f.call("#f1ede4"), [px + 0.005, y + 0.02, pz + 0.004], 8, [1.2, 0.7, 0.85])
			elif kind == "daifuku":
				K.sph(p, 0.028, f.call("#f4f0e8"), [px, y + 0.018, pz], 10, [1, 0.72, 1])
				K.sph(p, 0.005, f.call("#5a4050"), [px + 0.01, y + 0.03, pz + 0.012], 5)
			elif kind == "kusa":
				K.sph(p, 0.027, f.call("#8fae6a"), [px, y + 0.017, pz], 10, [1.1, 0.7, 1])


static func platter(p, K, kind: String, x: float, y: float, z: float, rnd) -> void:
	K.cyl(p, 0.12, 0.018, K.im("#e9e4d8", 0.3), [x, y + 0.009, z], 16)
	K.cyl(p, 0.121, 0.006, K.im("#6b86a8", 0.3), [x, y + 0.019, z], 16)
	sweets_tray(p, K, kind, x, y + 0.02, z, 0.16, 0.12, rnd, true)


const WRAP := [["#f3c9d4", "#e28ea8"], ["#dfe8cf", "#7fa36b"], ["#efe2c8", "#c08a54"], ["#d7dfea", "#6b86a8"], ["#f5e6c8", "#d9a441"], ["#ecd3dd", "#b56a86"]]


static func wrap_tex(K, i: int):
	return K.tex.draw(128, 128, null, {"key": "sb-wrap%d" % (i % WRAP.size())})


static func gift_box(p, K, x: float, y: float, z: float, w: float, h: float, d: float, i: int, rot_y: float = 0.0):
	var m = K.im("#ffffff", 0.28, {"map": wrap_tex(K, i)})
	var b = K.box(p, w, h, d, m, [x, y + h / 2.0, z])
	b.rotation.y = rot_y
	var r = K.box(p, w + 0.004, 0.012, d * 0.2, K.im("#c9463e", 0.25), [x, y + h + 0.001, z])
	r.rotation.y = rot_y
	return b


static func sakura_spray(p, K, x: float, y: float, z: float, h: float, rnd) -> void:
	K.cyl(p, 0.04, 0.16, K.im("#6b86a8", 0.3), [x, y + 0.08, z], 12, null, 0.05)
	var bark = K.im("#6a5448", 0.2)
	var pink = K.im("#f6c9d6", 0.35)
	var pink2 = K.im("#f0b0c4", 0.3)
	var br := [[0, 0, 0.1, h, 0.05], [0.02, h * 0.45, 0.2, h * 0.85, -0.3], [-0.02, h * 0.3, -0.18, h * 0.7, 0.2]]
	for b in br:
		var x0: float = b[0]
		var y0: float = b[1]
		var x1: float = b[2]
		var y1: float = b[3]
		var length := Vector2(x1 - x0, y1 - y0).length()
		var ang := atan2(x1 - x0, y1 - y0)
		K.cyl(p, 0.006, length, bark, [x + (x0 + x1) / 2.0, y + 0.16 + (y0 + y1) / 2.0, z], 5, [0, 0, -ang])
		for k in 12:
			var t := 0.25 + 0.75 * k / 11.0
			var r: float = 0.012 + rnd.f() * 0.008
			var px: float = x + x0 + (x1 - x0) * t + rnd.range(-0.035, 0.035)
			var py: float = y + 0.16 + y0 + (y1 - y0) * t + rnd.range(-0.025, 0.025)
			var pz: float = z + rnd.range(-0.035, 0.035)
			K.sph(p, r, pink if k % 2 else pink2, [px, py, pz], 6)


## Maneki-neko (招き猫): calico, right paw raised, gold koban.
static func maneki_neko(p, K, x: float, y: float, z: float, s: float = 0.3, rot_y: float = 0.0) -> void:
	var g := T.Group.new()
	g.position = Vector3(x, y, z)
	g.rotation.y = rot_y
	g.scale = Vector3.ONE * (s / 0.3)
	p.add(g)
	var white = K.m("#f3efe6")
	var red = K.m("#c9463e")
	var gold = K.m("#e3bd52")
	var ink = K.m("#3a3346")
	var orange = K.m("#e2a04e")
	var pinkM = K.m("#f0a6b6")
	K.sph(g, 0.1, white, [0, 0.09, 0], 14, [1, 0.95, 0.85])  # body
	K.sph(g, 0.085, white, [0, 0.23, 0.01], 14, [1.1, 0.95, 0.95])  # head
	for sx in [-1, 1]:
		var e = K.cyl(g, 0.0, 0.05, white, [sx * 0.055, 0.31, 0.0], 6, [0, 0, sx * -0.3], 0.03)
		e.scale = Vector3(1, 0.06, 1)
	for sx in [-1, 1]:
		K.sph(g, 0.012, pinkM, [sx * 0.056, 0.305, 0.018], 6)
	K.sph(g, 0.03, orange, [0.045, 0.285, 0.03], 8, [1.2, 0.6, 1])  # calico patch
	K.sph(g, 0.03, ink, [-0.07, 0.12, 0.04], 8, [0.9, 1, 0.6])
	for sx in [-1, 1]:
		K.box(g, 0.026, 0.008, 0.01, ink, [sx * 0.033, 0.235, 0.088], [0, 0, sx * 0.25])  # happy closed eyes
	K.sph(g, 0.008, pinkM, [0, 0.215, 0.093], 6)
	for sx in [-1, 1]:
		for k in 2:
			K.box(g, 0.035, 0.003, 0.003, ink, [sx * 0.07, 0.205 - k * 0.012, 0.085], [0, 0, sx * (0.12 - k * 0.2)])
	K.cyl(g, 0.078, 0.018, red, [0, 0.16, 0.012], 14)  # collar
	K.sph(g, 0.018, gold, [0, 0.145, 0.08], 8)  # bell
	K.sph(g, 0.03, white, [0.085, 0.3, 0.035], 8, [0.9, 1.4, 0.9])  # raised right paw
	K.sph(g, 0.012, pinkM, [0.085, 0.32, 0.06], 6)
	K.box(g, 0.08, 0.1, 0.012, gold, [-0.04, 0.09, 0.09], [0, 0, 0.1])  # koban
	K.box(g, 0.05, 0.004, 0.004, K.m("#8a6a2a"), [-0.04, 0.1, 0.097], [0, 0, 0.1])
	K.sph(g, 0.028, white, [-0.06, 0.1, 0.075], 8)  # left paw holding koban


# ============================================================================ textures (sized stand-ins)

static func sign_tex(K):
	return K.tex.draw(1024, 256, null, {"key": "sb-oug-sign"})


static func sode_tex(K):
	return K.tex.draw(160, 560, null, {"key": "sb-oug-sode"})


static func lightbox_tex(K):
	return K.tex.draw(512, 128, null, {"key": "sb-oug-lightbox"})


static func noren_tex(K, _W: float, _n: int):
	return K.tex.draw(768, 360, null, {"key": "sb-oug-noren"})


static func spring_poster_tex(K, variant: String):
	return K.tex.draw(256, 368, null, {"key": "sb-spring-" + variant})


static func taiyaki_nobori_tex(K):
	return K.tex.draw(160, 580, null, {"key": "sb-taiyaki-nobori"})
