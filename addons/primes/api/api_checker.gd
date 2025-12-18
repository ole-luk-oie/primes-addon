@tool
extends Object
class_name RestrictedAPIChecker

# Directories that should NOT be scanned
const EXCLUDE_DIRS := [
	"res://addons/primes",
	"res://.godot",
	"res://.import"
]

# === Removed / forbidden classes ===
const BANNED_CLASSES := [
	"GDExtension",
	"GDExtensionManager",
	"ScriptExtension",
	"ScriptLanguageExtension",
	"ScriptLanguageExtensionProfilingInfo",

	"IP",
	"StreamPeer",
	"StreamPeerExtension",
	"StreamPeerTCP",
	"TCPServer",
	"PacketPeer",
	"PacketPeerExtension",
	"PacketPeerStream",
	"PacketPeerUDP",
	"UDPServer",
	"HTTPClient",

	"MultiplayerPeer",
	"MultiplayerPeerExtension",
	"MultiplayerAPI",
	"MultiplayerAPIExtension",
	"HTTPRequest",

	"JNISingleton",
	"JavaClass",
	"JavaObject",
	"JavaClassWrapper",

	"JavaScriptObject",
	"JavaScriptBridge"
]

# === Removed OS methods (checked as OS.<method>) ===
const BANNED_OS_METHODS := [
	"execute",
	"execute_with_pipe",
	"create_process",
	"create_instance",
	"kill",
	"is_process_running",
	"get_process_exit_code",
	"get_process_id",
	"shell_open",
	"shell_show_in_file_manager",

	"has_environment",
	"get_environment",
	"set_environment",
	"unset_environment",
	"get_cmdline_args",
	"get_cmdline_user_args",
	"set_restart_on_exit",
	"is_restart_on_exit_set",
	"get_restart_on_exit_arguments",

	"move_to_trash",
	"get_system_dir",

	"get_unique_id",
	"request_permission",
	"request_permissions",
	"get_granted_permissions",
	"revoke_granted_permissions"
]

# === Internal compiled regex caches ===
static var _compiled_class_regexes: Array[RegEx] = []
static var _compiled_os_regexes: Array[RegEx] = []
static var _compiled_ready := false


# === Public entry point ===
# Returns:
# {
#   "ok": bool,
#   "findings": Array[Dictionary]
# }
static func scan_project(root: String = "res://") -> Dictionary:
	_ensure_compiled()

	var findings: Array = []
	_scan_dir_recursive(root, findings)

	return {
		"ok": findings.is_empty(),
		"findings": findings
	}


# === Compile regexes once ===
static func _ensure_compiled() -> void:
	if _compiled_ready:
		return
	_compiled_ready = true

	_compiled_class_regexes.clear()
	for cls in BANNED_CLASSES:
		var r := RegEx.new()
		r.compile("\\b" + cls + "\\b")
		_compiled_class_regexes.append(r)

	_compiled_os_regexes.clear()
	for m in BANNED_OS_METHODS:
		var r2 := RegEx.new()
		r2.compile("\\bOS\\s*\\.\\s*" + m + "\\b")
		_compiled_os_regexes.append(r2)


# === Directory traversal ===
static func _scan_dir_recursive(dir_path: String, findings: Array) -> void:
	if _is_excluded(dir_path):
		return

	var d := DirAccess.open(dir_path)
	if d == null:
		return

	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue

		var p := dir_path.path_join(name)
		if d.current_is_dir():
			_scan_dir_recursive(p, findings)
		else:
			if p.get_extension().to_lower() == "gd":
				_scan_gd_file(p, findings)

		name = d.get_next()
	d.list_dir_end()


static func _is_excluded(path: String) -> bool:
	for ex in EXCLUDE_DIRS:
		if path == ex or path.begins_with(ex + "/"):
			return true
	return false


# === File scan ===
static func _scan_gd_file(file_path: String, findings: Array) -> void:
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return

	var text := f.get_as_text()
	f.close()

	var lines := text.split("\n", false)

	for i in range(lines.size()):
		var raw_line := lines[i]
		var line_no := i + 1

		# Strip comments and strings to reduce false positives
		var line := _strip_strings_and_comments(raw_line)

		# Check banned classes
		for r in _compiled_class_regexes:
			var m := r.search(line)
			if m != null:
				findings.append({
					"file": file_path,
					"line": line_no,
					"kind": "class",
					"match": m.get_string(),
					"preview": raw_line.strip_edges()
				})

		# Check banned OS methods
		for r2 in _compiled_os_regexes:
			var m2 := r2.search(line)
			if m2 != null:
				findings.append({
					"file": file_path,
					"line": line_no,
					"kind": "os_method",
					"match": m2.get_string(),
					"preview": raw_line.strip_edges()
				})


# === Helpers ===
static func _strip_strings_and_comments(s: String) -> String:
	# Remove single-line comments
	var hash := s.find("#")
	if hash != -1:
		s = s.substr(0, hash)

	# Remove quoted strings (best-effort, not a full parser)
	s = _remove_quoted(s, "\"")
	s = _remove_quoted(s, "'")
	return s


static func _remove_quoted(s: String, quote: String) -> String:
	var out := ""
	var in_q := false
	var i := 0
	while i < s.length():
		var ch := s[i]
		if ch == quote:
			in_q = not in_q
			out += " "
		elif in_q:
			out += " "
		else:
			out += ch
		i += 1
	return out
