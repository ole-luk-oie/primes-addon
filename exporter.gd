extends Object
class_name PrimesExporter

const PLUGIN_DIR = "res://addons/primes"
const STUB_NAME = "__primes_stub.gd"
const ACCEPTED_PLATFORMS = ["Android", "Web"]

var _auth_api: AuthAPI = AuthAPI.new()
var _user_api: UserAPI = UserAPI.new()
var _packager: Packager = Packager.new()
var _uploader: Uploader = Uploader.new()

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

# === Authentication ===
func start_email_sign_in(host: Node, email: String) -> Dictionary:
	return await _auth_api.start_email_sign_in(host, email)

func verify_email_code(host: Node, session_id: int, code: String) -> Dictionary:
	return await _auth_api.verify_email_code(host, session_id, code)

func claim_username(host: Node, user_id: int, username: String) -> Dictionary:
	return await _auth_api.claim_username(host, user_id, username)

# === User Management ===
func fetch_user_info(host: Node, token: String) -> Dictionary:
	return await _user_api.fetch_user_info(host, token)

func set_prime_visibility(host: Node, token: String, prime_id: String, is_public: bool) -> Dictionary:
	return await _user_api.set_prime_visibility(host, token, prime_id, is_public)

func update_prime_meta(host: Node, token: String, prime_id: String, name: String, description: String) -> Dictionary:
	return await _user_api.update_prime_meta(host, token, prime_id, name, description)

func fetch_prime_flags(host: Node, token: String, prime_id: String) -> Dictionary:
	return await _user_api.fetch_prime_flags(host, token, prime_id)
	
func submit_flag_appeal(host: Node, token: String, flag_id: int, message: String) -> Dictionary:
	return await _user_api.submit_flag_appeal(host, token, flag_id, message)

func pack_zip() -> Dictionary:
	return _packager.pack_zip()
	
func upload_zip(host: Node, token: String, zip_path: String, is_public: bool, 
		name: String, description: String) -> Dictionary:
	return await _uploader.upload_zip(host, token, zip_path, is_public, name, description)

func cleanup_temp(zip_path: String):
	_packager.cleanup_temp(zip_path)
