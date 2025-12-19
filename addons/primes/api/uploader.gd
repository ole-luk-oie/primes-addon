class_name Uploader
extends Object

const INIT_URL := PrimesConfig.BASE_URL + "/uploads/init"
const COMPLETE_URL := PrimesConfig.BASE_URL + "/uploads/complete"

# Public API
func upload_zip(host: Node, token: String, zip_path: String, is_public := false, name := "", description := "") -> Dictionary:
	var file_buf_res := _read_file(zip_path)
	if not file_buf_res.success:
		return file_buf_res
	var file_buf: PackedByteArray = file_buf_res.bytes
	var size_bytes := file_buf.size()

	if size_bytes > PrimesConfig.MAX_ZIP_BYTES:
		return {"success": false, "error": "Zip too large (max 32MB)"}

	var engine_result := _get_engine_string()
	if not engine_result.success:
		return engine_result
	var engine : String = engine_result.engine

	# Compute sha256 hex for the file (matches server expectation)
	var sha256 := _sha256_hex(file_buf)
	if sha256.is_empty():
		return {"success": false, "error": "Failed to compute SHA-256"}

	# 1) init
	var init_payload := {
		"engine": engine,
		"name": name,
		"description": description,
		"isPublic": is_public,
		"sizeBytes": size_bytes,
		"sha256": sha256
	}

	var init_resp := await _http_json(host, INIT_URL, token, HTTPClient.METHOD_POST, init_payload)
	if not init_resp.success:
		return init_resp

	var init_body = init_resp.body
	if typeof(init_body) != TYPE_DICTIONARY:
		return {"success": false, "error": "Init returned non-object JSON"}

	if not init_body.has("id") or not init_body.has("uploadUrl"):
		# Future: if you later return an "upload" object instead, handle it here.
		return {"success": false, "error": "Init response missing id/uploadUrl: %s" % str(init_body)}

	var id: String = str(init_body["id"])
	var upload_url: String = str(init_body["uploadUrl"])
	var required_headers: Dictionary = init_body.get("requiredHeaders", {})

	# 2) upload to uploadUrl
	var upload_ok := await _upload_put_raw(host, upload_url, required_headers, file_buf)
	if not upload_ok.success:
		return upload_ok

	# 3) complete
	var complete_resp := await _http_json(host, COMPLETE_URL, token, HTTPClient.METHOD_POST, {"id": id})
	if not complete_resp.success:
		return complete_resp

	# Success
	return {"success": true, "id": id}


# ---- HTTP helpers ----

func _http_json(host: Node, url: String, bearer_token: String, method: int, payload: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.use_threads = true
	host.add_child(http)

	var headers := PackedStringArray()
	headers.append("Authorization: Bearer %s" % bearer_token)
	headers.append("Content-Type: application/json")

	var body := JSON.stringify(payload).to_utf8_buffer()

	var err := http.request_raw(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"success": false, "error": "Request failed to initiate: %s" % err}

	var result = await http.request_completed
	http.queue_free()

	var res_code: int = result[1]
	var raw: PackedByteArray = result[3]
	var text := raw.get_string_from_utf8()

	if res_code < 200 or res_code >= 300:
		return {"success": false, "error": "HTTP %s: %s" % [res_code, text]}

	var parsed = JSON.parse_string(text)
	if parsed == null:
		return {"success": false, "error": "Invalid JSON: %s" % text}

	return {"success": true, "body": parsed}


func _upload_put_raw(host: Node, url: String, required_headers: Dictionary, bytes: PackedByteArray) -> Dictionary:
	var http := HTTPRequest.new()
	http.use_threads = true
	host.add_child(http)

	var headers := PackedStringArray()

	# Required headers come from init
	# For your current backend you return:
	#   Content-Type: application/zip
	#   X-Primes-SHA256: <hex>
	for k in required_headers.keys():
		headers.append("%s: %s" % [str(k), str(required_headers[k])])

	# If server didn't send Content-Type, set it anyway
	var has_ct := false
	for h in headers:
		if h.to_lower().begins_with("content-type:"):
			has_ct = true
			break
	if not has_ct:
		headers.append("Content-Type: application/zip")

	var err := http.request_raw(url, headers, HTTPClient.METHOD_PUT, bytes)
	if err != OK:
		http.queue_free()
		return {"success": false, "error": "Upload failed to initiate: %s" % err}

	var result = await http.request_completed
	http.queue_free()

	var res_code: int = result[1]
	var raw: PackedByteArray = result[3]
	var text := raw.get_string_from_utf8()

	# Your PUT returns 204 No Content on success
	if res_code == 204 or (res_code >= 200 and res_code < 300):
		return {"success": true}

	return {"success": false, "error": "Upload failed: HTTP %s: %s" % [res_code, text]}


# ---- File + SHA helpers ----

func _read_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"success": false, "error": "Cannot open: " + path}
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if bytes.size() <= 0:
		return {"success": false, "error": "Empty file: " + path}
	return {"success": true, "bytes": bytes}


func _sha256_hex(bytes: PackedByteArray) -> String:
	# Godot 4: HashingContext is available
	var ctx := HashingContext.new()
	var ok := ctx.start(HashingContext.HASH_SHA256)
	if ok != OK:
		return ""
	ctx.update(bytes)
	var digest: PackedByteArray = ctx.finish()
	return digest.hex_encode()


# ---- Existing engine logic (unchanged) ----

func get_engine_string() -> Dictionary:
	return _get_engine_string()

func _get_engine_string() -> Dictionary:
	var version_info = Engine.get_version_info()
	var engine = "godot%s_%s" % [version_info["major"], version_info["minor"]]

	var renderer_name: String = str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"))
	match renderer_name:
		"gl_compatibility":
			return {"success": true, "engine": "web" + engine}
		"mobile":
			return {
				"success": false,
				"error":
				(
					"Mobile renderer is not supported yet, we're working on it. "
					+ "Meanwhile please switch to Compatibility"
				)
			}
		_:
			return {"success": false, "error": "Unsupported renderer '%s' please switch to Compatibility" % renderer_name}
