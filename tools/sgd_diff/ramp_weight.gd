# The scalar core of slug_kernels.sgd's ramp_row / _paint_colour (stop search, weight) and
# pack_layers' texel offsets, for the compiler's IR-interpreter-vs-RISC-V differential test
# (test_differential "one program named by GDSC_DIFF_FILE"): no containers, so both runs can
# execute it. test() folds every intermediate into one checksum.
func weight(t: float, a: float, b: float) -> float:
	var w := 0.0
	if b - a > 1e-9:
		w = (t - a) / (b - a)
	return w

func test():
	var acc := 0.0
	var stops := 5
	for x in 512:
		var t := float(x) / 511
		t = clampf(t, 0.0, 1.0)
		for i in range(1, stops):
			var a := float(i - 1) / (stops - 1) * 0.9
			var b := float(i) / (stops - 1) * 0.9
			if t <= b:
				acc += weight(t, a, b) * (i + 1)
				break
	var offs := 0
	for li in 1000:
		var s := li * 24
		var d := li * 8 * 4
		offs = (offs * 31 + s + d + 14) % 1000003
	return acc + offs
