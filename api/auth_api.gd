extends Object
class_name AuthAPI

const BASE_URL = "https://ole-luk-oie.com/primes"
const AUTH_EMAIL_START_URL = BASE_URL + "/auth/email/start"
const AUTH_EMAIL_VERIFY_URL = BASE_URL + "/auth/email/verify"
const AUTH_USERNAME_URL = BASE_URL + "/auth/username"
const AUTH_TOKEN_URL = BASE_URL + "/auth/token"

func start_email_sign_in(host: Node, email: String) -> Dictionary:
	var headers := PackedStringArray(["Content-Type: application/json"])
	var payload := {"email": email}
	var json_body := JSON.stringify(payload)
	
	var http := HTTPRequest.new()
	http.use_threads = true
	host.add_child(http)
	
	var err := http.request(AUTH_EMAIL_START_URL, headers, HTTPClient.METHOD_POST, json_body)
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
	
	var session_id := int(parsed.get("sessionId", -1))
	if session_id <= 0:
		return {
			"success": false,
			"error": "missing sessionId",
		}
	
	return {
		"success": true,
		"session_id": session_id,
	}

func verify_email_code(host: Node, session_id: int, code: String) -> Dictionary:
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
	var payload := {"sessionId": session_id, "code": code}
	var json_body := JSON.stringify(payload)
	
	var http := HTTPRequest.new()
	http.use_threads = true
	host.add_child(http)
	
	var err := http.request(AUTH_EMAIL_VERIFY_URL, headers, HTTPClient.METHOD_POST, json_body)
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
	
	var user_id := int(parsed.get("userId", -1))
	var username := String(parsed.get("username", ""))
	var needs_username := bool(parsed.get("needsUsername", username == ""))
	var token: String = parsed.get("token", "")
	
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
	
	return {
		"success": true,
		"user_id": user_id,
		"username": username,
		"needs_username": needs_username,
		"token": token
	}

func claim_username(host: Node, user_id: int, username: String) -> Dictionary:
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
	var payload := {"userId": user_id, "username": username}
	var json_body := JSON.stringify(payload)
	
	var http := HTTPRequest.new()
	http.use_threads = true
	host.add_child(http)
	
	var err := http.request(AUTH_USERNAME_URL, headers, HTTPClient.METHOD_POST, json_body)
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
	
	var result_username := String(parsed.get("username", ""))
	if result_username.is_empty():
		return {
			"success": false,
			"error": "missing username",
		}
	
	return {
		"success": true,
		"user_id": int(parsed.get("userId", user_id)),
		"username": result_username,
	}
