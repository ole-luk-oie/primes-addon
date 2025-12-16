extends Object
class_name Uploader

const UPLOAD_URL = PrimesConfig.BASE_URL + "/dev/upload"

func upload_zip(host: Node, token: String, zip_path: String,
		is_public := false, name := "", description := "") -> Dictionary:
	var f := FileAccess.open(zip_path, FileAccess.READ)
	if f == null:
		return {
			"success": false,
			"error": "Cannot open: " + zip_path
		}
	var file_buf := f.get_buffer(f.get_length())
	f.close()
	
	var engine_result := _get_engine_string()
	if not engine_result.success:
		return engine_result
	
	var boundary := "----GodotBoundary" + str(Time.get_unix_time_from_system())
	var body := PackedByteArray()
	
	#_add_part(body, boundary, "author", author)
	_add_part(body, boundary, "engine", engine_result.engine)
	if not name.is_empty():
		_add_part(body, boundary, "name", name)
	if not description.is_empty():
		_add_part(body, boundary, "description", description)
	_add_part(body, boundary, "public", str(is_public))
	
	# File part
	body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
	body.append_array(('Content-Disposition: form-data; name="file"; filename="%s"\r\n' % zip_path.get_file()).to_utf8_buffer())
	body.append_array("Content-Type: application/zip\r\n\r\n".to_utf8_buffer())
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
		return {
			"success": false,
			"error": "Upload failed to initiate: %s" % err
		}
	
	var result = await http.request_completed
	http.queue_free()
	
	if result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200:
		return {
			"success": true,
			"id": (result[3] as PackedByteArray).get_string_from_utf8()
		}
	else:
		return {
			"success": false,
			"error": "Upload failed with result %s, status %s, body %s" % [
				result[0], result[1], result[3].get_string_from_utf8()
			]
		}

func get_engine_string() -> Dictionary:
	return _get_engine_string()

func _get_engine_string() -> Dictionary:
	var version_info = Engine.get_version_info()
	var engine = "godot%s_%s" % [version_info["major"], version_info["minor"]]
	
	var renderer_name: String = str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"))
	match renderer_name:
		"gl_compatibility":
			return {
				"success": true,
				"engine": "web" + engine
			}
		"mobile":
			return {
				"success": false,
				"error": "Mobile renderer is not supported yet, we're working on it. Meanwhile please switch to Compatibility"
			}
		_:
			return {
				"success": false,
				"error": "Unsupported renderer '%s' please switch to Compatibility" % renderer_name
			}
	

func _add_part(body: PackedByteArray, boundary: String, name: String, value: String) -> void:
	body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
	body.append_array(('Content-Disposition: form-data; name="%s"\r\n\r\n' % name).to_utf8_buffer())
	body.append_array(value.to_utf8_buffer())
	body.append_array("\r\n".to_utf8_buffer())
