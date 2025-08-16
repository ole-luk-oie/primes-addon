extends Object

class_name PrimesExporter

const PLUGIN_DIR := "res://addons/primes"
const STUB_NAME := "__primes_stub.gd"
const ANDROID_PLATFORM_NAME := "Android"

var _btn: Button

class ExcludeSelfExportPlugin:
	extends EditorExportPlugin

	var plugin_dir: String

	func _get_name() -> String:
		return "ExcludeSelfExportPlugin"

	func _init(_plugin_dir: String) -> void:
		plugin_dir = _plugin_dir.rstrip("/")

	func _export_file(path: String, type: String, features: PackedStringArray) -> void:
		# Only exclude when the env var is set (i.e. from our button-triggered export).
		if path.begins_with(plugin_dir + "/") or path == plugin_dir or path.contains(STUB_NAME):
			skip()

func get_plugin() -> EditorExportPlugin:
	return ExcludeSelfExportPlugin.new(PLUGIN_DIR)

func pack_zip(log_func: Callable) -> String:
	# 1) Confirm the Android preset exists (by name).
	var preset_name = _get_android_preset(log_func)
	if not preset_name:
		log_func.call("[color=red]Android export preset not found. Create one in Project > Export…[/color]")
		return ""

	log_func.call("Found Android preset: " + preset_name)

	# 2) Ask where to save.
	var save_path := "res://build/export.zip"

	log_func.call("Saving to " + save_path)

	# 3) Build args for a headless export using the current editor binary.
	var exe := OS.get_executable_path()
	log_func.call("Godot binary: " + str(exe))
	var proj_path := ProjectSettings.globalize_path("res://")
	log_func.call("Project path: " + str(proj_path))
	var out_path := ProjectSettings.globalize_path(save_path)
	log_func.call("Output path: " + str(out_path))

	# Use .zip or .pck; Godot picks format from the extension when using --export-pack.
	# (If you prefer .pck, change the default_path above.)
	var args := [
		"--headless",
		"--path", proj_path,
		"--export-pack", preset_name, out_path
	]


	# 5) Run Godot headless to perform the export.
	var exit_code := OS.execute(exe, args, [], true, false)
	if exit_code == 0:
		log_func.call("Exported ZIP to: " + save_path)
		return save_path
	else:
		log_func.call("[color=red]Export failed (exit code %d). Check your preset and templates.[/color]" % exit_code)
		return ""

func _get_android_preset(log_func: Callable):
	# Query through ProjectSettings; presets are stored under "export/presets".
	
	var export_presets := ConfigFile.new()
	var err := export_presets.load("res://export_presets.cfg")
	if err != OK:
		log_func.call("[color=red]Couldn't load export_presets.cfg[/color]")
		return null
	
	# Read the presets
	for section in export_presets.get_sections():
		if section.begins_with("preset."):
			var preset_name = export_presets.get_value(section, "name", "")
			var platform = export_presets.get_value(section, "platform", "")
			if platform == ANDROID_PLATFORM_NAME:
				return preset_name
	return null
