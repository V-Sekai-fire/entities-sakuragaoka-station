extends SceneTree
const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const G = preload("res://addons/sakuragaoka_station/core/geo.gd")

func make(c: Array) -> T.Geometry:
	var k: String = c[0]
	var a = c[1]
	match k:
		"box": return G.box(a[0], a[1], a[2], a[3], a[4], a[5])
		"plane": return G.plane(a[0], a[1], a[2], a[3])
		"circle": return G.circle(a[0], a[1], a[2], a[3])
		"cylinder": return G.cylinder(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7])
		"sphere": return G.sphere(a[0], a[1], a[2], a[3], a[4], a[5], a[6])
		"torus": return G.torus(a[0], a[1], a[2], a[3], a[4])
		"icosahedron": return G.icosahedron(a[0], a[1])
		"lathe":
			var pts := []
			for p in a[0]: pts.append(Vector2(p[0], p[1]))
			return G.lathe(pts, a[1], a[2], a[3])
		"rounded_box": return G.rounded_box(a[0], a[1], a[2], a[3], a[4])
		"extrude":
			var g := G.extrude(a[0], a[1], a[2])
			return g
		"extrude_spline":
			var pts: Array = a[0].duplicate()
			pts.append(a[0][0])
			var sp := G.spline_points(pts, a[1])
			return G.extrude_shape(G.shape(sp), {"depth": 0.24, "bevelEnabled": true, "bevelThickness": 0.06, "bevelSize": 0.05, "bevelSegments": 4})
		"shape_geometry": return G.shape_geometry(G.shape(a[0], a[1]), 24)
		"tube":
			var pts := []
			for p in a[0]: pts.append(Vector3(p[0], p[1], p[2]))
			return G.tube_catmull(pts, true, a[1], a[2], a[3], true)
		"merge_vertices":
			var g := make([a[0], a[1]])
			g.delete_attribute("uv")
			g.delete_attribute("normal")
			return G.merge_vertices(g, a[2])
		"merge_geometries":
			return G.merge_geometries([G.box(1, 1, 1), G.box(2, 1, 1, 2, 1, 1).translate(3, 0, 0), G.box(1, 3, 1)], false)
	return null

## The three.js generators' output for each case (tools/gencheck_expected.txt, from three.js r170)
## against the port's: vertices, triangles, bounds and position sums. --control=box2 builds the second
## box with one width segment too many and must FAIL.
func _initialize() -> void:
	var cases = JSON.parse_string(FileAccess.get_file_as_string("res://tools/gencheck_cases.json"))
	var expected := FileAccess.get_file_as_string("res://tools/gencheck_expected.txt").strip_edges().split("\n")
	var control := "--control=box2" in OS.get_cmdline_user_args()
	if control:
		cases[1][1][3] = 3
	var fails := 0
	for ci in cases.size():
		var c = cases[ci]
		var g := make(c)
		g.compute_bounding_box()
		var p := g.position()
		var s := Vector3.ZERO
		var sx := 0.0; var sy := 0.0; var sz := 0.0
		for i in p.count():
			sx += p.get_x(i); sy += p.get_y(i); sz += p.get_z(i)
		var b: AABB = g.bounding_box
		var e := b.end
		var tri = g.triangle_count()
		var line := "%s | %d | %s | %.4f,%.4f,%.4f,%.4f,%.4f,%.4f | %.3f,%.3f,%.3f" % [c[0], p.count(), str(int(tri)) if tri == int(tri) else str(tri), b.position.x, b.position.y, b.position.z, e.x, e.y, e.z, sx, sy, sz]
		line = line.replace("-0.000", "0.000")
		if line != expected[ci].replace("-0.000", "0.000"):
			fails += 1
			print("MISMATCH %s\n  got      %s\n  three.js %s" % [c[0], line, expected[ci]])
	print("RESULT: %s (%d cases, %d mismatched)%s" % ["PASS" if fails == 0 else "FAIL", cases.size(), fails, " control box2" if control else ""])
	quit(1 if fails else 0)
