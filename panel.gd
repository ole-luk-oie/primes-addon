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
@onready var publish_divider_label: Label = $Root/Stack/Publish/DividerContainer/DividerRow/DividerLabel
@onready var logs: LogsArea = $Root/Log
@onready var edit_dialog: EditPrimeDialog = $Root/EditDialog
@onready var flags_dialog: FlagsDialog = $Root/FlagsDialog
@onready var initializing_wrapper: Control = $Root/Stack/InitializingWrapper

# adb stuff
var _device_check_timer: Timer
var _has_android_device: bool = false

var _device_menu: PopupMenu
var _pending_run_name: String = ""
var _pending_run_desc: String = ""
var _pending_devices: Array = [] # [{serial, label}]

# State
var _token: String = ""
var _username: String = ""

var _initialized = false

func _ready() -> void:
	_apply_hidpi()
	# Setup component dependencies
	sign_in_view.setup(exporter, logs)
	
	var theme := EditorInterface.get_editor_theme()
	publish_divider_label.add_theme_font_override("font", theme.get_font("bold", "EditorFonts"))
	publish_divider_label.add_theme_font_size_override("font_size",
		theme.get_font_size("main_size", "EditorFonts")
	)
	
	# Connect signals
	sign_in_view.sign_in_completed.connect(_on_sign_in_completed)
	author_section.logout_requested.connect(_on_logout)
	
	published_list.copy_link_requested.connect(_on_copy_link)
	published_list.toggle_visibility_requested.connect(_on_toggle_visibility)
	published_list.edit_prime_requested.connect(_on_edit_prime)
	published_list.flag_details_requested.connect(_on_flag_details_requested)
	published_list.delete_prime_requested.connect(_on_delete_prime)
	
	publish_form.publish_requested.connect(_on_publish)
	publish_form.run_on_phone_requested.connect(_on_run_on_phone)
	
	edit_dialog.update_requested.connect(_on_update_prime_meta)
	
	if flags_dialog:
		flags_dialog.appeal_submitted.connect(_on_flag_appeal_submitted)
	
	_device_menu = PopupMenu.new()
	add_child(_device_menu)
	_device_menu.id_pressed.connect(_on_device_menu_id_pressed)
	
	# Start device polling (lightweight, every couple of seconds)
	_device_check_timer = Timer.new()
	_device_check_timer.wait_time = 2.0
	_device_check_timer.one_shot = false
	_device_check_timer.timeout.connect(_on_device_check_timeout)
	add_child(_device_check_timer)
	_device_check_timer.start()
	
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

func _apply_hidpi() -> void:
	var s := PrimesUIScaler.scale()

	$Root/EditDialog/EditVBox.custom_minimum_size.x = PrimesUIScaler.px(500)
	$Root/EditDialog/EditVBox/DescGroup/DescEdit.custom_minimum_size.y = PrimesUIScaler.px(80)
	$Root/Stack/Publish/Form/CenterRow/FormInner.custom_minimum_size.x = PrimesUIScaler.px(500)

	$Root/Stack/Publish/PublishedScroll.custom_minimum_size.y = PrimesUIScaler.px(120)
	$Root/Stack/Publish/DividerContainer/DividerRow/LeftLine.custom_minimum_size.x = PrimesUIScaler.px(150)
	$Root/Log.custom_minimum_size.y = PrimesUIScaler.px(160)

	$Root/Stack/SignInWrapper/SignIn/Email.custom_minimum_size = PrimesUIScaler.v2(250, 0)

	var sign_in := $Root/Stack/SignInWrapper/SignIn
	sign_in.offset_left   = -PrimesUIScaler.px(125)
	sign_in.offset_right  =  PrimesUIScaler.px(125)
	sign_in.offset_top    = -PrimesUIScaler.px(60)
	sign_in.offset_bottom =  PrimesUIScaler.px(60)

	var init := $Root/Stack/InitializingWrapper/Initializing
	init.offset_left   = -PrimesUIScaler.px(100)
	init.offset_right  =  PrimesUIScaler.px(100)
	init.offset_top    = -PrimesUIScaler.px(20)
	init.offset_bottom =  PrimesUIScaler.px(20)

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

func _on_device_check_timeout() -> void:
	var available := exporter.probe_android_device()

	_has_android_device = available
	publish_form.set_dev_run_available(_has_android_device)

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

func _on_run_on_phone(name: String, description: String) -> void:
	# Ask exporter for devices (DevRunner does the adb work)
	var devices := exporter.list_android_devices()

	if devices.size() == 0:
		await logs.append_log(
			"[color=orange]No Android device detected via adb.[/color]",
			"orange"
		)
		return

	if devices.size() == 1:
		var serial := String(devices[0].get("serial", ""))
		if serial == "":
			await logs.append_log("[color=red]Device selection failed.[/color]", "red")
			return
		await _run_on_phone_with_serial(name, description, serial)
		return

	# >1 device: popup menu at mouse cursor
	_pending_run_name = name
	_pending_run_desc = description
	_pending_devices = devices

	_device_menu.clear()
	for i in range(_pending_devices.size()):
		_device_menu.add_item(String(_pending_devices[i].get("label", "Device")), i)

	var pos := DisplayServer.mouse_get_position()
	_device_menu.position = pos
	_device_menu.reset_size()
	_device_menu.popup()

func _on_device_menu_id_pressed(id: int) -> void:
	if id < 0 or id >= _pending_devices.size():
		return

	var serial := String(_pending_devices[id].get("serial", ""))
	if serial == "":
		await logs.append_log("[color=red]Device selection failed.[/color]", "red")
		return

	await _run_on_phone_with_serial(_pending_run_name, _pending_run_desc, serial)

func _run_on_phone_with_serial(name: String, description: String, device_serial: String) -> void:
	if not _has_android_device:
		# Optional extra guard; enumeration already checked above.
		await logs.append_log(
			"[color=orange]No Android device detected via adb.[/color]",
			"orange"
		)
		return

	publish_form.set_enabled(false)

	var ok := await exporter.dev_run_on_phone(
		self,
		logs,
		_username,
		name,
		description,
		device_serial
	)

	if ok:
		await logs.append_log("[color=green]Launched on device.[/color]")
	else:
		await logs.append_log("[color=red]Failed to launch on device.[/color]", "red")

	publish_form.set_enabled(true)


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

func _on_delete_prime(prime_id: String, name: String) -> void:
	if _token.is_empty():
		await logs.append_log("[color=orange]Session expired. Please sign in again.[/color]", "orange")
		return

	# Confirmation dialog
	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete from Primes"
	dlg.dialog_text = "Are you sure you want to delete \"%s\"?\n\n" % name +\
		"This removes the cloud copy from the catalog and feed. " +\
		"Your local Godot project stays unchanged.\n\n"

	dlg.min_size = PrimesUIScaler.v2(420, 100)

		# Center the text in the dialog
	var lbl := dlg.get_label() # AcceptDialog / ConfirmationDialog exposes this
	if lbl:
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AutowrapMode.AUTOWRAP_WORD
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Optional: customize buttons
	var ok_btn := dlg.get_ok_button()
	if ok_btn:
		ok_btn.text = "Delete"
	var cancel_btn := dlg.get_cancel_button()
	if cancel_btn:
		cancel_btn.text = "Cancel"

	add_child(dlg)
	dlg.popup_centered()

	dlg.canceled.connect(func():
		dlg.queue_free()
	)

	dlg.confirmed.connect(func():
		# Run the async delete flow
		await _perform_prime_delete(prime_id, name)
		dlg.queue_free()
	)

func _perform_prime_delete(prime_id: String, name: String) -> void:
	await logs.append_log("Deleting [b]%s[/b] from Primes..." % name)

	var res := await exporter.delete_prime(self, _token, prime_id)

	if not res.get("success", false):
		var err := String(res.get("error", "unknown"))
		await logs.append_log(
			"[color=red]Failed to delete[/color] [b]%s[/b]: %s" % [name, err],
			"red"
		)
		return

	await logs.append_log(
		"[color=green]Deleted[/color] [b]%s[/b] from Primes." % name
	)

	# Refresh list so the row disappears
	await _update_primes()


# === Publish Handlers ===
func _on_publish(name: String, description: String, hide_from_feed: bool) -> void:
	
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
