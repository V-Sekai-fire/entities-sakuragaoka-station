# shopsB/sweets.js: modelled wagashi pieces (instanced through K.I). Every builder takes the parent, K
# and the position of the piece's bottom centre on a surface; rot = rotation about Y.
extends RefCounted

const Props = preload("res://addons/sakuragaoka_station/world/shopsB/props.gd")


static func G(p, x: float, y: float, z: float, rot_y: float = 0.0):
	return Props.grp(p, x, y, z, rot_y)


## SWEETS[kind](p, K, x, y, z, rot, extra)
static func sweet(kind: String, p, K, x: float, y: float, z: float, rot: float = 0.0, extra = null) -> void:
	match kind:
		"sakura": sakura(p, K, x, y, z, rot)
		"dango": dango(p, K, x, y, z, rot, extra if extra != null else "sanshoku")
		"dora": dora(p, K, x, y, z, rot)
		"manju": manju(p, K, x, y, z, rot, bool(extra) if extra != null else false)
		"daifuku": daifuku(p, K, x, y, z, rot)
		"ichigo": ichigo(p, K, x, y, z, rot)
		"kashiwa": kashiwa(p, K, x, y, z, rot)
		"kusa": kusa(p, K, x, y, z, rot)
		"nerikiri": nerikiri(p, K, x, y, z, rot, extra if extra != null else "#f6c3d2")
		"monaka": monaka(p, K, x, y, z, rot)
		"yokan": yokan(p, K, x, y, z, rot, extra if extra != null else "neri")
		"yokanSlices": yokan_slices(p, K, x, y, z, rot)


## 桜もち (Kanto chōmeiji style): pink crêpe roll wrapped in a salted cherry leaf.
static func sakura(p, K, x: float, y: float, z: float, rot: float = 0.0) -> void:
	var g = G(p, x, y, z, rot)
	K.I.add("sph", g, [0, 0.009, 0], [0.068, 0.018, 0.05], "#7f8a45")  # leaf underneath
	K.I.add("sph", g, [0, 0.019, 0], [0.058, 0.028, 0.034], "#f2a9bd")  # pink roll
	K.I.add("sph", g, [0.012, 0.03, 0.004], [0.036, 0.012, 0.042], "#8c9a4c", [0, 0, -0.35])  # leaf flap over the top


## 三色だんご / みたらし / あん on a bamboo skewer lying on the tray (along local x).
static func dango(p, K, x: float, y: float, z: float, rot: float = 0.0, kind := "sanshoku") -> void:
	var g = G(p, x, y, z, rot)
	K.I.add("cylc", g, [0.012, 0.013, 0], [0.0045, 0.14, 0.0045], "#d9c08a", [0, 0, PI / 2.0])
	var cols: Array
	if kind == "mitarashi":
		cols = ["#c98a4e", "#c98a4e", "#c98a4e"]
	elif kind == "an":
		cols = ["#5a3040", "#5a3040", "#5a3040"]
	else:
		cols = ["#f2a7bb", "#f3efe4", "#9cc27a"]
	for i in cols.size():
		K.I.add("sph", g, [-0.028 + i * 0.027, 0.013, 0], [0.027, 0.025, 0.026], cols[i])
	if kind == "mitarashi":
		K.I.add("sph", g, [0, 0.022, 0], [0.084, 0.01, 0.028], "#b06a34")  # glaze


## どら焼き
static func dora(p, K, x: float, y: float, z: float, rot: float = 0.0) -> void:
	var g = G(p, x, y, z, rot)
	K.I.add("sph", g, [0, 0.008, 0], [0.078, 0.017, 0.078], "#c9884a")
	K.I.add("disc", g, [0, 0.012, 0], [0.07, 0.007, 0.07], "#5a3040")
	K.I.add("sph", g, [0, 0.022, 0], [0.078, 0.022, 0.078], "#a8642f")
	K.I.add("disc", g, [0, 0.0325, 0], [0.028, 0.0015, 0.028], "#7a4424")  # branded mark


## 酒まんじゅう / 栗まんじゅう
static func manju(p, K, x: float, y: float, z: float, rot: float = 0.0, brown := false) -> void:
	var g = G(p, x, y, z, rot)
	K.I.add("sph", g, [0, 0.016, 0], [0.052, 0.034, 0.052], "#c28550" if brown else "#f1e6d2")
	K.I.add("disc", g, [0, 0.0315, 0], [0.018, 0.0015, 0.018], "#7a4424" if brown else "#b87a7a")
	if brown:
		K.I.add("sph", g, [0, 0.03, 0], [0.028, 0.006, 0.028], "#8e5028")


## 大福 (豆大福 with black beans)
static func daifuku(p, K, x: float, y: float, z: float, rot: float = 0.0) -> void:
	var g = G(p, x, y, z, rot)
	K.I.add("sph", g, [0, 0.017, 0], [0.052, 0.034, 0.052], "#f4f0e8")
	for i in 3:
		var a := i * 2.2 + 0.4
		K.I.add("ball", g, [cos(a) * 0.016, 0.028 - (i % 2) * 0.004, sin(a) * 0.016], [0.011, 0.008, 0.011], "#4a3a4a")


## いちご大福
static func ichigo(p, K, x: float, y: float, z: float, rot: float = 0.0) -> void:
	var g = G(p, x, y, z, rot)
	K.I.add("sph", g, [0, 0.018, 0], [0.052, 0.036, 0.052], "#f7eef0")
	K.I.add("sph", g, [0.004, 0.036, 0.006], [0.022, 0.024, 0.022], "#d9463b")
	K.I.add("disc", g, [0.004, 0.047, 0.006], [0.014, 0.003, 0.014], "#5f8c4c")


## 柏もち: white mochi half-moon in an oak leaf.
static func kashiwa(p, K, x: float, y: float, z: float, rot: float = 0.0) -> void:
	var g = G(p, x, y, z, rot)
	K.I.add("sph", g, [0, 0.008, 0], [0.074, 0.016, 0.054], "#5f7a40")
	K.I.add("sph", g, [0, 0.019, 0], [0.062, 0.03, 0.036], "#f1ede4")
	K.I.add("sph", g, [0, 0.03, -0.012], [0.07, 0.01, 0.03], "#6f8a4a", [0.5, 0, 0])


## 草もち
static func kusa(p, K, x: float, y: float, z: float, rot: float = 0.0) -> void:
	var g = G(p, x, y, z, rot)
	K.I.add("sph", g, [0, 0.016, 0], [0.052, 0.032, 0.052], "#8aa865")
	K.I.add("sph", g, [0, 0.03, 0], [0.03, 0.008, 0.03], "#9dba78")


## 練り切り (sakura flower)
static func nerikiri(p, K, x: float, y: float, z: float, rot: float = 0.0, col = "#f6c3d2") -> void:
	var g = G(p, x, y, z, rot)
	for i in 5:
		var a := float(i) / 5 * PI * 2.0
		K.I.add("sph", g, [cos(a) * 0.012, 0.015, sin(a) * 0.012], [0.03, 0.026, 0.026], col, [0, -a, 0])
	K.I.add("ball", g, [0, 0.03, 0], [0.012, 0.008, 0.012], "#f2d36a")


## もなか (shell-shaped wafer)
static func monaka(p, K, x: float, y: float, z: float, rot: float = 0.0) -> void:
	var g = G(p, x, y, z, rot)
	K.I.add("rbox", g, [0, 0, 0], [0.06, 0.028, 0.06], "#d9b57e", [0, PI / 4.0, 0])
	K.I.add("disc", g, [0, 0.028, 0], [0.04, 0.002, 0.04], "#c49a60")


## 羊羹 bar (whole), optionally in gold foil / matcha / sakura layer.
static func yokan(p, K, x: float, y: float, z: float, rot: float = 0.0, kind := "neri") -> void:
	var g = G(p, x, y, z, rot)
	var c = {"neri": "#5a2a36", "matcha": "#5f7a3a", "foil": "#c9a45a", "sakura": "#6a3040"}[kind]
	K.I.add("rbox", g, [0, 0, 0], [0.19, 0.032, 0.052], c)
	if kind == "sakura":
		K.I.add("rbox", g, [0, 0.03, 0], [0.19, 0.01, 0.052], "#f0a6bb")
	if kind == "foil":
		K.I.add("box", g, [0.03, 0.032, 0], [0.05, 0.002, 0.053], "#b8423c")


## sliced yokan fanned on a small plate
static func yokan_slices(p, K, x: float, y: float, z: float, rot: float = 0.0) -> void:
	var g = G(p, x, y, z, rot)
	K.I.add("dish", g, [0, 0, 0], [0.14, 0.12, 0.14], "#e9e4d8")
	for i in 4:
		K.I.add("box", g, [-0.03 + i * 0.02, 0.006, 0], [0.013, 0.034, 0.048], "#5a2a36", [0, 0, -0.22])


## Lacquer tray with rims + washi sheet; returns top y of the sheet.
static func lacquer_tray(p, K, x: float, y: float, z: float, w: float, d: float, color = "#7a2e2e") -> float:
	K.I.add("box", p, [x, y, z], [w, 0.01, d], color)
	for s in [-1, 1]:
		K.I.add("box", p, [x, y + 0.01, z + s * (d / 2.0 - 0.004)], [w, 0.014, 0.008], color)
		K.I.add("box", p, [x + s * (w / 2.0 - 0.004), y + 0.01, z], [0.008, 0.014, d - 0.016], color)
	K.I.add("box", p, [x, y + 0.01, z], [w - 0.03, 0.002, d - 0.03], "#f4efe4")
	return y + 0.012


## Fill a tray (w × d centred at x, z) with a grid of one kind of sweet.
static func fill_tray(p, K, kind: String, x: float, y: float, z: float, w: float, d: float, cols: int, rows: int, rnd, extra = null) -> void:
	for i in cols:
		for j in rows:
			var px: float = x - w / 2.0 + w * (i + 0.5) / cols + rnd.range(-0.004, 0.004)
			var pz: float = z - d / 2.0 + d * (j + 0.5) / rows + rnd.range(-0.003, 0.003)
			sweet(kind, p, K, px, y, pz, rnd.range(-0.15, 0.15) + 0.0, extra)


## Folded paper tent card (two planes) standing on a surface, text faces +Z.
static func tent_card(p, K, x: float, y: float, z: float, rot_y: float, tex, w: float = 0.075, h: float = 0.042):
	var g = G(p, x, y, z, rot_y)
	var a := 0.28
	var m = K.im("#ffffff", 0.38, {"map": tex})
	K.plane(g, w, h, m, [0, cos(a) * h / 2.0, sin(a) * h / 2.0 + 0.002], 0, -a)
	K.plane(g, w, h, K.im("#f4efe4", 0.3), [0, cos(a) * h / 2.0, -sin(a) * h / 2.0], PI, a)
	return g


## Small vase with a cherry-blossom branch (interior, instanced blossoms).
static func sakura_branch(p, K, x: float, y: float, z: float, h: float, rnd, vase = "#6b86a8") -> void:
	K.cyl(p, 0.04, 0.16, K.im(vase, 0.3), [x, y + 0.08, z], 12, null, 0.05)
	var bark = K.im("#6a5448", 0.2)
	var br := [[0, 0, 0.08, h, 0.05], [0.02, h * 0.45, 0.2, h * 0.85, -0.3], [-0.02, h * 0.3, -0.18, h * 0.7, 0.2]]
	for b in br:
		var x0: float = b[0]
		var y0: float = b[1]
		var x1: float = b[2]
		var y1: float = b[3]
		var length := Vector2(x1 - x0, y1 - y0).length()
		var ang := atan2(x1 - x0, y1 - y0)
		K.cyl(p, 0.006, length, bark, [x + (x0 + x1) / 2.0, y + 0.16 + (y0 + y1) / 2.0, z], 5, [0, 0, -ang])
		for k in 11:
			var t := 0.25 + 0.75 * k / 10.0
			var px: float = x + x0 + (x1 - x0) * t + rnd.range(-0.035, 0.035)
			var py: float = y + 0.16 + y0 + (y1 - y0) * t + rnd.range(-0.025, 0.025)
			var pz: float = z + rnd.range(-0.035, 0.035)
			var s: float = 0.024 + rnd.f() * 0.012
			K.I.add("sph", p, [px, py, pz], s, "#f0b0c4" if k % 3 == 0 else "#f6c9d6")
