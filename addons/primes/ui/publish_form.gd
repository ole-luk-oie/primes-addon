@tool
class_name PublishForm
extends VBoxContainer

signal publish_requested(name: String, description: String, hide_from_feed: bool)

const DESC_MAX := 255

var _ui_enabled: bool = true
var _device_available: bool = false

@onready var desc_edit: TextEdit = $CenterRow/FormInner/DescGroup/Desc
@onready var hide_cb: CheckBox = $CenterRow/FormInner/ActionArea/HideFromFeed
@onready var publish_btn: Button = $CenterRow/FormInner/ActionArea/PublishBtn
@onready var run_on_phone_btn: Button = $CenterRow/FormInner/ActionArea/RunOnPhoneBtn


func _ready() -> void:
	desc_edit.custom_minimum_size = PrimesUIScaler.v2(0, 80)
	publish_btn.custom_minimum_size = PrimesUIScaler.v2(140, 0)
	run_on_phone_btn.custom_minimum_size = PrimesUIScaler.v2(160, 0)

	publish_btn.pressed.connect(_on_publish_pressed)
	desc_edit.text_changed.connect(_on_desc_text_changed)
	desc_edit.grab_focus()


func get_run_button() -> Button:
	return run_on_phone_btn


func _on_publish_pressed() -> void:
	var desc := desc_edit.text.strip_edges()
	var hide_from_feed := hide_cb.button_pressed
	publish_requested.emit("", desc, hide_from_feed)


func get_description_text() -> String:
	return desc_edit.text.strip_edges()


func _on_desc_text_changed() -> void:
	var t := desc_edit.text
	if t.length() > DESC_MAX:
		var cl := desc_edit.get_caret_line()
		var cc := desc_edit.get_caret_column()

		desc_edit.text = t.substr(0, DESC_MAX)

		var line := min(cl, desc_edit.get_line_count() - 1)
		var col := min(cc, desc_edit.get_line(line).length())
		desc_edit.set_caret_line(line)
		desc_edit.set_caret_column(col)


func _refresh_ui_state() -> void:
	# Publish depends only on “UI busy” state.
	publish_btn.disabled = not _ui_enabled

	# Other inputs follow UI enabled state.
	desc_edit.editable = _ui_enabled
	hide_cb.disabled = not _ui_enabled

	# Run button is controlled by CloudPublisherPanel (shared with toolbar button).


func set_enabled(enabled: bool) -> void:
	_ui_enabled = enabled
	_refresh_ui_state()


func set_dev_run_available(available: bool) -> void:
	# Kept for compatibility with existing calls; run button state is managed by the panel.
	_device_available = available


func clear_form() -> void:
	desc_edit.text = ""
	hide_cb.button_pressed = false
