@tool
extends Control
class_name SignInView

signal sign_in_completed(token: String, username: String)

const AUTH_STEP_EMAIL := 0
const AUTH_STEP_CODE := 1
const AUTH_STEP_USERNAME := 2

@onready var sign_label: Label = $EmailL
@onready var email_le: LineEdit = $Email
@onready var sign_in_btn: Button = $SignInRow/SignInBtn

var _auth_step: int = AUTH_STEP_EMAIL
var _current_email: String = ""
var _session_id: int = -1
var _user_id: int = -1
var _username: String = ""
var _token: String = ""

var _exporter: PrimesExporter
var _logs: LogsArea

func setup(exporter: PrimesExporter, logs: LogsArea) -> void:
	_exporter = exporter
	_logs = logs

func _ready() -> void:
	sign_in_btn.pressed.connect(_on_sign_in)
	reset()

func reset() -> void:
	_auth_step = AUTH_STEP_EMAIL
	_session_id = -1
	_user_id = -1
	_username = ""
	_token = ""
	_current_email = ""
	
	sign_label.text = "Enter email:"
	email_le.placeholder_text = "you@example.com"
	email_le.text = ""
	sign_in_btn.text = "Send code"
	sign_in_btn.disabled = false
	
	email_le.grab_focus()

func _on_sign_in() -> void:
	match _auth_step:
		AUTH_STEP_EMAIL:
			await _handle_email_step()
		AUTH_STEP_CODE:
			await _handle_code_step()
		AUTH_STEP_USERNAME:
			await _handle_username_step()

func _handle_email_step() -> void:
	var email: String = email_le.text.strip_edges()
	if email == "":
		return
	
	_current_email = email
	sign_in_btn.disabled = true
	
	await _logs.append_log("Starting email sign-in…")
	
	var start_res: Dictionary = await _exporter.start_email_sign_in(self, email)
	
	if not start_res.get("success", false):
		sign_in_btn.disabled = false
		await _logs.append_log(
			"[color=red]Auth start failed:[/color] %s"
			% String(start_res.get("error", "unknown")), "red"
		)
		return
	
	_session_id = int(start_res.get("session_id", -1))
	if _session_id <= 0:
		sign_in_btn.disabled = false
		await _logs.append_log("[color=red]Invalid session id returned.[/color]", "red")
		return
	
	_auth_step = AUTH_STEP_CODE
	sign_label.text = "Enter verification code:"
	email_le.text = ""
	email_le.placeholder_text = ""
	sign_in_btn.text = "Verify"
	sign_in_btn.disabled = false
	
	await _logs.append_log("Verification code sent to [b]%s[/b]. Please check your inbox." % _current_email)
	email_le.grab_focus()

func _handle_code_step() -> void:
	var code: String = email_le.text.strip_edges()
	if code == "":
		return
	
	sign_in_btn.disabled = true
	
	var verify_res: Dictionary = await _exporter.verify_email_code(self, _session_id, code)
	
	if not verify_res.get("success", false):
		sign_in_btn.disabled = false
		await _logs.append_log(
			"[color=red]Code verification failed:[/color] %s"
			% String(verify_res.get("error", "unknown")), "red"
		)
		return
	
	_user_id = int(verify_res.get("user_id", -1))
	_username = verify_res.get("username", "")
	var needs_username: bool = bool(verify_res.get("needs_username", _username == ""))
	_token = String(verify_res.get("token", ""))
	
	if _username == null:
		_username = ""
	
	if _user_id <= 0:
		sign_in_btn.disabled = false
		await _logs.append_log("[color=red]Verify: invalid user_id.[/color]", "red")
		return
	if _token.is_empty():
		sign_in_btn.disabled = false
		await _logs.append_log("[color=red]Verify: missing token.[/color]", "red")
		return
	
	await _logs.append_log("[color=green]Code accepted[/color]")
	
	if not needs_username:
		_finish_sign_in()
		sign_in_btn.disabled = false
	else:
		_auth_step = AUTH_STEP_USERNAME
		sign_label.text = "Choose a username:"
		email_le.text = ""
		email_le.placeholder_text = "my_cool_name"
		sign_in_btn.text = "Set username"
		sign_in_btn.disabled = false
		email_le.grab_focus()

func _handle_username_step() -> void:
	var username: String = email_le.text.strip_edges()
	if username == "":
		return
	
	sign_in_btn.disabled = true
	
	var uname_res: Dictionary = await _exporter.claim_username(self, _user_id, username)
	
	if not uname_res.get("success", false):
		sign_in_btn.disabled = false
		await _logs.append_log(
			"[color=red]Username claim failed:[/color] %s"
			% String(uname_res.get("error", "unknown")), "red"
		)
		return
	
	_username = username
	await _logs.append_log("[color=green]Username set:[/color] [b]%s[/b]" % _username)
	
	_finish_sign_in()
	sign_in_btn.disabled = false

func _finish_sign_in() -> void:
	var display_name := (_username if _username != "" else _current_email)
	if display_name == "":
		display_name = "(unknown)"
	
	await _logs.append_log("Signed in as [b]%s[/b]" % display_name)
	
	sign_in_completed.emit(_token, _username)
