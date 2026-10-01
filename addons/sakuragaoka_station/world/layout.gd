# WORLD LAYOUT CONTRACT, src/world/layout.js: the single source of truth every module shares.
# Units: metres. +Y up. +X east, -X west, -Z north, +Z south. A model's front is its local +Z;
# rot_y follows three.js (0 faces +Z south, PI faces -Z north, +PI/2 faces +X east).
# Built per run so a control can drop a lot before anything derived from LOTS is computed.
extends RefCounted

var NAMES := {
	"company": "桜川電鉄", "companyEn": "Sakuragawa Railway", "line": "桜川線", "lineEn": "Sakuragawa Line",
	"lineColor": "#ef9fbe", "lineColorDeep": "#d9718f",
	"station": "桜ヶ丘", "stationKana": "さくらがおか", "stationEn": "Sakuragaoka", "stationNo": "SK07",
	"prev": {"kanji": "花見台", "kana": "はなみだい", "en": "Hanamidai", "no": "SK06", "dir": "west"},
	"next": {"kanji": "春日野", "kana": "かすがの", "en": "Kasugano", "no": "SK08", "dir": "east"},
	"town": "桜ヶ丘町", "shoppingStreet": "桜ヶ丘駅前商店街",
}

var WORLD := {
	"play": {"x0": -92.0, "x1": 92.0, "z0": -97.0, "z1": 128.0},
	"visual": {"x0": -700.0, "x1": 700.0, "z0": -900.0, "z1": 700.0},
}

var RAIL := {
	"zA": -41.0, "zB": -45.0, "gauge": 1.067, "railTopY": 0.15, "railH": 0.15, "sleeperTopY": 0.0,
	"ballastTopY": -0.02, "groundY": -0.30, "corridorZ0": -52.0, "corridorZ1": -34.0,
	"xMin": -420.0, "xMax": 420.0, "contactWireY": 5.15,
}

var PLATFORM := {
	"y": 1.25,
	"south": {"x0": -7.0, "x1": 40.0, "z0": -39.5, "z1": -35.5, "edgeZ": -39.5},
	"north": {"x0": -7.0, "x1": 40.0, "z0": -50.5, "z1": -46.5, "edgeZ": -46.5},
	"rampX0": 40.0, "rampX1": 46.0,
	"walkCrossing": {"x0": 46.0, "x1": 48.5},
	"benchB1": {"x": 18.0, "z": -36.15, "rotY": PI},
}

var STATION := {
	"x0": -4.0, "x1": 12.0, "z0": -35.5, "z1": -25.0,
	"floorY": 1.25,
	"entrance": {"x": 4.0, "z": -25.0},
	"forecourt": {"x0": -4.0, "x1": 14.0, "z0": -25.0, "z1": -20.5},
	"sideYard": {"x0": 12.0, "x1": 27.0, "z0": -35.5, "z1": -25.0},
	"westYard": {"x0": -9.25, "x1": -4.0, "z0": -34.0, "z1": -25.0},
}

var TRAIN := {
	"cars": 2, "carLen": 18.0, "width": 2.8,
	"floorY": 0.15 + 1.15, "roofY": 0.15 + 3.65,
	"stopCenterX": 17.0,
	"doorOffsets": [-6.0, 0.0, 6.0],
	"doorW": 1.3,
	"period": 120.0,
}
var TRAIN_DOORS_X: Array = []

var SCHEDULE := {
	"A": {"stopped": [0, 48], "doors": [2, 44], "departMelody": 36, "depart": 48, "arriveFromEast": [100, 120]},
	"B": {"enterFromWest": 4, "passCrossing": [20, 26], "stop": 32, "doors": [34, 70], "departMelody": 64, "depart": 76},
}

var BIKE := {"length": 1.75, "wheelR": 0.33, "wheelbase": 1.08, "handlebar": {"y": 1.02, "z": 0.50, "halfW": 0.28},
	"saddle": {"y": 0.86, "z": -0.22}, "basket": {"y": 0.92, "z": 0.72}}

var CROSSING := {
	"x": -12.0, "roadHalfW": 2.75,
	"deckZ0": -47.6, "deckZ1": -38.4,
	"zone": {"x0": -17.0, "x1": -7.0, "z0": -52.0, "z1": -34.0},
	"stopLineSouthZ": -35.3, "stopLineNorthZ": -50.7,
}

var STREET := {"halfW": 3.0, "sideW": 1.6, "lotOffset": 4.8, "lotDepth": 14.0, "z0": 1.0, "z1": 130.0}

var ROADS := {
	"R1": {"name": "駅前商店街 (main street)", "halfW": 3.0, "kind": "main"},
	"R2": {"name": "踏切道 (crossing road)", "halfW": 2.75, "kind": "local", "x": -12.0, "z0": -88.0, "z1": -5.0},
	"R3": {"name": "駅前通り (station-front cross street)", "halfW": 3.0, "kind": "local", "z": -2.0, "x0": -95.0, "x1": 95.0},
	"R4": {"name": "線路北の道 (north lane along tracks)", "halfW": 2.0, "kind": "lane", "z": -55.5, "x0": -95.0, "x1": 95.0},
	"R6": {"name": "住宅街の路地 (residential alley)", "halfW": 1.5, "kind": "lane", "z": -71.0, "x0": -85.0, "x1": 85.0},
	"R5": {"name": "河川敷の堤防道 (levee-top path)", "halfW": 1.5, "kind": "path", "z": -93.0, "x0": -130.0, "x1": 130.0, "y": 3.2},
}

var PLAZA := {
	"x0": -9.25, "x1": 26.0, "z0": -25.0, "z1": -5.0,
	"tree": {"x": -3.0, "z": -14.0, "benchR": 2.3},
	"bikeRows": [
		{"z": -10.0, "x0": 16.5, "x1": 25.0, "step": 0.75, "rotY": PI},
		{"z": -14.5, "x0": 16.5, "x1": 25.0, "step": 0.75, "rotY": PI},
	],
	"busStop": {"x": 8.0, "z": -5.9},
	"taxiStand": {"x": -6.0, "z": -5.9},
}

var LOTS := [
	{"id": "W1", "side": -1, "z0": 2.5, "z1": 15.5, "owner": "shopsA", "kind": "konbini"},
	{"id": "W2", "side": -1, "z0": 15.5, "z1": 22.5, "owner": "shopsA", "kind": "flower"},
	{"id": "W3", "side": -1, "z0": 22.5, "z1": 31.5, "owner": "houses", "kind": "house-garden"},
	{"id": "W4", "side": -1, "z0": 31.5, "z1": 40.0, "owner": "shopsA", "kind": "bookstore"},
	{"id": "W5", "side": -1, "z0": 40.0, "z1": 49.0, "owner": "houses", "kind": "house"},
	{"id": "W6", "side": -1, "z0": 49.0, "z1": 58.0, "owner": "shopsB", "kind": "bicycle"},
	{"id": "W7", "side": -1, "z0": 58.0, "z1": 68.0, "owner": "houses", "kind": "house"},
	{"id": "W8", "side": -1, "z0": 68.0, "z1": 78.0, "owner": "houses", "kind": "house"},
	{"id": "W9", "side": -1, "z0": 78.0, "z1": 88.5, "owner": "houses", "kind": "house"},
	{"id": "W10", "side": -1, "z0": 88.5, "z1": 98.0, "owner": "houses", "kind": "house"},
	{"id": "W11", "side": -1, "z0": 98.0, "z1": 108.0, "owner": "houses", "kind": "house"},
	{"id": "W12", "side": -1, "z0": 108.0, "z1": 118.0, "owner": "houses", "kind": "house"},
	{"id": "W13", "side": -1, "z0": 118.0, "z1": 128.0, "owner": "houses", "kind": "house"},
	{"id": "E1", "side": 1, "z0": 2.5, "z1": 14.5, "owner": "shopsA", "kind": "cafe"},
	{"id": "E2", "side": 1, "z0": 14.5, "z1": 22.0, "owner": "shopsB", "kind": "wagashi"},
	{"id": "E3", "side": 1, "z0": 22.0, "z1": 30.5, "owner": "shopsB", "kind": "general"},
	{"id": "E4", "side": 1, "z0": 30.5, "z1": 39.0, "owner": "houses", "kind": "house"},
	{"id": "E5", "side": 1, "z0": 39.0, "z1": 47.5, "owner": "shopsB", "kind": "ramen"},
	{"id": "E6", "side": 1, "z0": 47.5, "z1": 56.0, "owner": "props", "kind": "shrine"},
	{"id": "E7", "side": 1, "z0": 56.0, "z1": 66.0, "owner": "houses", "kind": "house"},
	{"id": "E8", "side": 1, "z0": 66.0, "z1": 76.0, "owner": "houses", "kind": "house"},
	{"id": "E9", "side": 1, "z0": 76.0, "z1": 86.5, "owner": "houses", "kind": "house"},
	{"id": "E10", "side": 1, "z0": 86.5, "z1": 97.0, "owner": "houses", "kind": "house"},
	{"id": "E11", "side": 1, "z0": 97.0, "z1": 107.0, "owner": "houses", "kind": "house"},
	{"id": "E12", "side": 1, "z0": 107.0, "z1": 117.0, "owner": "houses", "kind": "house"},
	{"id": "E13", "side": 1, "z0": 117.0, "z1": 128.0, "owner": "houses", "kind": "house"},
]

var BLOCKS := [
	{"id": "NW", "x0": -62.0, "x1": -15.5, "z0": -33.5, "z1": -5.8, "front": ["S", "E"]},
	{"id": "NE", "x0": 27.0, "x1": 62.0, "z0": -33.5, "z1": -5.8, "front": ["S", "W"]},
	{"id": "SWB", "x0": -62.0, "x1": -19.5, "z0": 2.6, "z1": 128.0, "front": ["S", "E"]},
	{"id": "SEB", "x0": 19.5, "x1": 62.0, "z0": 2.6, "z1": 128.0, "front": ["S", "W"]},
	{"id": "N1W", "x0": -85.0, "x1": -15.5, "z0": -69.3, "z1": -57.9, "front": ["S"]},
	{"id": "N1E", "x0": -8.5, "x1": 85.0, "z0": -69.3, "z1": -57.9, "front": ["S"]},
	{"id": "N2W", "x0": -85.0, "x1": -15.5, "z0": -83.5, "z1": -72.7, "front": ["S"]},
	{"id": "N2E", "x0": -8.5, "x1": 85.0, "z0": -83.5, "z1": -72.7, "front": ["S"]},
]

var FAR_TOWN := [
	{"x0": -260.0, "x1": -95.0, "z0": -86.0, "z1": 200.0}, {"x0": 95.0, "x1": 260.0, "z0": -86.0, "z1": 200.0},
	{"x0": -95.0, "x1": 95.0, "z0": 131.0, "z1": 240.0},
]

var RIVER := {"z0": -101.0, "z1": -116.0, "waterY": -0.45, "flowDir": 1}

var POLE_RUNS := {}

var VENDING := [
	{"id": "V1a", "x": 14.65, "z": -24.45, "rotY": 0.0},
	{"id": "V1b", "x": 15.75, "z": -24.45, "rotY": 0.0},
	{"id": "V2", "x": 30.0, "z": -35.95, "rotY": PI, "y": 1.25},
	{"id": "V3a", "x": -5.3, "z": 13.9, "rotY": PI / 2},
	{"id": "V3b", "x": -5.3, "z": 12.8, "rotY": PI / 2},
	{"id": "V4", "x": -8.7, "z": -58.6, "rotY": -PI / 2},
	{"id": "V5", "x": -16.3, "z": -30.8, "rotY": PI / 2},
]

var SPOTS := {
	"crossingGirlBike": {"x": -10.4, "z": -34.1, "rotY": PI},
	"crossingGirl": {"x": -10.95, "z": -34.2, "rotY": PI},
	"crossingCar": {"x": -10.6, "z": -53.2, "rotY": 0.0},
	"crossingPedestrians": {"x": -13.8, "z": -34.6},
	"plazaStudents": {"x": -1.0, "z": -11.4},
	"treeGirl": {"x": -5.4, "z": -11.6, "rotY": 2.6},
	"vendingBoy": {"x": 14.65, "z": -23.55, "rotY": PI},
	"cafeBoard": {"x": 4.35, "z": 5.2},
	"cafeStaff": {"x": 4.9, "z": 5.9, "rotY": -PI / 2},
	"elderly": {"path": [{"x": 3.9, "z": 16.0}, {"x": 3.9, "z": 27.0}]},
	"stationStaffGate": {"x": 6.0, "z": -30.0},
	"stationStaffPlatform": {"x": 10.0, "z": -37.2, "y": 1.25},
	"taxi": {"x": -6.2, "z": -3.4, "rotY": PI / 2},
	"whiteVan": {"x": -2.3, "z": 72.0, "rotY": PI},
	"keiCar": {"x": 22.0, "z": -0.3, "rotY": -PI / 2},
	"plazaBenchSeatY": 0.45,
	"calicoCat": {"x": -1.25, "z": -15.5, "y": 0.45, "rotY": 2.2},
	"w3Sakura": {"x": -7.0, "z": 25.2},
	"w3Wall": {"lx0": -4.3, "lx1": 4.3, "lz": -0.15, "h": 1.3},
	"catWhite": {"x": -4.95, "z": 29.6, "onW3Wall": true, "rotY": PI / 2},
	"konbiniBikes": [{"x": -5.9, "z": 4.4, "rotY": -PI / 2}, {"x": -5.9, "z": 5.15, "rotY": -PI / 2}],
	"bookstoreBike": {"x": -5.35, "z": 38.6, "rotY": PI},
	"v5Bench": {"x": -16.35, "z": -28.9, "rotY": PI / 2, "seatY": 0.44, "len": 1.5},
	"blackCat": {"x": -16.0, "z": -27.6, "rotY": 1.2},
	"gashapon": {"x": 5.3, "z": 29.3, "rotY": -PI / 2, "count": 3},
	"disasterCabinet": {"x": 29.5, "z": -7.2, "rotY": 0.0},
}

var AREAS := [
	{"name": "桜ヶ丘駅 1番線ホーム", "x0": -7.0, "x1": 46.0, "z0": -40.0, "z1": -35.5},
	{"name": "桜ヶ丘駅 2番線ホーム", "x0": -7.0, "x1": 46.0, "z0": -51.0, "z1": -46.0},
	{"name": "桜ヶ丘駅", "x0": -4.0, "x1": 12.0, "z0": -35.5, "z1": -25.0},
	{"name": "桜川線 第一踏切", "x0": -17.0, "x1": -7.0, "z0": -52.0, "z1": -34.0},
	{"name": "駅前広場", "x0": -9.25, "x1": 26.0, "z0": -25.0, "z1": -5.0},
	{"name": "駅前通り", "x0": -95.0, "x1": 95.0, "z0": -5.5, "z1": 1.5},
	{"name": "桜ヶ丘駅前商店街", "x0": -12.0, "x1": 14.0, "z0": 1.5, "z1": 60.0},
	{"name": "桜ヶ丘 住宅街", "x0": -95.0, "x1": 95.0, "z0": 60.0, "z1": 130.0},
	{"name": "河川敷 · 桜川堤", "x0": -130.0, "x1": 130.0, "z0": -120.0, "z1": -84.0},
	{"name": "線路北の住宅街", "x0": -95.0, "x1": 95.0, "z0": -84.0, "z1": -52.0},
	{"name": "桜ヶ丘町", "x0": -999.0, "x1": 999.0, "z0": -999.0, "z1": 999.0},
]

var HERO := {"x": 1.6, "z": 34.0, "yaw": 4.0, "pitch": 2.0}
var SUN_DIR := [-0.776, 0.517, 0.362]


func _init(drop_lot: String = "") -> void:
	if drop_lot != "":
		var i := LOTS.find_custom(func(l): return l.id == drop_lot)
		assert(i >= 0, "no lot " + drop_lot)
		LOTS.remove_at(i)
	for s in [-1, 1]:
		for o in TRAIN.doorOffsets:
			TRAIN_DOORS_X.append(TRAIN.stopCenterX + s * TRAIN.carLen / 2.0 + o)
	TRAIN_DOORS_X.sort()
	POLE_RUNS = {
		"R1W": _main_run(-1, [8, 38, 68, 98, 126]),
		"R1E": _main_run(1, [23, 53, 83, 113]),
		"R3S": [-78, -52, -26, 22, 46, 72].map(func(x): return {"x": float(x), "z": 1.45}),
		"R2W": [{"x": -15.2, "z": -20.0}, {"x": -15.2, "z": -61.0}, {"x": -15.2, "z": -79.0}],
		"R4S": [-78, -48, -20, 18, 48, 78].map(func(x): return {"x": float(x), "z": -53.05}),
		"R6S": [-62, -32, 4, 34, 64].map(func(x): return {"x": float(x), "z": -69.1}),
	}
	var w6 = lot_by_id("W6")
	if w6 != null:
		SPOTS.bikeShopBikes = [-3.2, -2.4, -1.6].map(func(lx):
			var p := lot_to_world(w6, lx, -1.0)
			return {"x": p.x, "z": p.z, "rotY": lot_frame(w6).rotY})
	var e6 = lot_by_id("E6")
	if e6 != null:
		SPOTS.shrineSakura = lot_to_world(e6, -2.5, -6.5)


func _main_run(side: int, zs: Array) -> Array:
	return zs.map(func(z):
		var f := street_frame(float(z), side, 3.45)
		return {"x": f.x, "z": f.z})


## JavaScript's smoothstep from layout.js: also defined for a > b.
static func sstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Main street centreline x at z: straight near the station, a gentle curve for z > 28.
func street_center_x(z: float) -> float:
	if z <= 28.0:
		return 0.0
	var t := clampf((z - 28.0) / 100.0, 0.0, 1.0)
	return 7.0 * (1.0 - cos(PI * t)) / 2.0


func street_slope_x(z: float) -> float:
	if z <= 28.0 or z >= 128.0:
		return 0.0
	var t := (z - 28.0) / 100.0
	return 7.0 * PI * sin(PI * t) / 200.0


## Frame on the main street at z: {x, z, y, rotY, tx, tz}; for side +-1 local +Z faces the
## centreline, and (tx, tz) is the unit tangent pointing north.
func street_frame(z: float, side: int = 0, offset: float = 0.0) -> Dictionary:
	var cx := street_center_x(z)
	var sx := street_slope_x(z)
	var tx := -sx
	var tz := -1.0
	var tl := sqrt(tx * tx + tz * tz)
	tx /= tl
	tz /= tl
	var nx := -tz
	var nz := tx
	var x := cx + nx * offset * side
	var zz := z + nz * offset * side
	var fx := nx if side <= 0 else -nx
	var fz := nz if side <= 0 else -nz
	var rot_y := atan2(fx, fz)
	return {"x": x, "z": zz, "y": height_at(x, zz), "rotY": rot_y, "tx": tx, "tz": tz}


func lot_by_id(id: String):
	for l in LOTS:
		if l.id == id:
			return l
	return null


func lot_frame(lot: Dictionary) -> Dictionary:
	var zm: float = (lot.z0 + lot.z1) / 2.0
	var f := street_frame(zm, lot.side, STREET.lotOffset)
	return {"x": f.x, "y": f.y, "z": f.z, "rotY": f.rotY, "w": lot.z1 - lot.z0, "depth": STREET.lotDepth}


func lot_to_world(lot: Dictionary, lx: float, lz: float) -> Dictionary:
	var f := lot_frame(lot)
	var c := cos(f.rotY)
	var s := sin(f.rotY)
	return {"x": f.x + lx * c + lz * s, "z": f.z - lx * s + lz * c}


## Ground height (m) at (x, z); everything sits on this.
func height_at(x: float, z: float) -> float:
	var h: float
	if z <= 0.0:
		h = 0.0
	elif z < 10.0:
		h = 0.028 * z * z / 20.0
	else:
		h = 0.028 * (z - 5.0)
	if z < -33.0 and z > -53.0:
		var inner := sstep(-33.0, -34.0, z) * sstep(-53.0, -52.0, z)
		var hc := lerpf(0.0, RAIL.groundY, inner)
		var dx := absf(x - CROSSING.x)
		if dx < CROSSING.roadHalfW + 1.5:
			var wx := 1.0 - sstep(CROSSING.roadHalfW, CROSSING.roadHalfW + 1.5, dx)
			var along := sstep(-35.4, -38.4, z) * sstep(-50.6, -47.6, z)
			hc = lerpf(hc, lerpf(0.0, RAIL.railTopY, along), wx)
		h = hc
	if z < -84.0:
		if z >= -91.5:
			h = 3.2 * sstep(-84.0, -91.5, z)
		elif z >= -94.5:
			h = 3.2
		elif z >= -99.0:
			h = lerpf(3.2, 0.2, sstep(-94.5, -99.0, z))
		elif z >= -101.0:
			h = lerpf(0.2, -1.2, sstep(-99.0, -101.0, z))
		elif z >= -116.0:
			h = -1.2
		elif z >= -119.0:
			h = lerpf(-1.2, 0.6, sstep(-116.0, -119.0, z))
		else:
			h = 0.6 + 0.02 * (-119.0 - z)
	return h
