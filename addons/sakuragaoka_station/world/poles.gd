# LOCAL STUB, NOT FOR COMMIT: publishes the original's ctx.services.poles.spans (dumped from node).
extends RefCounted

func build(ctx):
	var a = JSON.parse_string(FileAccess.get_file_as_string("/Users/ernest.lee/.hermes/cache/scratch/chr-oracle/spans.json"))
	var spans := []
	for s in a:
		var pts := []
		for p in s.points:
			pts.append(Vector3(p[0], p[1], p[2]))
		spans.append({"kind": s.kind, "points": pts})
	ctx.services["poles"] = {"spans": spans}
