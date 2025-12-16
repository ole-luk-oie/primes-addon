@tool
extends VBoxContainer
class_name PublishForm

signal publish_requested(name: String, description: String, hide_from_feed: bool)
signal run_on_phone_requested(name: String, description: String)

const DESC_MAX := 255

@onready var name_edit: LineEdit = $CenterRow/FormInner/NameGroup/Name
@onready var desc_edit: TextEdit = $CenterRow/FormInner/DescGroup/Desc
@onready var hide_cb: CheckBox = $CenterRow/FormInner/ActionArea/HideFromFeed
@onready var publish_btn: Button = $CenterRow/FormInner/ActionArea/PublishBtn
@onready var run_on_phone_btn: Button = $CenterRow/FormInner/ActionArea/RunOnPhoneBtn

var _ui_enabled: bool = true
var _device_available: bool = false


func _ready() -> void:
	desc_edit.custom_minimum_size = PrimesUIScaler.v2(0, 80)
	publish_btn.custom_minimum_size = PrimesUIScaler.v2(140, 0)
	run_on_phone_btn.custom_minimum_size = PrimesUIScaler.v2(160, 0)

	publish_btn.pressed.connect(_on_publish_pressed)
	run_on_phone_btn.pressed.connect(_on_run_on_phone_pressed)
	desc_edit.text_changed.connect(_on_desc_text_changed)
	name_edit.grab_focus()


func _on_run_on_phone_pressed() -> void:
	var name := name_edit.text.strip_edges()
	var desc := desc_edit.text.strip_edges()
	run_on_phone_requested.emit(name, desc)


func _on_publish_pressed() -> void:
	var name := name_edit.text.strip_edges()
	var desc := desc_edit.text.strip_edges()
	var hide_from_feed := hide_cb.button_pressed

	publish_requested.emit(name, desc, hide_from_feed)


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


func _refresh_buttons() -> void:
	# Publish depends only on “UI busy” state.
	publish_btn.disabled = not _ui_enabled

	# Run on phone depends on both: UI must be enabled AND a device present.
	var dev_enabled := _ui_enabled and _device_available
	run_on_phone_btn.disabled = not dev_enabled

	if dev_enabled:
		run_on_phone_btn.tooltip_text = "Run current project on connected Android device"
	elif _device_available:
		# Shouldn’t really happen, but just in case
		run_on_phone_btn.tooltip_text = "UI is busy"
	else:
		run_on_phone_btn.tooltip_text = "No Android device detected via adb"


func set_enabled(enabled: bool) -> void:
	_ui_enabled = enabled
	_refresh_buttons()


func set_dev_run_available(available: bool) -> void:
	_device_available = available
	_refresh_buttons()


func clear_form() -> void:
	name_edit.text = ""
	desc_edit.text = ""
	hide_cb.button_pressed = false
