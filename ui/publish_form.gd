@tool
extends VBoxContainer
class_name PublishForm

signal publish_requested(name: String, description: String, hide_from_feed: bool)

const DESC_MAX := 255

@onready var name_edit: LineEdit = $CenterRow/FormInner/NameGroup/Name
@onready var desc_edit: TextEdit = $CenterRow/FormInner/DescGroup/Desc
@onready var hide_cb: CheckBox = $CenterRow/FormInner/ActionArea/HideFromFeed
@onready var publish_btn: Button = $CenterRow/FormInner/ActionArea/PublishBtn

func _ready() -> void:
	publish_btn.pressed.connect(_on_publish_pressed)
	desc_edit.text_changed.connect(_on_desc_text_changed)
	name_edit.grab_focus()

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

func set_enabled(enabled: bool) -> void:
	publish_btn.disabled = not enabled

func clear_form() -> void:
	name_edit.text = ""
	desc_edit.text = ""
	hide_cb.button_pressed = false
