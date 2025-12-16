@tool
extends AcceptDialog
class_name FlagsDialog

signal appeal_submitted(prime_id: String, flag_id: int, message: String)

@onready var _root_vbox: VBoxContainer = $VBoxContainer
@onready var _list_container: VBoxContainer = $VBoxContainer/ScrollContainer/FlagsList

var _prime_id: String = ""
var _flag_rows := {}  # flag_id -> { vbox, header, appeal_row, appeal_btn, appeal_input }


func _ready() -> void:
	var ok := get_ok_button()
	if ok:
		ok.text = "Close"

	if _root_vbox:
		_root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL


func show_flags(prime_id: String, prime_name: String, flags: Array) -> void:
	_prime_id = prime_id

	title = "Flags for %s" % prime_name

	if _list_container:
		for child in _list_container.get_children():
			child.queue_free()
		_flag_rows.clear()

		if flags.is_empty():
			var empty_lbl := Label.new()
			empty_lbl.text = "No flags for this prime."
			empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_list_container.add_child(empty_lbl)
		else:
			for f in flags:
				_add_flag_row(f)

	popup_centered_ratio(0.6)


func _add_flag_row(flag_data: Dictionary) -> void:
	if not _list_container:
		return

	print(str(flag_data))

	var flag_id: int = int(flag_data.get("id", 0))
	var reason := String(flag_data.get("reason", ""))
	var status := String(flag_data.get("status", ""))
	var reporter_comment := String(flag_data.get("comment", "<empty>"))
	var created_at := String(flag_data.get("createdAt", ""))

	if reporter_comment.is_empty():
		reporter_comment = "(no comment from reporter)"

	# Container for one flag
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size = Vector2(0, 80)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.225, 0.225, 0.225, 1.0)
	sb.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var header_lbl := Label.new()
	header_lbl.text = "[%s] %s (%s)" % [created_at, reason, status]
	header_lbl.autowrap_mode = TextServer.AutowrapMode.AUTOWRAP_WORD
	vbox.add_child(header_lbl)

	var reporter_lbl := Label.new()
	reporter_lbl.text = "Comment: " + reporter_comment
	reporter_lbl.autowrap_mode = TextServer.AutowrapMode.AUTOWRAP_WORD
	vbox.add_child(reporter_lbl)

	# Case 1 — CRASHED flags are NOT appealable
	if reason == "CRASHED":
		var info := RichTextLabel.new()
		info.bbcode_enabled = true
		info.fit_content = true
		info.scroll_active = false
		info.autowrap_mode = TextServer.AutowrapMode.AUTOWRAP_WORD
		info.text = "[i]Crash flags cannot be appealed. Please upload a fixed version and the system will stop flagging new crashes.[/i]"
		vbox.add_child(info)
		_list_container.add_child(panel)
		return

	# Case 2 — APPEALED
	if status == "APPEALED":
		var info := RichTextLabel.new()
		info.bbcode_enabled = true
		info.fit_content = true
		info.scroll_active = false
		info.autowrap_mode = TextServer.AutowrapMode.AUTOWRAP_WORD
		info.text = "[i]You have already appealed this flag. Our team is reviewing it.[/i]"
		vbox.add_child(info)
		_list_container.add_child(panel)
		return

	# Case 3 — CONFIRMED
	if status == "CONFIRMED":
		var info := RichTextLabel.new()
		info.bbcode_enabled = true
		info.fit_content = true
		info.scroll_active = false
		info.autowrap_mode = TextServer.AutowrapMode.AUTOWRAP_WORD
		info.text = "[i]Your appeal was reviewed. The flag was confirmed as valid.[/i]"
		vbox.add_child(info)
		_list_container.add_child(panel)
		return

	# Case 4 — DISMISSED
	if status == "DISMISSED":
		var info := RichTextLabel.new()
		info.bbcode_enabled = true
		info.fit_content = true
		info.scroll_active = false
		info.autowrap_mode = TextServer.AutowrapMode.AUTOWRAP_WORD
		info.text = "[i]Your appeal was reviewed. The flag was dismissed.[/i]"
		vbox.add_child(info)
		_list_container.add_child(panel)
		return

	# Case 5 — OPEN (default): show the input + button
	var appeal_hb := HBoxContainer.new()
	appeal_hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	appeal_hb.add_theme_constant_override("separation", 8)
	vbox.add_child(appeal_hb)

	var appeal_input := LineEdit.new()
	appeal_input.placeholder_text = "Explain or contest this flag..."
	appeal_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	appeal_hb.add_child(appeal_input)

	var appeal_btn := Button.new()
	appeal_btn.text = "Appeal"
	appeal_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	appeal_hb.add_child(appeal_btn)

	# Track this row so we can mutate it later
	_flag_rows[flag_id] = {
		"vbox": vbox,
		"header": header_lbl,
		"appeal_row": appeal_hb,
		"appeal_btn": appeal_btn,
		"appeal_input": appeal_input,
	}

	appeal_btn.pressed.connect(
		func():
			var msg := String(appeal_input.text).strip_edges()
			# Locally lock UI while request is in flight
			appeal_btn.disabled = true
			appeal_input.editable = false
			appeal_submitted.emit(_prime_id, flag_id, msg)
	)

	_list_container.add_child(panel)


func set_appeal_enabled(flag_id: int, enabled: bool) -> void:
	if not _flag_rows.has(flag_id):
		return

	var row = _flag_rows[flag_id]
	var btn: Button = row.get("appeal_btn")
	var input: LineEdit = row.get("appeal_input")

	if btn and is_instance_valid(btn):
		btn.disabled = not enabled
	if input and is_instance_valid(input):
		input.editable = enabled


func mark_flag_appealed(flag_id: int) -> void:
	if not _flag_rows.has(flag_id):
		return

	var row = _flag_rows[flag_id]
	var vbox: VBoxContainer = row.get("vbox")
	var header_lbl: Label = row.get("header")
	var appeal_row: HBoxContainer = row.get("appeal_row")

	# Remove the input row
	if appeal_row and is_instance_valid(appeal_row):
		appeal_row.queue_free()

	# Update header status text to APPEALED
	if header_lbl and is_instance_valid(header_lbl):
		var txt := String(header_lbl.text)
		var open_idx := txt.rfind("(")
		var close_idx := txt.rfind(")")
		if open_idx != -1 and close_idx > open_idx:
			header_lbl.text = txt.substr(0, open_idx + 1) + "APPEALED" + txt.substr(close_idx)
		else:
			header_lbl.text = txt + " (APPEALED)"

	# Add APPEALED info text
	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.autowrap_mode = TextServer.AutowrapMode.AUTOWRAP_WORD
	info.text = "[i]You’ve submitted an appeal for this flag. Our team is reviewing it.[/i]"
	vbox.add_child(info)

	# No longer need to treat this as an OPEN row
	_flag_rows.erase(flag_id)
