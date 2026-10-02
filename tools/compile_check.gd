# Compiles every .gd and .sgd the station owns and fails on any parse error or GDScript warning.
# --write-override writes override.cfg raising each warning the editor shows to an error; run that first.
#   godot --headless --path . --script tools/compile_check.gd -- --write-override
#   godot --headless --path . --script tools/compile_check.gd
extends SceneTree

const SKIP := ["res://.godot", "res://addons/godot_sandbox", "res://addons/Godot-MToon-Shader"]
const OVERRIDE := "res://override.cfg"
# Warning kinds the station already carries; any other kind fails the check.
const ALLOWED := [
	"confusable_local_declaration",
	"incompatible_ternary",
	"int_as_enum_without_cast",
	"integer_division",
	"narrowing_conversion",
	"redundant_await",
	"shadowed_global_identifier",
	"shadowed_variable",
	"shadowed_variable_base_class",
	"unused_parameter",
	"unused_variable",
]


func _init() -> void:
	if OS.get_cmdline_user_args().has("--write-override"):
		quit(write_override())
		return
	if not FileAccess.file_exists(OVERRIDE):
		printerr("compile_check: no override.cfg, so warnings would pass; run with --write-override first")
		quit(1)
		return
	var paths: PackedStringArray = []
	collect("res://", paths)
	var failed: PackedStringArray = []
	for path in paths:
		var script: Script = load(path) as Script
		if script == null or not script.can_instantiate():
			failed.append(path)
	print("compile_check: %d scripts, %d failed" % [paths.size(), failed.size()])
	for path in failed:
		print("  FAIL ", path)
	quit(0 if failed.is_empty() and paths.size() > 0 else 1)


func write_override() -> int:
	var cfg := ConfigFile.new()
	cfg.set_value("debug", "gdscript/warnings/enable", true)
	cfg.set_value("debug", "gdscript/warnings/exclude_addons", false)
	var raised := 0
	for prop in ProjectSettings.get_property_list():
		var name: String = prop.name
		if not name.begins_with("debug/gdscript/warnings/") or prop.type != TYPE_INT:
			continue
		if ProjectSettings.get_setting(name) == 1 and not name.get_file() in ALLOWED:
			cfg.set_value("debug", name.trim_prefix("debug/"), 2)
			raised += 1
	print("compile_check: %d warnings raised to errors" % raised)
	return cfg.save(OVERRIDE) if raised > 0 else 1


func collect(dir: String, out: PackedStringArray) -> void:
	for skip in SKIP:
		if dir.trim_suffix("/") == skip:
			return
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in ["gd", "sgd"]:
			out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		collect(dir.path_join(sub), out)
