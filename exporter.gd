extends Object

class_name PrimesExporter

const UPLOAD_URL = "https://ole-luk-oie.com/primes/upload"
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


func upload_zip_with_meta(host: Node, zip_path: String, author: String, is_public := false, 
							name := "", description := "") -> Dictionary:
	var f := FileAccess.open(zip_path, FileAccess.READ)
	if f == null:
		return { "ok": false, "error": "Cannot open: " + zip_path }
	var file_buf := f.get_buffer(f.get_length()); f.close()

	var boundary := "----GodotBoundary" + str(Time.get_unix_time_from_system())
	var body := PackedByteArray()

	var version_info = Engine.get_version_info()

	add_part(body, boundary, "author", author)
	add_part(body, boundary, "engine", "godot%s_%s" % [version_info["major"], version_info["minor"]] )
	if not name.is_empty(): add_part(body, boundary, "name", name)
	if not description.is_empty(): add_part(body, boundary, "description", description)

	# File part
	body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
	body.append_array(('Content-Disposition: form-data; name="file"; filename="%s"\r\n' % zip_path.get_file()).to_utf8_buffer())
	body.append_array("Content-Type: application/octet-stream\r\n\r\n".to_utf8_buffer())
	body.append_array(file_buf)
	body.append_array("\r\n".to_utf8_buffer())
	body.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())

	var headers := PackedStringArray(["Content-Type: multipart/form-data; boundary=%s" % boundary])

	var http := HTTPRequest.new()
	host.add_child(http)
	var err := http.request_raw(UPLOAD_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return { "success": false, "error": "Upload failed to initiate: %s" % err }
	var result = await http.request_completed
	http.queue_free()

	if result[0] == HTTPRequest.RESULT_SUCCESS && result[1] == 200:
		return {
			"success": true,
			"id": (result[3] as PackedByteArray).get_string_from_utf8()
		}
	else:
		return {
			"success": false,
			"error": "Upload falied with result %s, status %s, body %s" % [result[0], result[1], result[3].get_string_from_utf8()]
		}

func add_part(body: PackedByteArray, boundary: String, name: String, value: String) -> void:
	body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
	body.append_array(('Content-Disposition: form-data; name="%s"\r\n\r\n' % name).to_utf8_buffer())
	body.append_array(value.to_utf8_buffer())
	body.append_array("\r\n".to_utf8_buffer())
