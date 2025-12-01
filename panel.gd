@tool
extends PanelContainer
class_name CloudPublisherPanel

var plugin: EditorPlugin
var exporter: PrimesExporter = PrimesExporter.new()

# UI Components
@onready var stack: VBoxContainer = $Root/Stack
@onready var sign_in_wrapper: Control = $Root/Stack/SignInWrapper
@onready var sign_in_view: SignInView = $Root/Stack/SignInWrapper/SignIn
@onready var publish_vb: VBoxContainer = $Root/Stack/Publish
@onready var author_section: AuthorSection = $Root/Stack/Publish/AuthorRow
@onready var published_list: PublishedList = $Root/Stack/Publish/PublishedScroll
@onready var publish_form: PublishForm = $Root/Stack/Publish/Form
@onready var logs: LogsArea = $Root/Log
@onready var edit_dialog: EditPrimeDialog = $Root/EditDialog
@onready var flags_dialog: FlagsDialog = $Root/FlagsDialog
@onready var initializing_wrapper: Control = $Root/Stack/InitializingWrapper

# State
var _token: String = ""
var _username: String = ""

# Recovery lock handling
var _rec_lock_path := OS.get_user_data_dir().path_join(".recovery_mode_lock")
var _rec_lock_preexisting := false

var _initialized = false

func _ready() -> void:
	# Setup component dependencies
	sign_in_view.setup(exporter, logs)
	
	# Connect signals
	sign_in_view.sign_in_completed.connect(_on_sign_in_completed)
	author_section.logout_requested.connect(_on_logout)
	
	published_list.copy_link_requested.connect(_on_copy_link)
	published_list.toggle_visibility_requested.connect(_on_toggle_visibility)
	published_list.edit_prime_requested.connect(_on_edit_prime)
	published_list.flag_details_requested.connect(_on_flag_details_requested)
	
	publish_form.publish_requested.connect(_on_publish)
	
	edit_dialog.update_requested.connect(_on_update_prime_meta)
	
	if flags_dialog:
		flags_dialog.appeal_submitted.connect(_on_flag_appeal_submitted)
	
	# Initialize view
	ensure_correct_subview()
	
func ensure_correct_subview():
	if plugin:
		var token := String(plugin.load_token())
		if token and token != "":
			_token = token
			if not _initialized:
				_show_initializing()
			if await _update_primes():
				_show_publish()
				_initialized = true
				return
	
	_show_sign_in()

func _show_initializing() -> void:
	initializing_wrapper.visible = true
	publish_vb.visible = false
	sign_in_wrapper.visible = false

func _show_sign_in() -> void:
	initializing_wrapper.visible = false
	publish_vb.visible = false
	sign_in_wrapper.visible = true
	sign_in_view.reset()

func _show_publish() -> void:
	initializing_wrapper.visible = false
	sign_in_wrapper.visible = false
	publish_vb.visible = true

# === Sign-In Handlers ===
func _on_sign_in_completed(token: String, username: String) -> void:
	_token = token
	_username = username
	
	if plugin:
		plugin.save_token(_token)
	
	author_section.set_username(_username)
	await _update_primes()
	_show_publish()

func _on_logout() -> void:
	_token = ""
	_username = ""
	
	author_section.clear()
	
	if plugin:
		plugin.clear_token()
	
	await logs.append_log("Signed out")
	
	_show_sign_in()

# === Published List Handlers ===
func _on_copy_link(prime_id: String) -> void:
	var link := "https://ole-luk-oie.com/primes/i?id=" + prime_id
	DisplayServer.clipboard_set(link)
	await logs.append_log("Link copied to the clipboard: [b]" + link + "[/b]")

func _on_toggle_visibility(prime_id: String, name: String, current_is_public: bool) -> void:
	if _token.is_empty():
		await logs.append_log("[color=orange]Session expired. Please sign in again.[/color]", "orange")
		return
	
	var new_is_public := not current_is_public
	
	await logs.append_log("Updating visibility for [b]%s[/b]" % [name])
	
	var res: Dictionary = await exporter.set_prime_visibility(
		self,
		_token,
		prime_id,
		new_is_public
	)
	
	if not res.get("success", false):
		await logs.append_log(
			"[color=red]Failed to update visibility for[/color] [b]%s[/b]: %s"
			% [name, String(res.get("error", "unknown"))]
		)
		return
	
	published_list.update_visibility_state(prime_id, new_is_public)
	await logs.append_log(
		"Toggled visibility for [b]%s[/b] → %s"
		% [name, "public" if new_is_public else "hidden"]
	)

func _on_edit_prime(prime_id: String, name: String, description: String) -> void:
	edit_dialog.show_edit_dialog(prime_id, name, description)

func _on_update_prime_meta(prime_id: String, prev_name: String, name: String, description: String) -> void:
	if _token.is_empty():
		await logs.append_log("[color=orange]Session expired. Please sign in again.[/color]", "orange")
		return
	
	await logs.append_log("Updating meta for [b]%s[/b]" % [prev_name])

	var res := await exporter.update_prime_meta(
		self,
		_token,
		prime_id,
		name,
		description
	)
	
	if not res.get("success", false):
		await logs.append_log(
			"[color=red]Update failed for[/color] [b]%s[/b]: %s"
			% [prev_name, String(res.get("error", "unknown"))], "red"
		)
		return
	
	await logs.append_log("Meta for [b]%s[/b] succefully updated" % prev_name)
	edit_dialog.hide()
	
	await _update_primes()

func _on_flag_details_requested(prime_id: String, prime_name: String) -> void:
	if _token.is_empty():
		await logs.append_log("[color=orange]Session expired. Please sign in again.[/color]", "orange")
		return
	
	await logs.append_log("Fetching flags for [b]%s[/b] (id=%s)..." % [prime_name, prime_id])
	
	var res := await exporter.fetch_prime_flags(self, _token, prime_id)
	
	if not res.get("success", false):
		var err := String(res.get("error", "unknown"))
		if err == "token_expired":
			await logs.append_log("[color=orange]Session expired. Please sign in again.[/color]", "orange")
			_token = ""
			if plugin:
				plugin.clear_token()
			_show_sign_in()
			return
		
		await logs.append_log("[color=red]Failed to fetch flags:[/color] %s" % err, "red")
		return
	
	var flags: Array = res.get("flags", [])
	
	flags_dialog.show_flags(prime_id, prime_name, flags)

func _on_flag_appeal_submitted(prime_id: String, flag_id: int, message: String) -> void:
	if _token.is_empty():
		await logs.append_log("[color=orange]Session expired. Please sign in again.[/color]", "orange")
		return

	message = String(message).strip_edges()
	if message.is_empty():
		await logs.append_log("[color=orange]Please enter a comment before appealing.[/color]", "orange")
		# Re-enable UI if dialog had already disabled it
		if flags_dialog:
			flags_dialog.set_appeal_enabled(flag_id, true)
		return

	await logs.append_log(
		"Submitting appeal for flag [b]%d[/b] on prime [b]%s[/b]..." % [flag_id, prime_id]
	)

	var res := await exporter.submit_flag_appeal(self, _token, flag_id, message)

	if not res.get("success", false):
		var err := String(res.get("error", "unknown"))

		if err == "token_expired":
			await logs.append_log("[color=orange]Session expired. Please sign in again.[/color]", "orange")
			_token = ""
			if plugin:
				plugin.clear_token()
			_show_sign_in()
			return

		# Request failed → restore button / input so user can try again
		if flags_dialog:
			flags_dialog.set_appeal_enabled(flag_id, true)

		await logs.append_log(
			"[color=red]Failed to submit appeal:[/color] %s" % err,
			"red"
		)
		return

	# Success → update the row UI to APPEALED state
	if flags_dialog:
		flags_dialog.mark_flag_appealed(flag_id)

	await logs.append_log(
		"[color=green]Appeal submitted for flag[/color] [b]%d[/b] on [b]%s[/b]." % [flag_id, prime_id]
	)


# === User Data Management ===
func _update_primes() -> bool:
	var info: Dictionary = await exporter.fetch_user_info(self, _token)
	
	if info.get("success", false):
		_username = String(info.get("username", ""))
		if _username == "":
			_username = "(unknown)"
		
		author_section.set_username(_username)
		
		var games = info.get("primes", [])
		if typeof(games) == TYPE_ARRAY:
			published_list.update_list(games)
		else:
			published_list.update_list([])
		
		return true
	else:
		var error = String(info.get("error", ""))
		if error == "token_expired":
			await logs.append_log("[color=orange]Session expired. Please sign in again.[/color]", "orange")
			_token = ""
			plugin.clear_token()
			_show_sign_in()
			return false
		else:
			await logs.append_log("[color=orange]Failed to fetch user data. Updates may not be visible right away.[/color]", "orange")
		return true

# === Publish Handlers ===
func _on_publish(name: String, description: String, hide_from_feed: bool) -> void:
	_remember_recovery_lock_state()
	
	var is_public: bool = not hide_from_feed
	
	publish_form.set_enabled(false)
	
	var result := await pack_and_upload(
		self,
		_token,
		is_public,
		name,
		description
	)
	
	if not result.get("success", false):
		await logs.append_log("[color=red]Failed to publish:[/color] %s" % String(result.get("error", "")), "red")
	else:
		var link: String = "https://ole-luk-oie.com/primes/i?id=" + String(result["id"])
		DisplayServer.clipboard_set(link)
		await logs.append_log(
			"[color=green]Published[/color] %s. Link copied: %s"
			% [("Public" if is_public else "Unlisted"), link]
		)
		publish_form.clear_form()
	
	publish_form.set_enabled(true)
	
	_clear_recovery_lock_if_new()
	
	await _update_primes()

func pack_and_upload(host: Node, token: String, is_public: bool, 
		name: String, description: String) -> Dictionary:
	
	await logs.append_log("Packing project...")

	# Pack
	var pack_result := exporter.pack_zip()
	if not pack_result.get("success", false):
		await logs.append_log("[color=red]Failed to build package:[/color] %s" % String(pack_result.get("error", "")), "red")
		return pack_result
	
	var zip_path: String = pack_result.get("zip_path", "")
	
	await logs.append_log("Uploading...")

	# Upload
	var upload_result := await exporter.upload_zip(
		host, token, zip_path, is_public, name, description
	)
	
	await logs.append_log("Cleaning up...")

	# Cleanup
	exporter.cleanup_temp(zip_path)
	
	return upload_result

# === Recovery Lock Management ===
func _remember_recovery_lock_state() -> void:
	_rec_lock_preexisting = FileAccess.file_exists(_rec_lock_path)
	#if _rec_lock_preexisting:
		#await logs.append_log("[i]Editor recovery lock is set. [/i]")
	#else:
		#await logs.append_log("[i]No editor recovery lock.[/i]")

func _clear_recovery_lock_if_new() -> void:
	if not _rec_lock_preexisting and FileAccess.file_exists(_rec_lock_path):
		var err := DirAccess.remove_absolute(_rec_lock_path)
		#if err == OK:
			#await logs.append_log("[i]Cleared editor recovery lock.[/i]")
