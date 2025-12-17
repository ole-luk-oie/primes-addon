class_name Packager
extends Object

const PLUGIN_DIR := "res://addons/primes"
const EXPORT_PRESET_PLATFORM := "Web"
const EXPORT_PRESET_PREFERRED := "Primes (Web)"

var tmp_root := OS.get_user_data_dir() + "/primes_export_tmp"


func pack_zip() -> Dictionary:
	var exe := OS.get_executable_path()
	var src_proj := ProjectSettings.globalize_path("res://")

	# --- Recovery lock handling ---------------
	var rec_lock_path := OS.get_user_data_dir().path_join(".recovery_mode_lock")
	var rec_lock_preexisting := FileAccess.file_exists(rec_lock_path)
	# ------------------------------------------

	# 1) Make a temp copy of the project (no editor data, no plugin)
	var tmp_proj := _make_temp_copy(src_proj)
	if tmp_proj == "":
		return {"success": false, "error": "Failed to create temp copy for export"}

	# 2) Ensure a Web export preset exists in the *temp* project only
	var preset_name := _ensure_temp_web_preset(tmp_proj)
	if preset_name.is_empty():
		return {
			"success": false,
			"error":
			(
				"Could not create a temporary Web export preset.\n\n"
				+ "Please ensure Web export templates are installed in your Godot editor\n"
				+ "via Editor → Manage Export Templates, then try again."
			)
		}

	# 3) Export pack using headless Godot on the temp project
	var tmp_out := tmp_proj.path_join("export.zip")

	var args := ["--headless", "--path", tmp_proj, "--export-pack", preset_name, tmp_out]
	var exit_code := OS.execute(exe, args, [], true, false)

	# --- Clear recovery lock if this export created it ---
	if not rec_lock_preexisting and FileAccess.file_exists(rec_lock_path):
		DirAccess.remove_absolute(rec_lock_path)
	# -----------------------------------------------------

	if exit_code != 0:
		_cleanup_temp_for_path(tmp_out)
		return {
			"success": false,
			"error":
			(
				"Export failed (exit code %d).\n\n"
				+ "Most likely the Web export template is not installed or the\n"
				+ (
					"'%s' preset in the temporary project is misconfigured."
					% [exit_code, EXPORT_PRESET_PREFERRED]
				)
			)
		}

	return {"success": true, "zip_path": tmp_out, "preset_name": preset_name}


# === Create/ensure Web preset in TMP PROJECT only ===


func _ensure_temp_web_preset(tmp_proj_abs: String) -> String:
	var cfg := ConfigFile.new()
	var cfg_path := tmp_proj_abs.path_join("export_presets.cfg")

	var err := cfg.load(cfg_path)
	if err != OK:
		# No export_presets in temp project yet → create from scratch.
		cfg = ConfigFile.new()
		var section := "preset.0"
		var name := EXPORT_PRESET_PREFERRED
		_write_web_preset_section(cfg, section, name)

		var save_err := cfg.save(cfg_path)
		if save_err != OK:
			push_warning("Failed to save temp export_presets.cfg: %s" % save_err)
			return ""
		return name

	var any_web_name := ""
	var preferred_found := ""
	var max_index := -1

	for section in cfg.get_sections():
		if not section.begins_with("preset."):
			continue

		# Track highest preset index to append new one if needed
		var idx_str := section.substr("preset.".length())
		if idx_str.is_valid_int():
			var idx := int(idx_str)
			if idx > max_index:
				max_index = idx

		var platform := str(cfg.get_value(section, "platform", ""))
		if platform != EXPORT_PRESET_PLATFORM:
			continue

		var name := str(cfg.get_value(section, "name", ""))
		if any_web_name == "":
			any_web_name = name
		if name == EXPORT_PRESET_PREFERRED:
			preferred_found = name

	# Prefer our own named preset if present
	if preferred_found != "":
		return preferred_found

	# Otherwise reuse the first Web preset if one exists
	if any_web_name != "":
		return any_web_name

	# No Web preset at all in temp project → append one
	var new_index := max_index + 1
	var new_section := "preset.%d" % new_index
	var preset_name := EXPORT_PRESET_PREFERRED

	_write_web_preset_section(cfg, new_section, preset_name)
	var save_err2 := cfg.save(cfg_path)
	if save_err2 != OK:
		push_warning(
			"Failed to save temp export_presets.cfg after adding Web preset: %s" % save_err2
		)
		return ""

	return preset_name


func _write_web_preset_section(cfg: ConfigFile, section: String, preset_name: String) -> void:
	cfg.set_value(section, "name", preset_name)
	cfg.set_value(section, "platform", EXPORT_PRESET_PLATFORM)
	cfg.set_value(section, "runnable", false)
	cfg.set_value(section, "dedicated_server", false)
	cfg.set_value(section, "custom_features", "")
	cfg.set_value(section, "export_filter", "all_resources")
	cfg.set_value(section, "include_filter", "")
	cfg.set_value(section, "exclude_filter", "")
	# cosmetic; we override with --export-pack anyway
	cfg.set_value(section, "export_path", "res://build/%s.pck" % preset_name)

	var opt_section := "%s.options" % section
	cfg.set_value(opt_section, "custom_template/debug", "")
	cfg.set_value(opt_section, "custom_template/release", "")


# === Temp project copy / cleanup ===


func _make_temp_copy(src_proj_abs: String) -> String:
	var stamp := str(Time.get_unix_time_from_system())
	var tmp_base := tmp_root.path_join(stamp)
	if DirAccess.make_dir_recursive_absolute(tmp_base) != OK:
		return ""

	var ok := _copy_dir_recursive(
		src_proj_abs, tmp_base, [".git", ".godot", ".import", "build", "addons"]
	)
	if not ok:
		return ""

	# Remove this plugin from the temp copy so it doesn't get packed.
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
	if r == null:
		return false
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
	if base.begins_with(tmp_root):
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
