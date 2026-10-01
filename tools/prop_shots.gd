# A photo of every prop, each realized alone the way the station is (CSG, MToon, palette UVs) and
# framed in a three-quarter view, plus a contact sheet of them all. A prop is a top-level object a
# module adds that measures 0.3 to 8 m across; ground, buildings and specks are left out and counted.
#   godot --path . --resolution 768x768 --script tools/prop_shots.gd -- --out=<dir> [--modules=plaza]
extends SceneTree

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const Realize = preload("res://addons/sakuragaoka_station/core/realize.gd")
const THUMB := 192
const COLS := 8

var _out := ""
var _props := []
var _holder: Node3D
var _cam: Camera3D
var _r = null
var _frames := 0
var _thumbs := []
var _left_out := 0


func _initialize() -> void:
	var mods := PackedStringArray(["environment", "station", "plaza", "sakura"])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--modules="):
			mods = PackedStringArray(a.substr(10).split(","))
	DirAccess.make_dir_recursive_absolute(_out)
	var ctx = Ctx.new(1)
	for n in mods:
		var path := "res://addons/sakuragaoka_station/world/%s.gd" % n
		if not ResourceLoader.exists(path):
			print("props: FAIL (no module %s)" % n)
			quit(1)
			return
		var before: int = ctx.static_root.children.size() + ctx.dynamic_root.children.size()
		load(path).new().build(ctx)
		var added: Array = (ctx.static_root.children + ctx.dynamic_root.children).slice(before)
		ctx.scene.update_matrix_world(true)
		var found := []
		for o in added:
			_collect(o, found)
		for i in found.size():
			var o = found[i][0]
			_props.append({"o": o, "name": "%s-%03d%s" % [n, i, ("-" + o.name).validate_filename() if o.name != "" else ""], "box": found[i][1]})
	print("props: %d props, %d objects left out by size" % [_props.size(), _left_out])
	_cam = Camera3D.new()
	_cam.fov = 40.0
	get_root().add_child(_cam)
	_cam.make_current()
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	get_root().add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -ctx.sun_dir, Vector3.UP)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.86, 0.87, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	get_root().add_child(we)
	_next()


func _next() -> void:
	if _holder != null:
		_holder.queue_free()
	if _props.is_empty():
		_sheet()
		quit()
		return
	_holder = Node3D.new()
	get_root().add_child(_holder)
	_r = Realize.new()
	_r.realize_part([_props[0].o], _holder)
	_frames = 0


func _process(_dt: float) -> bool:
	if _r == null:
		return false
	_frames += 1
	if _frames == 2:
		_r.finish()
		var box: AABB = _props[0].box
		var c := box.get_center()
		var d := box.size.length() * 1.6 + 0.4
		_cam.look_at_from_position(c + Vector3(1.0, 0.75, 1.0).normalized() * d, c, Vector3.UP)
	elif _frames == 14:
		var p: Dictionary = _props.pop_front()
		var img := get_root().get_texture().get_image()
		img.save_png(_out.path_join(p.name + ".png"))
		img.resize(THUMB, THUMB)
		_thumbs.append(img)
		_r = null
		_next()
	return false


func _sheet() -> void:
	if _thumbs.is_empty():
		print("props: FAIL (no props)")
		return
	var rows := ceili(_thumbs.size() / float(COLS))
	var sheet := Image.create(COLS * THUMB, rows * THUMB, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(1, 1, 1))
	for i in _thumbs.size():
		var t: Image = _thumbs[i]
		t.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(t, Rect2i(0, 0, THUMB, THUMB), Vector2i((i % COLS) * THUMB, (i / COLS) * THUMB))
	sheet.save_png(_out.path_join("contact-sheet.png"))
	print("props: saved %d photos and the contact sheet in %s" % [_thumbs.size(), _out])


## Props under o: o itself when it measures 0.3 to 8 m, its children when it is larger.
func _collect(o, out: Array) -> void:
	var box = _bounds(o)
	var size: float = box.size.length() if box != null else 0.0
	if size > 8.0 and not o.children.is_empty():
		for c in o.children:
			_collect(c, out)
	elif size >= 0.3 and size <= 8.0:
		out.append([o, box])
	else:
		_left_out += 1


## The world bounds of an object's meshes, or null when it has none.
func _bounds(o):
	var box = null
	var stack := [o]
	while not stack.is_empty():
		var n = stack.pop_back()
		if not n.visible:
			continue
		if n.is_mesh and n.geometry.position() != null and n.geometry.vertex_count() > 0:
			var pos: PackedVector3Array = n.geometry.position().vec3_array()
			var lo := Vector3(INF, INF, INF)
			var hi := -lo
			for p in pos:
				lo = lo.min(p)
				hi = hi.max(p)
			var b: AABB = n.matrix_world * AABB(lo, hi - lo)
			box = b if box == null else box.merge(b)
		stack.append_array(n.children)
	return box
