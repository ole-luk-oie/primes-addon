extends Object
class_name PrimesExporter

const BASE_URL = "https://ole-luk-oie.com/primes"

const AUTH_EMAIL_START_URL  = BASE_URL + "/auth/email/start"
const AUTH_EMAIL_VERIFY_URL = BASE_URL + "/auth/email/verify"
const AUTH_USERNAME_URL     = BASE_URL + "/auth/username"
const AUTH_TOKEN_URL        = BASE_URL + "/auth/token"

const USER_INFO_URL         = BASE_URL + "/dev/info"
const UPLOAD_URL            = BASE_URL + "/dev/upload"
const PRIMES_SET_PUBLIC_URL = BASE_URL + "/dev/set-public"
const EDIT_META_URL         = BASE_URL + "/dev/edit-meta"

const PLUGIN_DIR = "res://addons/primes"
const STUB_NAME = "__primes_stub.gd"
const ACCEPTED_PLATFORMS = ["Android", "Web"]

# Temp workspace root
var TMP_ROOT = OS.get_user_data_dir() + "/primes_export_tmp"

var _btn: Button

class ExcludeSelfExportPlugin:
	extends EditorExportPlugin
	var plugin_dir: String
	func _get_name() -> String: return "ExcludeSelfExportPlugin"
	func _init(_plugin_dir: String) -> void:
		plugin_dir = _plugin_dir.rstrip("/")
	func _export_file(path: String, type: String, features: PackedStringArray) -> void:
		if path.begins_with(plugin_dir + "/") or path == plugin_dir or path.contains(STUB_NAME):
			skip()

func get_plugin() -> EditorExportPlugin:
	return ExcludeSelfExportPlugin.new(PLUGIN_DIR)

# ----------------- auth helpers -----------------

func start_email_sign_in(host: Node, email: String, log_func: Callable) -> Dictionary:
	await log_func.call("Starting email sign-in…")

	var headers := PackedStringArray(["Content-Type: application/json"])
	var payload := { "email": email }
	var json_body := JSON.stringify(payload)

	var http := HTTPRequest.new()
	http.use_threads = true
	host.add_child(http)

	var err := http.request(AUTH_EMAIL_START_URL, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		http.queue_free()
		await log_func.call("[color=red]Failed to contact auth server (start).[/color]")
		return {
			"success": false,
			"error": "request() error %d" % err,
		}

	var result = await http.request_completed
	http.queue_free()

	var transport_status: int = result[0]
	var http_status: int = result[1]
	var raw_body: PackedByteArray = result[3]

	if transport_status != HTTPRequest.RESULT_SUCCESS:
		#await log_func.call("[color=red]Auth request failed (transport %d).[/color]" % transport_status)
		return {
			"success": false,
			"error": "transport %d" % transport_status,
		}

	var body_str := raw_body.get_string_from_utf8()

	if http_status != 200:
		#await log_func.call("[color=red]Auth start HTTP %d:[/color] %s" % [http_status, body_str])
		return {
			"success": false,
			"error": "HTTP %d: %s" % [http_status, body_str],
		}

	var parsed := JSON.parse_string(body_str)
	if typeof(parsed) != TYPE_DICTIONARY:
		await log_func.call("[color=red]Auth start: invalid JSON.[/color]")
		return {
			"success": false,
			"error": "invalid JSON",
		}

	var session_id := int(parsed.get("sessionId", -1))
	if session_id <= 0:
		await log_func.call("[color=red]Auth start: missing sessionId.[/color]")
		return {
			"success": false,
			"error": "missing sessionId",
		}

	#await log_func.call("Verification email sent to [b]%s[/b]. Please check your inbox." % email)

	return {
		"success": true,
		"session_id": session_id,
	}
	
func verify_email_code(host: Node, session_id: int, code: String, log_func: Callable) -> Dictionary:
	if session_id <= 0:
		return {
			"success": false,
			"error": "invalid session id",
		}

	code = code.strip_edges()
	if code.is_empty():
		return {
			"success": false,
			"error": "empty code",
		}

	var headers := PackedStringArray(["Content-Type: application/json"])
	var payload := { "sessionId": session_id, "code": code }
	var json_body := JSON.stringify(payload)

	var http := HTTPRequest.new()
	http.use_threads = true
	host.add_child(http)

	var err := http.request(AUTH_EMAIL_VERIFY_URL, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		http.queue_free()
		await log_func.call("[color=red]Failed to contact auth server (verify).[/color]")
		return {
			"success": false,
			"error": "request() error %d" % err,
		}

	var result = await http.request_completed
	http.queue_free()

	var transport_status: int = result[0]
	var http_status: int = result[1]
	var raw_body: PackedByteArray = result[3]

	if transport_status != HTTPRequest.RESULT_SUCCESS:
		return {
			"success": false,
			"error": "transport %d" % transport_status,
		}

	var body_str := raw_body.get_string_from_utf8()

	if http_status != 200:
		return {
			"success": false,
			"error": "HTTP %d: %s" % [http_status, body_str],
		}

	var parsed := JSON.parse_string(body_str)
	if typeof(parsed) != TYPE_DICTIONARY:
		await log_func.call("[color=red]Verify: invalid JSON.[/color]")
		return {
			"success": false,
			"error": "invalid JSON",
		}

	var user_id := int(parsed.get("userId", -1))
	var username := String(parsed.get("username", ""))
	var needs_username := bool(parsed.get("needsUsername", username == "")) # fallback
	var token : String = parsed.get("token", "")

	if user_id <= 0:
		return {
			"success": false,
			"error": "missing userId",
		}
		
	if token == "":
		return {
			"success": false,
			"error": "missing token",
		}

	await log_func.call(
		"[color=green]Code accepted.[/color] username=%s"
		% [username]
	)

	return {
		"success": true,
		"user_id": user_id,
		"username": username,
		"needs_username": needs_username,
		"token": token
	}
	
func fetch_user_info(host: Node, token: String, log_func: Callable) -> Dictionary:
	if token.is_empty():
		return { "success": false, "error": "no_token" }

	var headers := PackedStringArray([
		"Authorization: Bearer %s" % token
	])

	var http := HTTPRequest.new()
	http.use_threads = true
	host.add_child(http)

	var err := http.request(USER_INFO_URL, headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		await log_func.call("[color=red]Failed to contact server (user info).[/color]")
		return {
			"success": false,
			"error": "request() error %d" % err,
		}

	var result = await http.request_completed
	http.queue_free()

	var transport_status: int = result[0]
	var http_status: int = result[1]
	var raw_body: PackedByteArray = result[3]

	if transport_status != HTTPRequest.RESULT_SUCCESS:
		return {
			"success": false,
			"error": "transport %d" % transport_status,
		}

	var body_str := raw_body.get_string_from_utf8()

	if http_status == 401 or http_status == 403:
		# treat as token expired / invalid
		await log_func.call("[color=orange]Stored token is no longer valid.[/color]")
		return {
			"success": false,
			"error": "token_expired",
		}

	if http_status != 200:
		return {
			"success": false,
			"error": "HTTP %d: %s" % [http_status, body_str],
		}

	var parsed := JSON.parse_string(body_str)
	if typeof(parsed) != TYPE_DICTIONARY:
		await log_func.call("[color=red]User info: invalid JSON.[/color]")
		return {
			"success": false,
			"error": "invalid JSON",
		}
		
	var username := String(parsed.get("username", ""))
	var primes = parsed.get("primes", [])
	
	return {
		"success": true,
		"username": username,
		"primes": primes
	}

func claim_username(host: Node, user_id: int, username: String, log_func: Callable) -> Dictionary:
	if user_id <= 0:
		return {
			"success": false,
			"error": "invalid user id",
		}

	username = username.strip_edges()
	if username.is_empty():
		return {
			"success": false,
			"error": "empty username",
		}

	var headers := PackedStringArray(["Content-Type: application/json"])
	var payload := { "userId": user_id, "username": username }
	var json_body := JSON.stringify(payload)

	var http := HTTPRequest.new()
	http.use_threads = true
	host.add_child(http)

	var err := http.request(AUTH_USERNAME_URL, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		http.queue_free()
		await log_func.call("[color=red]Failed to contact auth server (username).[/color]")
		return {
			"success": false,
			"error": "request() error %d" % err,
		}

	var result = await http.request_completed
	http.queue_free()

	var transport_status: int = result[0]
	var http_status: int = result[1]
	var raw_body: PackedByteArray = result[3]

	if transport_status != HTTPRequest.RESULT_SUCCESS:
		return {
			"success": false,
			"error": "transport %d" % transport_status,
		}

	var body_str := raw_body.get_string_from_utf8()

	if http_status != 200:
		return {
			"success": false,
			"error": "HTTP %d: %s" % [http_status, body_str],
		}

	var parsed := JSON.parse_string(body_str)
	if typeof(parsed) != TYPE_DICTIONARY:
		await log_func.call("[color=red]Username: invalid JSON.[/color]")
		return {
			"success": false,
			"error": "invalid JSON",
		}

	var result_username := String(parsed.get("username", ""))
	if result_username.is_empty():
		return {
			"success": false,
			"error": "missing username",
		}

	await log_func.call(
		"[color=green]Username set:[/color] %s"
		% result_username
	)

	return {
		"success": true,
		"user_id": int(parsed.get("userId", user_id)),
		"username": result_username,
	}

func set_prime_visibility(
	host: Node,
	token: String,
	prime_id: String,
	hidden: bool,
	log_func: Callable
) -> Dictionary:
	var url := "%s?primeId=%s&isPublic=%s" % [
		PRIMES_SET_PUBLIC_URL,
		prime_id.uri_encode(),         # avoid weird chars in query
		"true" if hidden else "false"
	]

	var headers := PackedStringArray([
		"Authorization: Bearer %s" % token
	])

	var http := HTTPRequest.new()
	http.use_threads = true
	host.add_child(http)

	var err := http.request(url, headers, HTTPClient.METHOD_PUT)
	if err != OK:
		http.queue_free()
		await log_func.call("[color=red]Failed to contact server (set-hidden).[/color]")
		return {
			"success": false,
			"error": "request() error %d" % err,
		}

	var result = await http.request_completed
	http.queue_free()

	var transport_status: int = result[0]
	var http_status: int = result[1]
	var raw_body: PackedByteArray = result[3]
	var body_str := raw_body.get_string_from_utf8()

	if transport_status != HTTPRequest.RESULT_SUCCESS:
		return {
			"success": false,
			"error": "transport %d" % transport_status,
		}

	if http_status != 200:
		return {
			"success": false,
			"error": "HTTP %d: %s" % [http_status, body_str],
		}

	# No body expected, just OK
	await log_func.call(
		"[i]Server updated visibility for %s (hidden=%s)[/i]"
		% [prime_id, str(hidden)]
	)

	return { "success": true }

func update_prime_meta(
	host: Node,
	token: String,
	prime_id: String,
	name: String,
	description: String,
	log_func: Callable
) -> Dictionary:
	if prime_id.is_empty():
		return {
			"success": false,
			"error": "missing prime id",
		}

	# local caps (just in case)
	if name.length() > 32:
		name = name.substr(0, 32)
	if description.length() > 255:
		description = description.substr(0, 255)

	var headers := PackedStringArray([
		"Authorization: Bearer %s" % token,
		"Content-Type: application/json"
	])

	var payload := {
		"primeId": prime_id,
		"name": name,
		"description": description,
	}
	var json_body := JSON.stringify(payload)

	var http := HTTPRequest.new()
	http.use_threads = true
	host.add_child(http)

	var err := http.request(EDIT_META_URL, headers, HTTPClient.METHOD_PUT, json_body)
	if err != OK:
		http.queue_free()
		await log_func.call("[color=red]Failed to contact server (edit-meta).[/color]")
		return {
			"success": false,
			"error": "request() error %d" % err,
		}

	var result = await http.request_completed
	http.queue_free()

	var transport_status: int = result[0]
	var http_status: int = result[1]
	var raw_body: PackedByteArray = result[3]
	var body_str := raw_body.get_string_from_utf8()

	if transport_status != HTTPRequest.RESULT_SUCCESS:
		return {
			"success": false,
			"error": "transport %d" % transport_status,
		}

	if http_status != 200 and http_status != 204:
		return {
			"success": false,
			"error": "HTTP %d: %s" % [http_status, body_str],
		}

	# server returns no content, but treat any 200/204 as success
	await log_func.call("[color=green]Updated meta for %s[/color]" % prime_id)
	return { "success": true }


func pack_zip(log_func: Callable) -> String:
	# 1) Pick preset (Android preferred, else Web).
	var preset_name := await _get_pack_preset(log_func)
	if preset_name.is_empty():
		await log_func.call("[color=red]No Android/Web export preset found. Create one in Project > Export…[/color]")
		return ""

	await log_func.call("Using export preset: " + preset_name)

	var exe := OS.get_executable_path()
	var src_proj := ProjectSettings.globalize_path("res://")
	await log_func.call("Godot binary: " + str(exe))
	await log_func.call("Project path: " + str(src_proj))

	# 2) Make a temp copy (exclude heavy/editor dirs and the plugin itself).
	var tmp_proj := await _make_temp_copy(src_proj, log_func)
	if tmp_proj == "":
		await log_func.call("[color=red]Failed to create temp copy for export.[/color]")
		return ""

	# 3) Export pack in the TEMP project
	var tmp_out := tmp_proj.path_join("export.zip")
	await log_func.call("Exporting to temp: " + tmp_out)

	var args := [
		"--headless",
		"--path", tmp_proj,
		"--export-pack", preset_name, tmp_out
	]
	var exit_code := OS.execute(exe, args, [], true, false)
	if exit_code != 0:
		await log_func.call("[color=red]Export failed (exit code %d). Check your preset and templates.[/color]" % exit_code)
		_cleanup_temp_for_path(tmp_proj)
		return ""

	# IMPORTANT: Do NOT delete here; upload will read this file and then clean up.
	return tmp_out  # absolute path

func _get_pack_preset(log_func: Callable) -> String:
	var export_presets := ConfigFile.new()
	var err := export_presets.load("res://export_presets.cfg")
	if err != OK:
		await log_func.call("[color=red]Couldn't load export_presets.cfg[/color]")
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

func upload_zip_with_meta(host: Node, token: String, zip_path: String, author: String, is_public := false,
		name := "", description := "") -> Dictionary:
	var f := FileAccess.open(zip_path, FileAccess.READ)
	if f == null:
		return { "success": false, "error": "Cannot open: " + zip_path }
	var file_buf := f.get_buffer(f.get_length()); f.close()

	var boundary := "----GodotBoundary" + str(Time.get_unix_time_from_system())
	var body := PackedByteArray()

	var version_info = Engine.get_version_info()
	var engine = "godot%s_%s" % [version_info["major"], version_info["minor"]]

	var renderer_name: String = str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"))
	match renderer_name:
		"gl_compatibility":
			engine = "web" + engine
		"forward_plus":
			return { "success": false, "error": "Unsupported renderer '%s' please switch to mobile or compatibility" % renderer_name }
		"mobile":
			pass
		_:
			return { "success": false, "error": "Unsupported renderer '%s' please switch to mobile or compatibility" % renderer_name }

	add_part(body, boundary, "author", author)
	add_part(body, boundary, "engine", engine)
	if not name.is_empty(): add_part(body, boundary, "name", name)
	if not description.is_empty(): add_part(body, boundary, "description", description)
	add_part(body, boundary, "public", str(is_public))

	# File part
	body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
	body.append_array(('Content-Disposition: form-data; name="file"; filename="%s"\r\n' % zip_path.get_file()).to_utf8_buffer())
	body.append_array("Content-Type: application/octet-stream\r\n\r\n".to_utf8_buffer())
	body.append_array(file_buf)
	body.append_array("\r\n".to_utf8_buffer())
	body.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())

	var headers := PackedStringArray([
		"Authorization: Bearer %s" % token,
		"Content-Type: multipart/form-data; boundary=%s" % boundary
		])

	var http := HTTPRequest.new()
	http.use_threads = true
	host.add_child(http)
	var err := http.request_raw(UPLOAD_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		_cleanup_temp_for_path(zip_path) # best-effort cleanup even on failure
		return { "success": false, "error": "Upload failed to initiate: %s" % err }

	var result = await http.request_completed
	http.queue_free()

	# Cleanup the temp workspace now that we're done with the file
	_cleanup_temp_for_path(zip_path)

	if result[0] == HTTPRequest.RESULT_SUCCESS && result[1] == 200:
		return { "success": true, "id": (result[3] as PackedByteArray).get_string_from_utf8() }
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

# ----------------- temp workspace helpers -----------------

func _make_temp_copy(src_proj_abs: String, log_func: Callable) -> String:
	var stamp := str(Time.get_unix_time_from_system())
	var tmp_base := TMP_ROOT.path_join(stamp)
	if DirAccess.make_dir_recursive_absolute(tmp_base) != OK:
		return ""

	await log_func.call("Creating temp copy…")

	var ok := _copy_dir_recursive(
		src_proj_abs,
		tmp_base,
		[
			".git",
			".godot",
			".import",
			"build",
			# exclude the plugin itself so it doesn't get packed
			"addons" # handled specially below
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
			# top-level exclusions
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
			# copy file
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

func _cleanup_temp_for_path(zip_abs: String) -> void:
	# zip_abs looks like TMP_ROOT/<stamp>/export.zip — delete the parent folder
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
