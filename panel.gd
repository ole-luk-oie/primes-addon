@tool
extends PanelContainer
class_name CloudPublisherPanel

var plugin: EditorPlugin

@onready var stack: VBoxContainer          = $Root/Stack
@onready var sign_in: VBoxContainer        = $Root/Stack/SignInWrapper/SignIn
@onready var sign_label: Label             = $Root/Stack/SignInWrapper/SignIn/EmailL
@onready var email_le: LineEdit            = $Root/Stack/SignInWrapper/SignIn/Email
@onready var sign_in_btn: Button           = $Root/Stack/SignInWrapper/SignIn/SignInRow/SignInBtn

@onready var publish_vb: VBoxContainer     = $Root/Stack/Publish
@onready var author_val: RichTextLabel     = $Root/Stack/Publish/AuthorRow/AuthorValue
@onready var published_list: VBoxContainer = $Root/Stack/Publish/PublishedScroll/PublishedList
@onready var name_le: LineEdit             = $Root/Stack/Publish/Form/CenterRow/FormInner/NameGroup/Name
@onready var desc_te: TextEdit             = $Root/Stack/Publish/Form/CenterRow/FormInner/DescGroup/Desc
@onready var hide_cb: CheckBox             = $Root/Stack/Publish/Form/CenterRow/FormInner/ActionArea/HideFromFeed
@onready var publish_btn: Button           = $Root/Stack/Publish/Form/CenterRow/FormInner/ActionArea/PublishBtn
@onready var log_rt: RichTextLabel         = $Root/Log
@onready var logout_btn: Button            = $Root/Stack/Publish/AuthorRow/LogoutBtn

@onready var edit_dialog: AcceptDialog     = $Root/EditDialog
@onready var edit_name_le: LineEdit        = $Root/EditDialog/EditVBox/NameGroup/NameEdit
@onready var edit_desc_te: TextEdit        = $Root/EditDialog/EditVBox/DescGroup/DescEdit

var _editing_prime_id: String = ""

var _current_email: String = ""
var _session_id: int = -1
var _user_id: int = -1
var _username: String = ""
var _token: String = ""

const AUTH_STEP_EMAIL := 0
const AUTH_STEP_CODE := 1
const AUTH_STEP_USERNAME := 2

var _auth_step: int = AUTH_STEP_EMAIL

const DESC_MAX := 255

var ROW_BG_DARK := StyleBoxFlat.new()
var ROW_BG_LIGHT := StyleBoxFlat.new()

var exporter: PrimesExporter
var _log_cleared = false

# --- Recovery lock handling ---
var _rec_lock_path := OS.get_user_data_dir().path_join(".recovery_mode_lock")
var _rec_lock_preexisting := false

func _remember_recovery_lock_state() -> void:
	_rec_lock_preexisting = FileAccess.file_exists(_rec_lock_path)

func _clear_recovery_lock_if_new() -> void:
	# Only remove if it wasn't there before we started.
	if not _rec_lock_preexisting and FileAccess.file_exists(_rec_lock_path):
		var err := DirAccess.remove_absolute(_rec_lock_path)
		if err == OK:
			await _append_log("[i]Cleared editor recovery lock.[/i]")

func _ready() -> void:
	
	var theme := EditorInterface.get_editor_theme()

	ROW_BG_DARK = StyleBoxFlat.new()
	ROW_BG_DARK.bg_color = theme.get_color("dark_color_1", "Editor")
	ROW_BG_DARK.set_content_margin_all(3)
	ROW_BG_DARK.draw_center = true

	ROW_BG_LIGHT = StyleBoxFlat.new()
	ROW_BG_LIGHT.bg_color = theme.get_color("dark_color_2", "Editor")
	ROW_BG_LIGHT.set_content_margin_all(3)
	ROW_BG_LIGHT.draw_center = true
	
	published_list.add_theme_constant_override("separation", 0)
	
	logout_btn.flat = true
	logout_btn.focus_mode = Control.FOCUS_NONE
	logout_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	logout_btn.modulate = Color(1, 1, 1, 0.8)
	logout_btn.mouse_entered.connect(func(): logout_btn.modulate = Color(0.7, 0.7, 1))
	logout_btn.mouse_exited .connect(func(): logout_btn.modulate = Color(1, 1, 1, 0.8))
	
	# Edit dialog buttons & signals
	var ok_btn = edit_dialog.get_ok_button()
	edit_dialog.add_cancel_button("Close")
	if ok_btn:
		ok_btn.text = "Update"

	edit_dialog.confirmed.connect(_on_edit_dialog_confirmed)
	# Cancel just hides by default, no extra code needed

	# Limit description length as well
	edit_desc_te.text_changed.connect(_on_edit_desc_changed)
	
	# Sign-In
	sign_in_btn.pressed.connect(_on_sign_in)

	# Logout
	logout_btn.pressed.connect(_on_logout)

	# Publish actions
	publish_btn.pressed.connect(_on_publish)
	desc_te.text_changed.connect(_on_desc_text_changed)

	# Show placeholder in the published list (until server data arrives)
	update_published_list([])

	# Prefill if we already have creds
	ensure_correct_subview()

func ensure_correct_subview() -> void:
	if plugin:
		var token := String(plugin.load_token())
		if token and token != "":
			_token = token
			# Try to fetch user info with the stored token
			if await _update_primes():
				_show_publish()
				return
	
	_show_sign_in()


func _on_edit_desc_changed() -> void:
	var t := edit_desc_te.text
	if t.length() > DESC_MAX:
		var cl := edit_desc_te.get_caret_line()
		var cc := edit_desc_te.get_caret_column()

		edit_desc_te.text = t.substr(0, DESC_MAX)

		var line := min(cl, edit_desc_te.get_line_count() - 1)
		var col := min(cc, edit_desc_te.get_line(line).length())
		edit_desc_te.set_caret_line(line)
		edit_desc_te.set_caret_column(col)

func _show_sign_in() -> void:
	publish_vb.visible = false
	sign_in.visible = true

	_auth_step = AUTH_STEP_EMAIL
	_session_id = -1
	_user_id = -1
	_username = ""

	sign_label.text = "Enter email:"
	email_le.placeholder_text = "you@example.com"
	sign_in_btn.text = "Send code"

	email_le.grab_focus()
	
func _show_publish() -> void:
	sign_in.visible = false
	publish_vb.visible = true
	name_le.grab_focus()


func update_published_list(items: Array) -> void:
	# Clear any previous rows
	for c in published_list.get_children():
		c.queue_free()

	var num_items := items.size()
	var total_rows := max(num_items, 3)

	for i in range(total_rows):
		# ===== outer panel: draws background =====
		var row_panel := PanelContainer.new()
		row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_panel.custom_minimum_size = Vector2(0, 40)
		row_panel.add_theme_stylebox_override(
			"panel",
			ROW_BG_DARK if i % 2 == 1 else ROW_BG_LIGHT
		)

		# --- inner row ---
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		row_panel.add_child(row)

		if i < num_items:
			# ----- REAL PRIME ROW -----
			var meta = items[i]
			if typeof(meta) != TYPE_DICTIONARY:
				continue

			var desc_val = meta.get("description")
			var prime_id       := String(meta.get("shortId", ""))
			var name           := String(meta.get("name", ""))
			var desc           := "" if desc_val == null else str(desc_val)
			var created_at_raw := String(meta.get("createdAt", ""))
			var likes          := int(meta.get("likes", 0))
			var is_public      := bool(meta.get("public", true))

			if name == "":
				name = prime_id

			# Simple date formatting: just take YYYY-MM-DD part if present
			var date_label_text := created_at_raw
			if created_at_raw.length() >= 10:
				date_label_text = created_at_raw.substr(0, 10)

			# --- DATE (first column) ---
			var date_lbl := Label.new()
			date_lbl.text = date_label_text
			date_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			date_lbl.modulate = Color(1, 1, 1, 0.55)
			date_lbl.add_theme_constant_override("margin_right", 6)

			# Name (expand)
			var name_lbl := Label.new()
			name_lbl.text = name
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			# Likes
			var likes_lbl := Label.new()
			likes_lbl.text = "♥ " + str(likes)
			likes_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END

			# Copy link button
			var link_btn := Button.new()
			link_btn.flat = true
			link_btn.focus_mode = Control.FOCUS_NONE
			link_btn.icon = preload("res://addons/primes/link.svg")
			var normal_col  = Color(1, 1, 1, 0.8)
			var hover_col   = Color(1, 1, 1, 1.0)
			var pressed_col = EditorInterface.get_editor_theme().get_color("icon_pressed_color", "Button")
			link_btn.add_theme_color_override("icon_normal_color", normal_col)
			link_btn.add_theme_color_override("icon_hover_color", hover_col)
			link_btn.add_theme_color_override("icon_pressed_color", pressed_col)
			link_btn.tooltip_text = "Copy share link"
			link_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			link_btn.set_meta("prime_id", prime_id)
			link_btn.pressed.connect(_on_copy_link_pressed.bind(link_btn))

			# Hide/Show button
			var vis_btn := Button.new()
			vis_btn.flat = true
			vis_btn.focus_mode = Control.FOCUS_NONE
			vis_btn.set_meta("prime_id", prime_id)
			vis_btn.set_meta("is_public", is_public)
			vis_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			_update_visibility_icon(vis_btn, is_public)
			vis_btn.pressed.connect(_on_toggle_visibility_pressed.bind(vis_btn))

			# Edit button
			var edit_btn := Button.new()
			edit_btn.focus_mode = Control.FOCUS_NONE
			edit_btn.icon = EditorInterface.get_editor_theme().get_icon("Edit", "EditorIcons")
			edit_btn.tooltip_text = "Edit name and description"
			edit_btn.flat = true
			edit_btn.set_meta("prime_id", prime_id)
			edit_btn.set_meta("name", name)
			edit_btn.set_meta("description", desc)
			edit_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			edit_btn.pressed.connect(_on_edit_prime_pressed.bind(edit_btn))

			# Add to row
			row.add_child(date_lbl)
			row.add_child(name_lbl)
			row.add_child(likes_lbl)
			row.add_child(link_btn)
			row.add_child(vis_btn)
			row.add_child(edit_btn)
		else:
			# ----- PLACEHOLDER ROWS -----
			# If there are *no* items at all, show the message in the middle row
			if num_items == 0 and i == 1:
				var lbl := Label.new()
				lbl.text = "You haven't published anything yet"
				lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				row.add_child(lbl)
			# otherwise leave the row empty (background only)

		published_list.add_child(row_panel)

func _on_copy_link_pressed(button: Button) -> void:
	var prime_id := String(button.get_meta("prime_id"))
	if prime_id == "":
		return

	var link := "https://ole-luk-oie.com/primes/i?id=" + prime_id
	DisplayServer.clipboard_set(link)
	await _append_log("[i]Link copied:[/i] " + link)

func _on_toggle_visibility_pressed(button: Button) -> void:
	if _token == "" or _token == null:
		await _append_log("[color=orange]Please sign in again (missing token).[/color]")
		return

	var prime_id := String(button.get_meta("prime_id"))
	var is_public := bool(button.get_meta("is_public"))

	var new_public := !is_public

	button.disabled = true

	var res: Dictionary = await exporter.set_prime_visibility(
		self,
		_token,
		prime_id,
		new_public,
		Callable(self, "_append_log")
	)

	button.disabled = false

	if not res.get("success", false):
		# revert UI state
		button.set_meta("is_public", is_public)
		_update_visibility_icon(button, is_public)

		await _append_log(
			"[color=red]Failed to update visibility for %s:[/color] %s"
			% [prime_id, String(res.get("error", "unknown"))]
		)
		return

	# server accepted → commit UI state
	button.set_meta("is_public", new_public)
	_update_visibility_icon(button, new_public)
	await _append_log(
		"[i]Toggled visibility for %s → %s[/i]"
		% [prime_id, "public" if new_public else "hidden"]
	)

func _update_visibility_icon(btn: Button, is_public: bool) -> void:
	if is_public:
		btn.icon = EditorInterface.get_editor_theme().get_icon("GuiVisibilityVisible", "EditorIcons")
	else:
		btn.icon = EditorInterface.get_editor_theme().get_icon("GuiVisibilityHidden", "EditorIcons")

func _on_edit_prime_pressed(button: Button) -> void:
	var prime_id := String(button.get_meta("prime_id"))

	_editing_prime_id = prime_id

	var name = String(button.get_meta("name", ""))
	var desc = String(button.get_meta("description", ""))

	edit_name_le.text = name
	edit_desc_te.text = desc

	edit_dialog.popup_centered()
	edit_name_le.grab_focus()

func _on_edit_dialog_confirmed() -> void:
	if _editing_prime_id == "":
		return

	var new_name := edit_name_le.text.strip_edges()
	var new_desc := edit_desc_te.text.strip_edges()

	# fire-and-forget-ish; we await so errors can be logged
	await _apply_prime_meta_update(_editing_prime_id, new_name, new_desc)
	
	_update_primes()
	

func _apply_prime_meta_update(prime_id: String, name: String, desc: String) -> void:
	if _token.is_empty():
		await _append_log("[color=red]Cannot edit: missing auth token.[/color]")
		return

	var res := await exporter.update_prime_meta(
		self,
		_token,
		prime_id,
		name,
		desc,
		Callable(self, "_append_log")
	)

	if not res.get("success", false):
		await _append_log(
			"[color=red]Update failed for %s:[/color] %s"
			% [prime_id, String(res.get("error", "unknown"))]
		)
		return

	await _append_log("[color=green]Updated %s[/color]" % prime_id)
	edit_dialog.hide()

	# Option A: refresh list from server (simple, always consistent)
	var info := await exporter.fetch_user_info(self, _token, Callable(self, "_append_log"))
	if info.get("success", false):
		var games = info.get("primes", [])
		if typeof(games) == TYPE_ARRAY:
			update_published_list(games)


# --- Enforce 255-char cap on Description ---
func _on_desc_text_changed() -> void:
	var t := desc_te.text
	if t.length() > DESC_MAX:
		var cl := desc_te.get_caret_line()
		var cc := desc_te.get_caret_column()

		desc_te.text = t.substr(0, DESC_MAX)

		# Restore caret safely
		var line := min(cl, desc_te.get_line_count() - 1)
		var col := min(cc, desc_te.get_line(line).length())
		desc_te.set_caret_line(line)
		desc_te.set_caret_column(col)

# --- Sign-In ---
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
		#push_warning("Please enter your email.")
		return

	_current_email = email
	sign_in_btn.disabled = true

	var start_res: Dictionary = await exporter.start_email_sign_in(
		self,
		email,
		Callable(self, "_append_log")
	)

	if not start_res.get("success", false):
		sign_in_btn.disabled = false
		await _append_log(
			"[color=red]Auth start failed:[/color] %s"
			% String(start_res.get("error", "unknown"))
		)
		return

	_session_id = int(start_res.get("session_id", -1))
	if _session_id <= 0:
		sign_in_btn.disabled = false
		await _append_log("[color=red]Invalid session id returned.[/color]")
		return

	# Move to CODE step
	_auth_step = AUTH_STEP_CODE
	sign_label.text = "Enter verification code:"
	email_le.text = ""
	email_le.placeholder_text = ""
	sign_in_btn.text = "Verify"
	sign_in_btn.disabled = false

	await _append_log("Verification code sent to [b]%s[/b]. Please check your inbox." % _current_email)
	email_le.grab_focus()

func _handle_code_step() -> void:
	var code: String = email_le.text.strip_edges()
	if code == "":
		#push_warning("Please enter the verification code.")
		return

	sign_in_btn.disabled = true

	var verify_res: Dictionary = await exporter.verify_email_code(
		self,
		_session_id,
		code,
		Callable(self, "_append_log")
	)

	if not verify_res.get("success", false):
		sign_in_btn.disabled = false
		await _append_log(
			"[color=red]Code verification failed:[/color] %s"
			% String(verify_res.get("error", "unknown"))
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
		await _append_log("[color=red]Verify: invalid user_id.[/color]")
		return
	if _token.is_empty():
		sign_in_btn.disabled = false
		await _append_log("[color=red]Verify: missing token.[/color]")
		return

	if not needs_username:
		# Finished auth – mark signed in and show publish
		_finish_sign_in()
		sign_in_btn.disabled = false
	else:
		# Move to USERNAME step
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
		#push_warning("Please enter a username.")
		return

	sign_in_btn.disabled = true

	var uname_res: Dictionary = await exporter.claim_username(
		self,
		_user_id,
		username,
		Callable(self, "_append_log")
	)

	if not uname_res.get("success", false):
		sign_in_btn.disabled = false
		await _append_log(
			"[color=red]Username claim failed:[/color] %s"
			% String(uname_res.get("error", "unknown"))
		)
		return

	_username = username

	_finish_sign_in()
	sign_in_btn.disabled = false

func _finish_sign_in() -> void:
	if plugin:
		plugin.save_token(_token)

	var display_name := (_username if _username != "" else _current_email)
	if display_name == "":
		display_name = "(unknown)"

	author_val.text = "[font_size=18][b]%s[/b]" % display_name
	await _append_log("[color=green]Signed in as %s[/color]" % display_name)

	_update_primes()

	_show_publish()

# returns false only if token has expired
func _update_primes() -> bool:
	var info: Dictionary = await exporter.fetch_user_info(
		self,
		_token,
		Callable(self, "_append_log")
	)

	if info.get("success", false):
		_username = String(info.get("username", ""))
		if _username == "":
			_username = "(unknown)"

		author_val.text = "[font_size=18][b]%s[/b]" % _username

		var games = info.get("primes", [])
		if typeof(games) == TYPE_ARRAY:
			update_published_list(games)
		else:
			update_published_list([])

		return true
	else:
		var error = String(info.get("error", ""))
		if error == "token_expired":
			await _append_log("[color=orange]Session expired. Please sign in again.[/color]")
			_token = ""
			plugin.clear_token()
			_show_sign_in()
			return false
		else:
			await _append_log("[color=orange]Failed to fetch user data. The updates to the list of primes might not be visible right away.[/color]")
		return true

func _on_logout() -> void:
	_current_email = ""
	_username = ""
	_token = ""
	_user_id = -1
	_session_id = -1

	author_val.text = ""

	if plugin:
		plugin.clear_token()

	email_le.text = ""
	_show_sign_in()


# --- Publish ---
func _on_publish() -> void:
	# Remember lock state BEFORE we do anything that might create it
	_remember_recovery_lock_state()

	var name: String = name_le.text.strip_edges()
	var desc: String = desc_te.text.strip_edges()

	# Hide-from-feed means "unlisted". Map to is_public=false for uploader.
	var hide_from_feed: bool = hide_cb.button_pressed
	var is_public: bool = not hide_from_feed

	publish_btn.disabled = true
	await _append_log("Packing project…")
	var pkg := await exporter.pack_zip(Callable(self, "_append_log"))
	if pkg == "":
		await _append_log("[color=red]Packing failed.[/color]")
		publish_btn.disabled = false
		return

	await _append_log("Done. Now uploading…")
	await _flush_ui()
	var result = await exporter.upload_zip_with_meta(self, _token, pkg, "ole-luk-oie", is_public, name, desc)

	if !result.get("success", false):
		await _append_log("[color=red]Failed to publish[/color] %s" % String(result.get("error", "")))
	else:
		var link: String = "https://ole-luk-oie.com/primes/i?id=" + String(result["id"])
		DisplayServer.clipboard_set(link)
		await _append_log("[color=green]Published[/color] %s. Link copied: %s"
			% [
				#name if name != "" else "(auto)", 
				("Public" if is_public else "Unlisted"), 
				link
				])

	publish_btn.disabled = false
	
	# Remove the lock iff we created it
	_clear_recovery_lock_if_new()
	
	_update_primes()

func _append_log(msg: String) -> void:
	if not _log_cleared:
		log_rt.clear()       # remove "Logs will appear here..."
		_log_cleared = true
		log_rt.append_text("• %s" % msg)
	else:
		log_rt.append_text("\n• %s" % msg)
	log_rt.scroll_to_line(log_rt.get_line_count())
	# Let the editor render this line before we continue
	await get_tree().process_frame
	await get_tree().process_frame
	
# reliable UI flush (works in editor/tool scripts)
func _flush_ui() -> void:
	await get_tree().create_timer(0.5).timeout  # yield to idle
	await get_tree().process_frame              # ensure a frame is drawn
