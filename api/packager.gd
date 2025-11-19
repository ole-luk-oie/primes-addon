extends Object
class_name Packager

const PLUGIN_DIR = "res://addons/primes"
const STUB_NAME = "__primes_stub.gd"
const ACCEPTED_PLATFORMS = ["Android", "Web"]

var TMP_ROOT = OS.get_user_data_dir() + "/primes_export_tmp"

func pack_zip() -> Dictionary:
	var preset_name := _get_pack_preset()
	if preset_name.is_empty():
		return {
			"success": false,
			"error": "No Android/Web export preset found"
		}
	
	var exe := OS.get_executable_path()
	var src_proj := ProjectSettings.globalize_path("res://")
	
	var tmp_proj := _make_temp_copy(src_proj)
	if tmp_proj == "":
		return {
			"success": false,
			"error": "Failed to create temp copy for export"
		}
	
	var tmp_out := tmp_proj.path_join("export.zip")
	
	var args := [
		"--headless",
		"--path", tmp_proj,
		"--export-pack", preset_name, tmp_out
	]
	var exit_code := OS.execute(exe, args, [], true, false)
	if exit_code != 0:
		_cleanup_temp_for_path(tmp_out)
		return {
			"success": false,
			"error": "Export failed (exit code %d)" % exit_code
		}
	
	return {
		"success": true,
		"zip_path": tmp_out,
		"preset_name": preset_name
	}

func _get_pack_preset() -> String:
	var export_presets := ConfigFile.new()
	var err := export_presets.load("res://export_presets.cfg")
	if err != OK:
		return ""
	
	var android_candidate := ""
	var web_candidate := ""
	for section in export_presets.get_sections():
		if section.begins_with("preset."):
			var preset_name := str(export_presets.get_value(section, "name", ""))
			var platform := str(export_presets.get_value(section, "platform", ""))
			if ACCEPTED_PLATFORMS.has(platform):
				if platform == "Android":
					android_candidate = preset_name
				elif platform == "Web":
					web_candidate = preset_name
	
	# Prefer Android, else Web
	if android_candidate != "":
		return android_candidate
	if web_candidate != "":
		return web_candidate
	return ""

func _make_temp_copy(src_proj_abs: String) -> String:
	var stamp := str(Time.get_unix_time_from_system())
	var tmp_base := TMP_ROOT.path_join(stamp)
	if DirAccess.make_dir_recursive_absolute(tmp_base) != OK:
		return ""
	
	var ok := _copy_dir_recursive(
		src_proj_abs,
		tmp_base,
		[
			".git",
			".godot",
			".import",
			"build",
			"addons"
		]
	)
	if not ok:
		return ""
	
	_delete_dir_recursive(tmp_base.path_join("addons/primes"))
	
	return tmp_base

func _copy_dir_recursive(src_abs: String, dst_abs: String, exclude_top: Array) -> bool:
	var d := DirAccess.open(src_abs)
	if d == null:
		return false
	
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		var src_path := src_abs.path_join(fn)
		var dst_path := dst_abs.path_join(fn)
		var is_dir := d.current_is_dir()
		
		if is_dir:
			if exclude_top.has(fn):
				fn = d.get_next()
				continue
			if fn.begins_with("."):
				fn = d.get_next()
				continue
			
			if DirAccess.make_dir_recursive_absolute(dst_path) != OK:
				return false
			if not _copy_dir_recursive(src_path, dst_path, exclude_top):
				return false
		else:
			if not _copy_file_abs(src_path, dst_path):
				return false
		
		fn = d.get_next()
	d.list_dir_end()
	return true

func _copy_file_abs(src_abs: String, dst_abs: String) -> bool:
	var r := FileAccess.open(src_abs, FileAccess.READ)
	if r == null: return false
	var w := FileAccess.open(dst_abs, FileAccess.WRITE_READ)
	if w == null:
		r.close()
		return false
	w.store_buffer(r.get_buffer(r.get_length()))
	r.close()
	w.close()
	return true

func cleanup_temp(zip_path: String) -> void:
	_cleanup_temp_for_path(zip_path)

func _cleanup_temp_for_path(zip_abs: String) -> void:
	var base := zip_abs.get_base_dir()
	if base.begins_with(TMP_ROOT):
		_delete_dir_recursive(base)

func _delete_dir_recursive(path_abs: String) -> void:
	var d := DirAccess.open(path_abs)
	if d == null:
		return
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		var p := path_abs.path_join(fn)
		var is_dir := d.current_is_dir()
		if is_dir:
			_delete_dir_recursive(p)
			DirAccess.remove_absolute(p)
		else:
			DirAccess.remove_absolute(p)
		fn = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path_abs)
