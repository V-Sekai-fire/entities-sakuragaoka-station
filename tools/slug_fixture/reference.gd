# CPU references for the Slug checks: render.hpp's coverage (Sampler::renderSample, every curve, no
# bands) and stamp layers expanded instance by instance (no cells), with the same antialiasing the
# shader uses, so a GPU pixel can be compared with what the fixture means.
extends RefCounted


## render.hpp Sampler::renderSample at shape-em point (rx, ry), ppe pixels per em along x and y.
static func coverage(curves: Array, rx: float, ry: float, ppe: Vector2) -> float:
	var xcov := 0.0
	var ycov := 0.0
	var xwgt := 0.0
	var ywgt := 0.0
	for c in curves:
		var x1: float = c[0] - rx
		var y1: float = c[1] - ry
		var x2: float = c[2] - rx
		var y2: float = c[3] - ry
		var x3: float = c[4] - rx
		var y3: float = c[5] - ry
		var code := root_code(y1, y2, y3)
		if code != 0:
			var r := solve(x1, y1, x2, y2, x3, y3) * ppe.x
			if code & 1:
				xcov += clampf(r.x + 0.5, 0, 1)
				xwgt = maxf(xwgt, clampf(1.0 - absf(r.x) * 2.0, 0, 1))
			if code & 0x100:
				xcov -= clampf(r.y + 0.5, 0, 1)
				xwgt = maxf(xwgt, clampf(1.0 - absf(r.y) * 2.0, 0, 1))
		code = root_code(x1, x2, x3)
		if code != 0:
			var r := solve(y1, x1, y2, x2, y3, x3) * ppe.y
			if code & 1:
				ycov -= clampf(r.x + 0.5, 0, 1)
				ywgt = maxf(ywgt, clampf(1.0 - absf(r.x) * 2.0, 0, 1))
			if code & 0x100:
				ycov += clampf(r.y + 0.5, 0, 1)
				ywgt = maxf(ywgt, clampf(1.0 - absf(r.y) * 2.0, 0, 1))
	var weighted := absf(xcov * xwgt + ycov * ywgt) / maxf(xwgt + ywgt, 1.0 / 65536.0)
	return clampf(maxf(weighted, minf(absf(xcov), absf(ycov))), 0, 1)


static func root_code(y1: float, y2: float, y3: float) -> int:
	var shift := (1 if y1 < 0.0 else 0) | (2 if y2 < 0.0 else 0) | (4 if y3 < 0.0 else 0)
	return (0x2E74 >> shift) & 0x0101


## _solveHorizPoly; the vertical solve is the same with x and y swapped.
static func solve(x1: float, y1: float, x2: float, y2: float, x3: float, y3: float) -> Vector2:
	var ax := x1 - 2.0 * x2 + x3
	var ay := y1 - 2.0 * y2 + y3
	var bx := x1 - x2
	var by := y1 - y2
	var eps := 1.0 / 65536.0
	if absf(ay) < eps:
		var t := y1 * (0.5 / by) if absf(by) >= eps else 0.0
		var xx := (ax * t - 2.0 * bx) * t + x1
		return Vector2(xx, xx)
	var d := sqrt(maxf(by * by - ay * y1, 0.0))
	var t1 := (by - d) / ay
	var t2 := (by + d) / ay
	return Vector2((ax * t1 - 2.0 * bx) * t1 + x1, (ax * t2 - 2.0 * bx) * t2 + x1)


# ------------------------------------------------------------------------------------ stamps
# An instance here: {"inv": Transform2D (canvas em -> prototype frame), "kind": 0 curve / 1 ellipse
# / 2 rect, "curves": the curve prototype's shape-em curves, "offset": its layer's em offset,
# "color": Color (straight), "grad": null or a linear gradient {"transform": [xx, yx, xy, yy, dx,
# dy], "stops": [{"t", "color"}]} evaluated at the prototype-frame point and times "color",
# "bbox": Rect2 in canvas em (unpadded)}.

## One instance's coverage at canvas em point em; dx, dy: em per screen pixel (as dFdx / dFdy).
static func stamp_coverage(inst: Dictionary, em: Vector2, dx: Vector2, dy: Vector2) -> float:
	var m: Transform2D = inst.inv
	var q: Vector2 = m * em
	var qx: Vector2 = m.basis_xform(dx)
	var qy: Vector2 = m.basis_xform(dy)
	var l := Vector2(maxf(Vector2(qx.x, qy.x).length(), 1e-9), maxf(Vector2(qx.y, qy.y).length(), 1e-9))
	match int(inst.kind):
		2:
			var cx := clampf(q.x / l.x + 0.5, 0, 1) - clampf((q.x - 1.0) / l.x + 0.5, 0, 1)
			var cy := clampf(q.y / l.y + 0.5, 0, 1) - clampf((q.y - 1.0) / l.y + 0.5, 0, 1)
			return cx * cy
		1:
			var r := q.length()
			var n := q / maxf(r, 1e-9)
			var gl := maxf(Vector2(n.dot(qx), n.dot(qy)).length(), 1e-9)
			return clampf(0.5 - (r - 1.0) / gl, 0, 1)
		_:
			var p: Vector2 = q - inst.offset
			var qe := Vector2(absf(qx.x) + absf(qy.x), absf(qx.y) + absf(qy.y))
			return coverage(inst.curves, p.x, p.y, Vector2(1.0 / qe.x, 1.0 / qe.y))


## An instance's screen footprint in px (the shader's fade input): its prototype's extent along
## each prototype axis over that axis' change per pixel, the larger of the two.
static func stamp_footprint(inst: Dictionary, dx: Vector2, dy: Vector2) -> float:
	var m: Transform2D = inst.inv
	var qx: Vector2 = m.basis_xform(dx)
	var qy: Vector2 = m.basis_xform(dy)
	var l := Vector2(maxf(Vector2(qx.x, qy.x).length(), 1e-9), maxf(Vector2(qx.y, qy.y).length(), 1e-9))
	var ext := Vector2(1, 1) if int(inst.kind) == 2 else Vector2(2, 2)
	if int(inst.kind) == 0:
		var lo := Vector2(INF, INF)
		var hi := -lo
		for c in inst.curves:
			for i in 3:
				lo = lo.min(Vector2(c[i * 2], c[i * 2 + 1]))
				hi = hi.max(Vector2(c[i * 2], c[i * 2 + 1]))
		ext = hi - lo
	return maxf(ext.x / l.x, ext.y / l.y)


## Ground truth for one instance over a screen pixel: the fraction of n x n subsamples inside it.
static func stamp_supersampled(inst: Dictionary, em: Vector2, dx: Vector2, dy: Vector2, n: int = 32) -> float:
	var hit := 0
	for i in n:
		for j in n:
			var p: Vector2 = em + dx * ((i + 0.5) / n - 0.5) + dy * ((j + 0.5) / n - 0.5)
			var q: Vector2 = inst.inv * p
			match int(inst.kind):
				2:
					hit += 1 if q.x >= 0.0 and q.x <= 1.0 and q.y >= 0.0 and q.y <= 1.0 else 0
				1:
					hit += 1 if q.length_squared() <= 1.0 else 0
	return float(hit) / (n * n)


## An instance's straight colour at canvas em point em: its colour, times its gradient (in the
## prototype frame, so fixed to the instance) when it has one.
static func stamp_color(inst: Dictionary, em: Vector2) -> Color:
	var col: Color = inst.color
	if inst.get("grad") == null:
		return col
	var q: Vector2 = inst.inv * em
	var m: Array = inst.grad.transform
	var t := clampf(m[0] * q.x + m[2] * q.y + m[4], 0, 1)
	var st: Array = inst.grad.stops
	var g := Color(st[0].color[0], st[0].color[1], st[0].color[2], st[0].color[3])
	for i in range(1, st.size()):
		var c := Color(st[i].color[0], st[i].color[1], st[i].color[2], st[i].color[3])
		if t <= st[i].t:
			var span: float = st[i].t - st[i - 1].t
			g = g.lerp(c, (t - st[i - 1].t) / span if span > 1e-9 else 0.0)
			break
		g = c
	return g * col


## Source-over a straight colour at coverage cov onto premultiplied acc.
static func over(acc: Color, col: Color, cov: float) -> Color:
	var a := col.a * cov
	return Color(col.r * a + acc.r * (1 - a), col.g * a + acc.g * (1 - a), col.b * a + acc.b * (1 - a), a + acc.a * (1 - a))


## A stamp layer alone (premultiplied, over transparent) on a size x size image of the canvas em
## square [0, 1]^2 (pixel (x, y) at em ((x + 0.5) / size, (y + 0.5) / size)), every instance in
## paint order over its padded bbox. Returns a PackedColorArray, row-major.
static func raster(insts: Array, size: int) -> PackedColorArray:
	var img := PackedColorArray()
	img.resize(size * size)
	img.fill(Color(0, 0, 0, 0))
	var dx := Vector2(1.0 / size, 0)
	var dy := Vector2(0, 1.0 / size)
	for inst in insts:
		var b: Rect2 = inst.bbox
		var x0 := clampi(floori(b.position.x * size) - 2, 0, size - 1)
		var x1 := clampi(ceili(b.end.x * size) + 2, 0, size - 1)
		var y0 := clampi(floori(b.position.y * size) - 2, 0, size - 1)
		var y1 := clampi(ceili(b.end.y * size) + 2, 0, size - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var em := Vector2((x + 0.5) / size, (y + 0.5) / size)
				var cov := stamp_coverage(inst, em, dx, dy)
				if cov > 0.0:
					img[y * size + x] = over(img[y * size + x], stamp_color(inst, em), cov)
	return img
