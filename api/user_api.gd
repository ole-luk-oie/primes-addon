extends Object
class_name UserAPI

const USER_INFO_URL = PrimesConfig.BASE_URL + "/dev/info"
const PRIMES_SET_PUBLIC_URL = PrimesConfig.BASE_URL + "/dev/set-public"
const EDIT_META_URL = PrimesConfig.BASE_URL + "/dev/edit-meta"

func fetch_user_info(host: Node, token: String) -> Dictionary:
	if token.is_empty():
		return {"success": false, "error": "no_token"}
	
	var headers := PackedStringArray([
		"Authorization: Bearer %s" % token
	])
	
	var http := HTTPRequest.new()
	http.use_threads = true
	host.add_child(http)
	
	var err := http.request(USER_INFO_URL, headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
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

func set_prime_visibility(host: Node, token: String, prime_id: String, is_public: bool) -> Dictionary:
	var url := "%s?primeId=%s&isPublic=%s" % [
		PRIMES_SET_PUBLIC_URL,
		prime_id.uri_encode(),
		"true" if is_public else "false"
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
	
	return {
		"success": true,
		"prime_id": prime_id,
		"is_public": is_public
	}

func update_prime_meta(host: Node, token: String, prime_id: String, name: String, description: String) -> Dictionary:
	if prime_id.is_empty():
		return {
			"success": false,
			"error": "missing prime id",
		}
	
	# Local caps
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
	
	return {
		"success": true,
		"prime_id": prime_id
	}
