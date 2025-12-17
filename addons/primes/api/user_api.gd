class_name UserAPI
extends Object

const USER_INFO_URL = PrimesConfig.BASE_URL + "/dev/info"
const PRIMES_SET_PUBLIC_URL = PrimesConfig.BASE_URL + "/dev/set-public"
const EDIT_META_URL = PrimesConfig.BASE_URL + "/dev/edit-meta"
const PRIME_FLAGS_URL = PrimesConfig.BASE_URL + "/dev/flags"
const FLAGS_APPEAL_URL = PrimesConfig.BASE_URL + "/dev/flags/appeal"
const DELETE_PRIME_URL = PrimesConfig.BASE_URL + "/dev/prime"


func fetch_user_info(host: Node, token: String) -> Dictionary:
	if token.is_empty():
		return {"success": false, "error": "no_token"}

	var headers := PackedStringArray(["Authorization: Bearer %s" % token])

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

	return {"success": true, "username": username, "primes": primes}


func set_prime_visibility(
	host: Node, token: String, prime_id: String, is_public: bool
) -> Dictionary:
	var url := (
		"%s?primeId=%s&isPublic=%s"
		% [PRIMES_SET_PUBLIC_URL, prime_id.uri_encode(), "true" if is_public else "false"]
	)

	var headers := PackedStringArray(["Authorization: Bearer %s" % token])

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

	return {"success": true, "prime_id": prime_id, "is_public": is_public}


func update_prime_meta(
	host: Node, token: String, prime_id: String, name: String, description: String
) -> Dictionary:
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

	var headers := PackedStringArray(
		["Authorization: Bearer %s" % token, "Content-Type: application/json"]
	)

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

	return {"success": true, "prime_id": prime_id}


func fetch_prime_flags(host: Node, token: String, prime_id: String) -> Dictionary:
	if token.is_empty():
		return {"success": false, "error": "no_token"}

	if prime_id.is_empty():
		return {"success": false, "error": "missing prime id"}

	var url := "%s?id=%s" % [PRIME_FLAGS_URL, prime_id.uri_encode()]

	var headers := PackedStringArray(["Authorization: Bearer %s" % token])

	var http := HTTPRequest.new()
	http.use_threads = true
	host.add_child(http)

	var err := http.request(url, headers, HTTPClient.METHOD_GET)
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
	if typeof(parsed) != TYPE_ARRAY:
		return {
			"success": false,
			"error": "invalid JSON",
		}

	# parsed is Array<Dictionary> from PrimeFlagDto
	return {"success": true, "flags": parsed}


func submit_flag_appeal(host: Node, token: String, flag_id: int, message: String) -> Dictionary:
	if token.is_empty():
		return {"success": false, "error": "no_token"}

	if flag_id <= 0:
		return {"success": false, "error": "invalid flag id"}

	message = String(message).strip_edges()
	if message.is_empty():
		return {"success": false, "error": "empty_message"}

	# Optional local cap to match backend safety
	if message.length() > 2000:
		message = message.substr(0, 2000)

	var headers := PackedStringArray(
		["Authorization: Bearer %s" % token, "Content-Type: application/json"]
	)

	var payload := {
		"flagId": flag_id,
		"message": message,
	}
	var json_body := JSON.stringify(payload)

	var http := HTTPRequest.new()
	http.use_threads = true
	host.add_child(http)

	var err := http.request(FLAGS_APPEAL_URL, headers, HTTPClient.METHOD_POST, json_body)
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

	if http_status == 401 or http_status == 403:
		return {
			"success": false,
			"error": "token_expired",
		}

	# Backend returns 204 No Content on success
	if http_status != 200 and http_status != 204:
		return {
			"success": false,
			"error": "HTTP %d: %s" % [http_status, body_str],
		}

	return {"success": true, "flag_id": flag_id}


func delete_prime(host: Node, token: String, prime_id: String) -> Dictionary:
	if token.is_empty():
		return {"success": false, "error": "no_token"}

	if prime_id.is_empty():
		return {"success": false, "error": "missing prime id"}

	var url := "%s?primeId=%s" % [DELETE_PRIME_URL, prime_id.uri_encode()]

	var headers := PackedStringArray(["Authorization: Bearer %s" % token])

	var http := HTTPRequest.new()
	http.use_threads = true
	host.add_child(http)

	var err := http.request(url, headers, HTTPClient.METHOD_DELETE)
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

	if http_status == 401 or http_status == 403:
		return {
			"success": false,
			"error": "token_expired",
		}

	# Backend can return 200 or 204 on success
	if http_status != 200 and http_status != 204:
		return {
			"success": false,
			"error": "HTTP %d: %s" % [http_status, body_str],
		}

	return {"success": true, "prime_id": prime_id}
