# shopsB/general.js: E3 よろず屋 山田商店. Showa 看板建築 general store: copper-plate false front with a
# crowned parapet, canvas awning, big signboard, open storefront with goods spilling onto the apron,
# ice-cream chest freezer + nobori, enamel signs, retro toys & magazines in the window.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const GeneralInt = preload("res://addons/sakuragaoka_station/world/shopsB/generalInt.gd")

const TEXTS := ["よろず屋", "山田商店", "食料品", "日用雑貨", "米穀", "たばこ", "お米", "TEL 24-3156", "ヒバリ印", "蚊とり線香", "桜川醤油", "醤油", "コトリ石鹸", "お肌すべすべ", "春日ラムネ", "つめた〜い", "アイスクリーム", "つめたい", "おいしい",
	"桜ヶ丘産", "コシヒカリ", "5kg", "10kg", "新米", "精米", "月刊", "はるかぜ", "週刊", "ハナビ", "ひだまり", "少年", "ソラマメ", "まんが", "夏まつり", "桜ヶ丘", "盆踊り", "花火大会", "8月15日", "16日", "本日の特売", "たまご", "1パック", "198円",
	"キャベツ", "1玉", "128円", "7:00〜20:00", "年中無休", "さくまる", "桜ヶ丘町", "マスコット", "カレー", "せんべい", "洗剤", "のり", "ティッシュ", "うどん", "マッチ", "キャラメル", "サイダー", "しょうゆ", "みそ", "お茶", "ラーメン", "クッキー", "ビスケット", "だがし",
	"冷たいお飲み物", "駄菓子", "10円", "20円", "30円", "ほうき", "バケツ", "ご自由にお取りください", "町内会", "お知らせ", "春の交通安全運動", "4月6日", "15日", "やまだ", "山"]


static func build_general(ctx, K, lot) -> Dictionary:
	var C: Dictionary = K.C
	var TX: Dictionary = K.TX
	var S = K.space(lot)
	var g = S.g
	var rnd = ctx.rng("shopsB-general")

	var X0 := -4.0
	var X1 := 4.0
	var ZF := -2.0
	var ZB := -11.2
	var ZI := -7.4
	var gr: Array = K.g_range(S, X0, X1, ZB, 0)
	var gmin: float = gr[0]
	var gmax: float = gr[1]
	var FL := gmax + 0.1
	var H1 := 3.1
	var Y1 := FL + H1
	var YE := FL + 5.75
	var YP := FL + 6.3
	var YC := FL + 6.8
	var WT := 0.15

	# ---------------------------------------------------------------- materials
	var mCopper = K.mt(C.copper, TX.copper, {"paint": 0.07})
	var mCopperDark = K.m("#6f9c88")
	var mMortar = K.mt("#d9d1c1", TX.plaster, {"paint": 0.07})
	var mMosaic = K.mt("#ffffff", mosaic_tex(K), {"paint": 0.04})
	var mCorr = K.mt("#94aab6", TX.corr, {"paint": 0.08})
	var mCorrBack = K.mt("#a6b3ae", TX.corr, {"paint": 0.08})
	var mAlu = K.m(C.alu)
	var mAluDark = K.m(C.aluDark)
	var mRoof = K.mt("#8d5d50", TX.corr, {"paint": 0.07})
	var mBase = K.mt("#aaa59b", TX.concrete, {"paint": 0.08})
	var mApron = K.mt("#c9c6bd", TX.concrete, {"paint": 0.06})
	var mGravel = K.mt("#b9b2a5", TX.gravel)
	var mGlass = K.glass({"opacity": 0.18})
	var _mFrost = K.glass({"frost": true})
	var mGutter = K.m("#9aa1a8", {"side": "double"})
	var iFloor = K.im("#b9bab0", 0.22, {"map": TX.tile})
	var _iWall = K.im("#ece3cf", 0.3, {"map": TX.plaster})
	var _iCeil = K.im("#e6e1d6", 0.3)
	var iWood = K.im("#a57c58", 0.3, {"map": TX.grain})
	var iWoodDark = K.im("#6e5040", 0.26, {"map": TX.grain})
	var _iShelf = K.im("#d5d2c8", 0.28)

	# ---------------------------------------------------------------- ground
	K.slab(S, -4.25, 4.25, ZF - 0.05, 0, 0.035, mApron, 4)
	K.slab(S, X1, 4.25, ZB, ZF - 0.05, 0.02, mGravel, 1.5)
	K.slab(S, -4.25, X0, ZB, ZF - 0.05, 0.02, mGravel, 1.5)
	K.slab(S, -4.25, 4.25, -14, ZB, 0.02, mGravel, 1.5)
	K.tbox(g, X1 - X0, FL - 0.02 - (gmin - 0.2), ZF - ZB, mBase, [0, (FL - 0.02 + gmin - 0.2) / 2.0, (ZF + ZB) / 2.0], 3)
	K.tbox(g, X1 - X0 - 2 * WT, 0.03, ZF - ZI - WT, iFloor, [0, FL - 0.015, (ZF - WT + ZI) / 2.0], 2.4)
	S.walk(X0 + WT, ZI, X1 - WT, ZF + 0.02, FL)
	# entrance step (low concrete sill)
	var stepTop: float = (FL + S.gl(0.1, ZF + 0.2) + 0.035) / 2.0
	K.tbox(g, 2.3, stepTop - gmin + 0.1, 0.3, K.mt("#b3afa6", TX.concrete), [0.12, (stepTop + gmin - 0.1) / 2.0, ZF + 0.15], 2)

	# ---------------------------------------------------------------- facade: ground floor
	var openL := {"a0": -3.8, "a1": -2.3, "y0": FL + 0.72, "y1": FL + 2.4}  # display window
	var openM := {"a0": -2.1, "a1": 2.3, "y0": FL, "y1": FL + 2.45}  # open storefront
	K.wall(g, mMortar, {"axis": "x", "a0": X0, "a1": X1, "y0": FL + 0.6, "y1": Y1, "c": ZF - WT / 2.0, "t": WT, "holes": [openL, openM], "tile": 2.5})
	K.wall(g, mMosaic, {"axis": "x", "a0": X0, "a1": X1, "y0": FL - 0.02, "y1": FL + 0.6, "c": ZF - WT / 2.0 + 0.005, "t": WT + 0.01, "holes": [openM], "tile": 0.4})
	# pilasters
	for x in [X0 + 0.1, -2.2, 2.38, X1 - 0.1]:
		K.tbox(g, 0.2, H1, 0.22, K.mt("#cfc6b3", TX.plaster), [x, FL + H1 / 2.0, ZF - 0.06], 2.5)
	K.box(g, openM.a1 - openM.a0, 0.05, 0.2, mAluDark, [(openM.a0 + openM.a1) / 2.0, FL + 0.01, ZF - 0.08])
	K.box(g, openM.a1 - openM.a0 + 0.1, 0.12, 0.2, mAluDark, [(openM.a0 + openM.a1) / 2.0, openM.y1 + 0.02, ZF - 0.08])
	# aluminium sliding doors pushed aside (2 stacks): open storefront during business hours
	var pw := 1.1
	var dh := 2.4
	var dOpt := {"w": pw, "h": dh, "d": 0.035, "frame": mAlu, "glass": mGlass, "stile": 0.04, "top": 0.05, "bottom": 0.1, "bars": [0.42]}
	for xz in [[openM.a0 + pw / 2.0, ZF - 0.03], [openM.a0 + pw / 2.0 + 0.08, ZF - 0.08], [openM.a1 - pw / 2.0, ZF - 0.03], [openM.a1 - pw / 2.0 - 0.08, ZF - 0.08]]:
		var p = K.panel(g, dOpt)
		p.position = Vector3(xz[0], FL + 0.02, xz[1])
	S.box(openM.a0, ZF - 0.12, openM.a0 + pw + 0.08, ZF, FL, FL + 2.4)
	S.box(openM.a1 - pw - 0.08, ZF - 0.12, openM.a1, ZF, FL, FL + 2.4)
	S.box(X0, ZF - WT, openM.a0, ZF, FL - 0.1, Y1)
	S.box(openM.a1, ZF - WT, X1, ZF, FL - 0.1, Y1)
	# display window (left)
	if true:
		var w: float = openL.a1 - openL.a0
		var h: float = openL.y1 - openL.y0
		var cx: float = (openL.a0 + openL.a1) / 2.0
		K.window(g, {"x": cx, "y0": openL.y0, "z": ZF - 0.07, "w": w, "h": h, "frame": mAluDark, "glass": mGlass, "panes": 1, "sill": true, "sillMat": K.m("#b3aca0")})
	# signs on the right pier: enamel signs
	enamel(g, K, "soy", 3.12, FL + 1.95, ZF + 0.012, 0.7, 0.95)
	enamel(g, K, "kayari", 3.12, FL + 0.95, ZF + 0.012, 0.62, 0.62)

	# ---------------------------------------------------------------- awning (テント) + valance
	if true:
		var ax0 := -3.95
		var ax1 := 3.95
		var yT := FL + 2.95
		var dep := 1.25
		var drop := 0.42
		var length := Vector2(dep, drop).length()
		var ang := atan2(drop, dep)
		var cloth = K.m("#6f9d8f", {"paint": 0.06})
		var stripe = awning_tex(K)
		K.tbox(g, ax1 - ax0, 0.02, length, K.mt("#ffffff", stripe, {"side": "double"}), [0, yT - drop / 2.0, ZF + dep / 2.0], 1.0, [ang, 0, 0])
		K.plane(g, ax1 - ax0, 0.32, K.toon_memo("#ffffff", {"map": valance_tex(K), "side": "double"}), [0, yT - drop - 0.16, ZF + dep + 0.004])
		for x in [ax0, ax1]:
			var sg := T.Group.new()
			sg.position = Vector3(x, yT, ZF)
			g.add(sg)
			K.extrude(sg, [[0, 0], [dep, -drop], [dep, -drop - 0.32], [dep - 0.05, -drop - 0.32]], 0.01, cloth, [0, 0, 0], [0, -PI / 2.0, 0])
		for x in [ax0 + 0.1, 0, ax1 - 0.1]:
			K.box(g, 0.03, 0.03, dep, mAluDark, [x, yT - drop / 2.0 - 0.03, ZF + dep / 2.0], [ang, 0, 0])
		K.box(g, ax1 - ax0, 0.05, 0.05, mAluDark, [0, yT - drop - 0.02, ZF + dep - 0.02])
		K.box(g, ax1 - ax0, 0.08, 0.08, mAluDark, [0, yT + 0.02, ZF + 0.04])
	# big signboard band
	if true:
		var sy := FL + 3.42
		var sh := 0.72
		var sw := 7.6
		K.rbox_r(g, sw + 0.1, sh + 0.1, 0.1, 0.02, K.m("#6d5a4a"), [0, sy, ZF + 0.05])
		K.plane(g, sw, sh, K.toon_memo("#ffffff", {"map": big_sign_tex(K), "paint": 0.03}), [0, sy, ZF + 0.102])
		for x in [-3.2, 0, 3.2]:
			K.box(g, 0.04, 0.04, 0.22, mAluDark, [x, sy + sh / 2.0 + 0.2, ZF + 0.15])
			K.cyl(g, 0.05, 0.1, K.m("#5c6168"), [x, sy + sh / 2.0 + 0.2, ZF + 0.3], 10, [PI / 2.0 - 0.5, 0, 0], 0.09)

	# ---------------------------------------------------------------- facade: upper floor (copper plates) + parapet + crown
	var win2 := [{"a0": -3.25, "a1": -0.95, "y0": FL + 4.15, "y1": FL + 5.2}, {"a0": 0.95, "a1": 3.25, "y0": FL + 4.15, "y1": FL + 5.2}]
	K.wall(g, mCopper, {"axis": "x", "a0": X0, "a1": X1, "y0": Y1, "y1": YP, "c": ZF - WT / 2.0, "t": WT, "holes": win2, "tile": 1.8})
	K.wall(g, mCopper, {"axis": "x", "a0": -1.25, "a1": 1.25, "y0": YP, "y1": YC, "c": ZF - WT / 2.0, "t": WT, "tile": 1.8})
	K.box(g, X1 - X0 + 0.16, 0.1, 0.24, mCopperDark, [0, Y1 + 0.02, ZF - 0.03])
	# cornice (stepped) + 七宝 band + crown with 屋号
	K.box(g, X1 - X0 + 0.2, 0.1, 0.28, mCopperDark, [0, YP - 0.02, ZF - 0.02])
	K.box(g, X1 - X0 + 0.28, 0.06, 0.34, K.m("#7fa895"), [0, YP + 0.06, ZF - 0.02])
	K.plane(g, X1 - X0 - 0.3, 0.26, K.toon_memo("#ffffff", {"map": shippo_tex(K)}), [0, YP - 0.3, ZF + 0.004])
	K.box(g, 2.62, 0.08, 0.3, K.m("#7fa895"), [0, YC + 0.02, ZF - 0.02])
	for x in [-1.3, 1.3]:
		K.box(g, 0.12, YC - YP, 0.22, mCopperDark, [x, (YC + YP) / 2.0, ZF - 0.04])
	K.cyl(g, 0.24, 0.05, K.m("#e9e2cf"), [0, YC - 0.25, ZF + 0.01], 24, [PI / 2.0, 0, 0])
	K.plane(g, 0.42, 0.42, K.toon_memo("#ffffff", {"map": yago_tex(K), "transparent": true}), [0, YC - 0.25, ZF + 0.038])
	for o in win2:
		var w: float = o.a1 - o.a0
		var h: float = o.y1 - o.y0
		var cx: float = (o.a0 + o.a1) / 2.0
		K.window(g, {"x": cx, "y0": o.y0, "z": ZF - 0.07, "w": w, "h": h, "frame": mAlu, "glass": mGlass, "panes": 2, "behind": K.curtain("#e9dccb" if cx < 0 else "#dfe6ea"), "behindD": 0.1, "sillMat": mCopperDark})
		# iron railing (手すり) with flower box
		var rg := T.Group.new()
		rg.position = Vector3(cx, o.y0 - 0.12, ZF + 0.18)
		g.add(rg)
		var iron = K.m("#4f5a60")
		K.box(rg, w + 0.1, 0.03, 0.03, iron, [0, 0.62, 0])
		K.box(rg, w + 0.1, 0.02, 0.02, iron, [0, 0.08, 0])
		for i in 13:
			K.box(rg, 0.014, 0.54, 0.014, iron, [-w / 2.0 - 0.05 + i * (w + 0.1) / 12.0, 0.35, 0])
		for sx in [-1, 1]:
			K.box(rg, 0.03, 0.03, 0.2, iron, [sx * (w / 2.0 + 0.04), 0.3, -0.1])
		K.box(rg, w * 0.6, 0.14, 0.16, K.m("#b98a6a"), [0.1, 0.16, -0.1])
		K.hedge(rg, 0.1, 0.2, -0.1, w * 0.58, 0.16, 0.15, 4 if cx < 0 else 5)
		var fc := ["#f2b5c8", "#f7e28a", "#f4efe6"]
		for i in 5:
			K.sph(rg, 0.03, K.m(fc[i % 3]), [-w * 0.22 + i * w * 0.11, 0.35, -0.03], 6)

	# ---------------------------------------------------------------- side walls (corrugated tin), back wall, roof (妻入り metal)
	for x in [X0 + WT / 2.0, X1 - WT / 2.0]:
		K.wall(g, mCorr, {"axis": "z", "a0": ZB, "a1": ZF - WT, "y0": FL - 0.05, "y1": YE, "c": x, "t": WT, "holes": [{"a0": -6.5, "a1": -5.3, "y0": FL + 3.9, "y1": FL + 4.9}] if x > 0 else [], "tile": 1.2})
		S.box(x - WT / 2.0, ZB, x + WT / 2.0, ZF, FL - 0.1, YE)
	K.window(g, {"x": X1 + 0.005, "y0": FL + 3.9, "z": -5.9, "w": 1.2, "h": 1.0, "frame": mAluDark, "glass": mGlass, "panes": 2, "rotY": PI / 2.0, "behind": K.curtain("#efe0cf")})
	# painted enamel ad on the south side wall (visible from the street to the south)
	if true:
		var sg := T.Group.new()
		sg.position = Vector3(X1 + 0.02, FL + 2.3, -4.2)
		sg.rotation.y = PI / 2.0
		g.add(sg)
		enamel(sg, K, "ramune", 0, 0, 0, 1.0, 1.4)
		var sg2 := T.Group.new()
		sg2.position = Vector3(X1 + 0.02, FL + 2.1, -7.4)
		sg2.rotation.y = PI / 2.0
		g.add(sg2)
		enamel(sg2, K, "soap", 0, 0, 0, 1.3, 0.45)
	K.wall(g, mCorrBack, {"axis": "x", "a0": X0 + WT, "a1": X1 - WT, "y0": FL - 0.05, "y1": YE, "c": ZB + WT / 2.0, "t": WT, "holes": [{"a0": -3.0, "a1": -2.1, "y0": FL, "y1": FL + 1.9}, {"a0": 0.5, "a1": 2.0, "y0": FL + 3.7, "y1": FL + 4.7}], "tile": 1.2})
	K.box(g, 0.9, 1.9, 0.05, K.m("#8d949b"), [-2.55, FL + 0.95, ZB - 0.02])
	K.window(g, {"x": 1.25, "y0": FL + 3.7, "z": ZB - 0.03, "w": 1.5, "h": 1.0, "frame": mAluDark, "glass": mGlass, "panes": 2, "rotY": PI, "behind": K.curtain("#d9e0d2")})
	S.box(X0, ZB, X1, ZI, FL - 0.1, YE)
	# roof: gable with ridge along z (hidden behind the false front)
	if true:
		var rg := T.Group.new()
		rg.rotation.y = PI / 2.0
		g.add(rg)
		var ov := 0.12
		var pitch := 0.17
		var yR := YE + 0.05 + pitch * (X1 - X0) / 2.0
		K.gable_x(rg, {"x0": -(ZF - 0.1), "x1": -(ZB - ov), "zf": X1 + ov, "zb": X0 - ov, "yE": YE + 0.05 - pitch * ov, "yR": yR, "zR": 0, "t": 0.08, "mat": mRoof, "tile": 1.2, "fascia": K.m("#c9c2b2")})
		K.box(rg, (ZF - 0.1) - (ZB - ov), 0.1, 0.24, K.m("#7a4f44"), [-((ZF - 0.1) + (ZB - ov)) / 2.0, yR + 0.06, 0])
		# gable end (back) triangle
		K.gable_end(rg, mCorrBack, -(ZB + WT / 2.0) + 0.0, X0, X1, YE - 0.01, 0, yR - 0.05, WT, 1.2)
		K.gutter_x(rg, -(ZF - 0.1), -(ZB - ov), YE + 0.05 - pitch * ov - 0.08, X1 + ov + 0.05, mGutter)
		K.gutter_x(rg, -(ZF - 0.1), -(ZB - ov), YE + 0.05 - pitch * ov - 0.08, -(X1 + ov + 0.05), mGutter)
	K.downpipe(g, X1 + 0.17, ZB + 0.3, YE - 0.05, S.gl(X1 + 0.17, ZB + 0.3), mGutter, 0.17, [-1, 0])
	K.downpipe(g, X0 - 0.17, ZB + 0.3, YE - 0.05, S.gl(X0 - 0.17, ZB + 0.3), mGutter, 0.17, [1, 0])
	# side-gap utilities on the south wall
	if true:
		var wg := T.Group.new()
		wg.position = Vector3(X1 + 0.005, 0, 0)
		wg.rotation.y = PI / 2.0
		g.add(wg)
		K.meter(wg, 9.3, FL + 1.6, 0)
		K.gas_meter(wg, 8.7, FL + 1.0, 0)
		# propane-free: water pipe + TV cable
		K.cyl(g, 0.02, YE - FL - 1.0, K.m("#d9d4c6"), [X1 + 0.05, (YE + FL) / 2.0 + 0.3, -8.3], 6)
	K.ac_unit(g, X1 + 0.03, S.gl(X1, -9.5) + 0.02, -9.6, PI / 2.0)
	S.box(X1, -10, 4.25, -9.2, 0, 0.7)

	# ---------------------------------------------------------------- interior (see generalInt.gd)
	GeneralInt.build_general_interior(ctx, K, S, {"FL": FL, "ZF": ZF, "ZI": ZI, "WT": WT, "X0": X0, "X1": X1})
	# display window contents: retro toys + magazines + festival poster
	if true:
		var cx: float = (openL.a0 + openL.a1) / 2.0
		var z0 := ZF - WT
		K.box(g, 1.5, 0.72, 0.6, iWoodDark, [cx, FL + 0.36, z0 - 0.3])
		K.box(g, 1.52, 0.03, 0.62, K.im("#c9463e", 0.25), [cx, FL + 0.735, z0 - 0.3])
		K.box(g, 1.5, 0.03, 0.3, iWood, [cx, FL + 1.25, z0 - 0.45])
		for x in [openL.a0 + 0.05, openL.a1 - 0.05]:
			K.box(g, 0.03, 0.5, 0.3, iWoodDark, [x, FL + 1.0, z0 - 0.45])
		retro_toys(g, K, cx, FL + 0.75, z0 - 0.2, rnd)
		magazines(g, K, cx, FL + 1.265, z0 - 0.45)
		K.decal(g, festival_tex(K), 0.42, 0.6, [openL.a1 - 0.3, FL + 1.8, ZF - 0.1])
		K.decal(g, mascot_tex(K), 0.2, 0.2, [openL.a0 + 0.22, FL + 2.1, ZF - 0.066])
		S.box(openL.a0, z0 - 0.7, openL.a1, ZF, FL, FL + 1.3)
	# stickers on the door glass
	K.decal(g, K.hours_sticker(["7:00〜20:00", "年中無休"], "#3f8f5b"), 0.22, 0.165, [openM.a0 + 0.35, FL + 1.35, ZF + 0.0])
	K.decal(g, K.cashless(), 0.36, 0.113, [openM.a1 - 0.45, FL + 1.3, ZF + 0.0])
	K.decal(g, mascot_tex(K), 0.16, 0.16, [openM.a1 - 0.7, FL + 1.62, ZF + 0.0])

	# ---------------------------------------------------------------- apron goods
	var ag := func(x, z): return S.gl(x, z) + 0.035
	# wooden bench with backrest in front of the window
	K.bench(g, -3.1, ag.call(-3.1, -1.62), -1.62, 1.4, 0, {"color": "#8fa9b8", "leg": "#6a7f8c", "back": true, "d": 0.4})
	S.box(-3.82, -1.85, -2.38, -1.4, ag.call(-3.1, -1.6), ag.call(-3.1, -1.6) + 0.46)
	# drink crates
	if true:
		var cols := ["#e8c547", "#d9463b", "#e8c547", "#3f7fb5"]
		var i := 0
		for c in [[-1.95, -1.75, 3], [-1.45, -1.8, 2], [-1.75, -1.15, 1]]:
			var x: float = c[0]
			var z: float = c[1]
			var n: int = c[2]
			for k in n:
				K.crate(g, x, ag.call(x, z) + k * 0.3, z, cols[i % cols.size()], (k % 2) * 0.06 - 0.03, k == n - 1, "#6f9a6a" if k % 2 else "#8a5a3a")
				i += 1
			S.box(x - 0.24, z - 0.18, x + 0.24, z + 0.18, ag.call(x, z), ag.call(x, z) + n * 0.3)
	# ice-cream chest freezer + nobori
	if true:
		var fx := 1.78
		var fz := -1.62
		var y0: float = ag.call(fx, fz)
		freezer(g, K, fx, y0, fz)
		S.box(fx - 0.53, fz - 0.33, fx + 0.53, fz + 0.33, y0, y0 + 0.9)
		K.nobori(S, {"x": 2.0, "z": -0.2, "rot": -0.35, "tex": ice_nobori_tex(K), "w": 0.45, "h": 1.6, "poleH": 2.5, "flip": true, "baseColor": "#8d949b"})
	# rice bags on a pallet + brooms + buckets at the right pier (behind the gashapon spot)
	if true:
		var px := 2.95
		var pz := -1.72
		var y0: float = ag.call(px, pz)
		K.box(g, 0.9, 0.1, 0.5, K.mt("#b89468", TX.grain), [px, y0 + 0.05, pz])
		for i in 3:
			rice_bag(g, K, px - 0.18 + (i % 2) * 0.36, y0 + 0.1 + floori(i / 2.0) * 0.15, pz, 0.05 * (i - 1), "10kg" if i == 2 else "5kg", false)
		rice_bag(g, K, px, y0 + 0.4, pz, 0.12, "5kg", false)
		S.box(px - 0.48, pz - 0.28, px + 0.48, pz + 0.28, y0, y0 + 0.6)
		brooms(g, K, 3.72, ag.call(3.72, -1.85), -1.85)
		buckets(g, K, 3.95, ag.call(3.95, -1.2), -1.2)
		S.box(3.5, -2.0, 4.2, -0.95, y0, y0 + 1.4)
	# small blackboard (本日の特売) by the entrance
	if true:
		var x := -0.85
		var z := -0.55
		var y0: float = ag.call(x, z)
		var bg := T.Group.new()
		bg.position = Vector3(x, y0, z)
		bg.rotation.y = 0.35
		g.add(bg)
		var wood = K.m("#8a6446")
		for s in [1, -1]:
			var leg = K.box(bg, 0.04, 0.8, 0.03, wood, [0, 0.4, s * 0.14])
			leg.rotation.x = -s * 0.2
		var face := T.Group.new()
		face.position = Vector3(0, 0.44, 0.16)
		face.rotation.x = -0.2
		bg.add(face)
		K.box(face, 0.5, 0.66, 0.03, wood, [0, 0, 0])
		K.plane(face, 0.44, 0.6, K.toon_memo("#ffffff", {"map": chalk_tex(K)}), [0, 0, 0.017])
		S.box(x - 0.28, z - 0.25, x + 0.28, z + 0.25, y0, y0 + 0.9)
	return {"S": S, "FL": FL}


# ============================================================================ props

static func rice_bag(p, K, x: float, y: float, z: float, rot: float, size := "5kg", interior := true):
	var t = rice_tex(K, size)
	var m = K.im("#ffffff", 0.3, {"map": t}) if interior else K.mt("#ffffff", t)
	var w := 0.46 if size == "10kg" else 0.38
	var d := 0.3 if size == "10kg" else 0.26
	var h := 0.14
	var b = K.rbox(p, w, h, d, 0.3, m, [x, y + h / 2.0, z])
	b.rotation.y = rot
	return b


static func rice_tex(K, size: String):
	return K.tex.draw(256, 160, null, {"key": "sb-rice-" + size})


static func brooms(p, K, x: float, y: float, z: float) -> void:
	var handle = K.m("#c9a36a")
	var straw = K.m("#b59a5a")
	var bamboo = K.m("#9a8a52")
	# bamboo broom (竹ぼうき) + room broom (座敷ほうき) leaning on the wall, in a holder
	var b1 := T.Group.new()
	b1.position = Vector3(x, y, z)
	b1.rotation = Vector3(-0.12, 0, 0.1)
	p.add(b1)
	K.cyl(b1, 0.016, 1.35, handle, [0, 0.9, 0], 6)
	K.cyl(b1, 0.03, 0.5, bamboo, [0, 0.25, 0], 8, null, 0.16).scale = Vector3(1, 0.5, 0.45)
	var b2 := T.Group.new()
	b2.position = Vector3(x - 0.2, y, z + 0.05)
	b2.rotation = Vector3(-0.14, 0, -0.08)
	p.add(b2)
	K.cyl(b2, 0.014, 1.0, handle, [0, 0.75, 0], 6)
	K.box(b2, 0.28, 0.3, 0.07, straw, [0, 0.16, 0])
	K.box(b2, 0.29, 0.03, 0.08, K.m("#c9463e"), [0, 0.3, 0])
	var b3 := T.Group.new()
	b3.position = Vector3(x + 0.18, y, z + 0.02)
	b3.rotation = Vector3(-0.1, 0, 0.16)
	p.add(b3)
	K.cyl(b3, 0.015, 1.1, handle, [0, 0.8, 0], 6)
	K.box(b3, 0.22, 0.24, 0.05, K.m("#d8c27a"), [0, 0.13, 0])
	K.plane(p, 0.2, 0.08, K.mt("#ffffff", K.card(["ほうき", "980円"], {"w": 160, "h": 72, "bg": "#f4efe2", "fg": "#3a3346", "fg2": "#c9463e"})), [x, y + 0.95, z + 0.12])


static func buckets(p, K, x: float, y: float, z: float) -> void:
	var cols := ["#3f7fb5", "#d9463b", "#e8c547", "#6f9a6a"]
	for i in 4:
		K.cyl(p, 0.15, 0.24, K.m(cols[i]), [x, y + 0.12 + i * 0.06, z], 14, [PI, 0, 0], 0.12)
	K.cyl(p, 0.16, 0.02, K.m(cols[3]), [x, y + 0.36, z], 14)
	K.plane(p, 0.16, 0.08, K.mt("#ffffff", K.card(["バケツ", "380円"], {"w": 160, "h": 72, "bg": "#f4efe2", "fg": "#3a3346", "fg2": "#c9463e"})), [x, y + 0.2, z + 0.155], 0, 0.1)


static func freezer(p, K, x: float, y: float, z: float) -> void:
	var g := T.Group.new()
	g.position = Vector3(x, y, z)
	p.add(g)
	var body = K.m("#eeeae2")
	var trim = K.m("#3f7fb5")
	K.rbox_r(g, 1.02, 0.78, 0.62, 0.05, body, [0, 0.45, 0])
	K.box(g, 1.03, 0.07, 0.63, trim, [0, 0.12, 0])
	K.box(g, 0.94, 0.02, 0.54, K.lamp(1.05, "#dbe9f2"), [0, 0.84, 0])  # lit interior seen through the lid
	# ice cream packs inside (under the glass)
	var cols := ["#f2b5c8", "#f7e28a", "#a9cfc0", "#e9c7a0", "#b9c7ea", "#f4efe6"]
	var rr = K.ctx.rng("freezer")
	for i in 12:
		var pz: float = -0.12 + floori(i / 6.0) * 0.2 + rr.range(-0.02, 0.02)
		K.box(g, 0.12, 0.03, 0.08, K.m(cols[i % 6]), [-0.38 + (i % 6) * 0.15, 0.86, pz]).rotation.y = rr.range(-0.3, 0.3)
	for zz in [-0.13, 0.13]:
		var lid = K.box(g, 0.98, 0.012, 0.27, K.glass({"opacity": 0.25}), [0, 0.88, zz])
		lid.cast_shadow = false
		K.ctx.no_outline(lid)
	K.box(g, 1.0, 0.03, 0.03, K.m("#b9bfc4"), [0, 0.885, 0.3])
	K.box(g, 1.0, 0.03, 0.03, K.m("#b9bfc4"), [0, 0.885, -0.3])
	K.plane(g, 0.8, 0.26, K.mt("#ffffff", freezer_tex(K)), [0, 0.5, 0.313])
	for sx in [-0.45, 0.45]:
		K.box(g, 0.06, 0.06, 0.5, K.m("#6d747c"), [sx, 0.03, 0])


static func freezer_tex(K):
	return K.tex.draw(512, 168, null, {"key": "sb-freezer"})


static func ice_nobori_tex(K):
	return K.tex.draw(160, 570, null, {"key": "sb-ice-nobori"})


static func mosaic_tex(K):
	return K.tex.draw(256, 256, null, {"key": "sb-mosaic", "repeat": [1, 1]})


static func awning_tex(K):
	return K.tex.draw(256, 64, null, {"key": "sb-awning", "repeat": [1, 1]})


static func valance_tex(K):
	return K.tex.draw(1024, 64, null, {"key": "sb-valance"})


static func big_sign_tex(K):
	return K.tex.draw(1024, 100, null, {"key": "sb-yamada-sign"})


static func shippo_tex(K):
	return K.tex.draw(1024, 64, null, {"key": "sb-shippo"})


static func yago_tex(K):
	return K.tex.draw(128, 128, null, {"key": "sb-yago"})


const ENAMEL := {
	"soy": {"bg": "#b8423c", "fg": "#f6efe2", "lines": ["桜川醤油"], "sub": "しょうゆ", "vertical": true},
	"kayari": {"bg": "#2f5f9e", "fg": "#f6efe2", "lines": ["ヒバリ印", "蚊とり線香"]},
	"soap": {"bg": "#3f8f5b", "fg": "#f6efe2", "lines": ["コトリ石鹸"], "sub": "お肌すべすべ"},
	"ramune": {"bg": "#f1ece0", "fg": "#2f5f9e", "lines": ["春日ラムネ"], "sub": "つめた〜い", "vertical": true, "bottle": true},
}


static func enamel_tex(K, kind: String):
	var e: Dictionary = ENAMEL[kind]
	var vertical := bool(e.get("vertical", false))
	var W := 256 if vertical else (512 if kind == "soap" else 256)
	var H := 384 if vertical else (160 if kind == "soap" else 256)
	return K.tex.draw(W, H, null, {"key": "sb-enamel-" + kind})


static func enamel(p, K, kind: String, x: float, y: float, z: float, w: float, h: float):
	var m = K.plane(p, w, h, K.mt("#ffffff", enamel_tex(K, kind), {"paint": 0.03}), [x, y, z])
	K.box(p, w + 0.01, h + 0.01, 0.008, K.m("#6d747c"), [x, y, z - 0.006])
	return m


static func retro_toys(p, K, x: float, y: float, z: float, rnd) -> void:
	var m := func(c): return K.im(c, 0.32)
	# daruma
	K.sph(p, 0.09, m.call("#c9463e"), [x - 0.5, y + 0.09, z], 12, [1, 1.05, 0.95])
	K.sph(p, 0.05, m.call("#f3ead8"), [x - 0.5, y + 0.11, z + 0.055], 10, [1, 1, 0.5])
	K.sph(p, 0.012, m.call("#3a3346"), [x - 0.47, y + 0.12, z + 0.075], 6)
	# kendama
	K.cyl(p, 0.012, 0.18, m.call("#c9a36a"), [x - 0.27, y + 0.09, z + 0.05], 6)
	K.box(p, 0.1, 0.035, 0.035, m.call("#c9a36a"), [x - 0.27, y + 0.15, z + 0.05])
	K.sph(p, 0.035, m.call("#d9463b"), [x - 0.27, y + 0.215, z + 0.05], 10)
	# tin robot
	var rx := x - 0.05
	K.box(p, 0.09, 0.12, 0.06, m.call("#9aa6b3"), [rx, y + 0.1, z])
	K.box(p, 0.07, 0.06, 0.06, m.call("#b9c3cc"), [rx, y + 0.19, z])
	K.box(p, 0.03, 0.05, 0.03, m.call("#9aa6b3"), [rx - 0.025, y + 0.025, z])
	K.box(p, 0.03, 0.05, 0.03, m.call("#9aa6b3"), [rx + 0.025, y + 0.025, z])
	K.box(p, 0.05, 0.012, 0.01, m.call("#e8c547"), [rx, y + 0.195, z + 0.032])
	K.cyl(p, 0.004, 0.04, m.call("#6d747c"), [rx, y + 0.24, z], 4)
	K.sph(p, 0.01, m.call("#d9463b"), [rx, y + 0.265, z], 6)
	# spinning tops (独楽)
	var tc := ["#d9463b", "#3f7fb5", "#e8c547"]
	for i in 3:
		K.cyl(p, 0.0, 0.05, m.call(tc[i]), [x + 0.14 + i * 0.09, y + 0.035, z + 0.09], 10, [PI, 0, 0], 0.045)
		K.cyl(p, 0.006, 0.03, m.call("#6e5040"), [x + 0.14 + i * 0.09, y + 0.075, z + 0.09], 5)
	# toy train (local line colours)
	K.rbox(p, 0.26, 0.08, 0.07, 0.25, m.call("#f5f0e6"), [x + 0.35, y + 0.05, z - 0.08])
	K.box(p, 0.262, 0.018, 0.072, m.call("#ef9fbe"), [x + 0.35, y + 0.045, z - 0.08])
	for dx in [-0.08, 0.08]:
		K.cyl(p, 0.018, 0.075, m.call("#3a3346"), [x + 0.35 + dx, y + 0.015, z - 0.08], 8, [PI / 2.0, 0, 0])
	# pinwheel (風車)
	K.cyl(p, 0.004, 0.3, m.call("#6f9a6a"), [x + 0.6, y + 0.15, z - 0.05], 4)
	var pc := ["#f2b5c8", "#f7e28a", "#a9cfc0", "#b9c7ea"]
	for i in 4:
		var b = K.box(p, 0.06, 0.012, 0.004, m.call(pc[i]), [x + 0.6, y + 0.3, z - 0.05 + 0.004])
		b.rotation.z = i * PI / 2.0 + 0.4
		b.position.x += cos(i * PI / 2.0 + 0.4) * 0.03
		b.position.y += sin(i * PI / 2.0 + 0.4) * 0.03
	# menko cards / marbles jar
	var mc := ["#e9a23b", "#5f8fcf", "#d9463b", "#8fb86f"]
	for i in 4:
		K.box(p, 0.06, 0.004, 0.06, m.call(mc[i]), [x + 0.1 + i * 0.07, y + 0.004, z - 0.12]).rotation.y = rnd.range(-0.5, 0.5)


const MAGS := [["月刊", "はるかぜ", "#f2b5c8", "#8e3b36"], ["週刊", "ハナビ", "#5f8fcf", "#fdf8ee"], ["少年", "ソラマメ", "#e8c547", "#2f3f6e"], ["まんが", "ひだまり", "#a9cfc0", "#3a3346"]]


static func mag_tex(K, i: int):
	return K.tex.draw(128, 176, null, {"key": "sb-mag%d" % (i % MAGS.size())})


static func magazines(p, K, x: float, y: float, z: float) -> void:
	for i in 5:
		var mg = K.plane(p, 0.2, 0.275, K.im("#ffffff", 0.3, {"map": mag_tex(K, i)}), [x - 0.52 + i * 0.26, y + 0.14, z + 0.02])
		mg.rotation.x = -0.22
		mg.rotation.y = (i - 2) * 0.05
		K.box(p, 0.2, 0.275, 0.008, K.im("#e9e4d8", 0.3), [x - 0.52 + i * 0.26, y + 0.14, z + 0.015], [-0.22, (i - 2) * 0.05, 0])


static func festival_tex(K):
	return K.tex.draw(256, 368, null, {"key": "sb-festival"})


static func mascot_tex(K):
	return K.tex.draw(128, 128, null, {"key": "sb-mascot"})


static func chalk_tex(K):
	return K.tex.draw(256, 352, null, {"key": "sb-chalk"})
