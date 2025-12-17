@tool
class_name EditPrimeDialog
extends AcceptDialog

signal update_requested(prime_id: String, prev_name: String, name: String, description: String)

const DESC_MAX := 255

var _editing_prime_id: String = ""
var _prev_name = ""

@onready var edit_name_le: LineEdit = $EditVBox/NameGroup/NameEdit
@onready var edit_desc_te: TextEdit = $EditVBox/DescGroup/DescEdit


func _ready() -> void:
	var ok_btn = get_ok_button()
	add_cancel_button("Close")
	if ok_btn:
		ok_btn.text = "Update"

	confirmed.connect(_on_confirmed)
	edit_desc_te.text_changed.connect(_on_edit_desc_changed)


func show_edit_dialog(prime_id: String, name: String, description: String) -> void:
	_editing_prime_id = prime_id
	edit_name_le.text = name
	edit_desc_te.text = description

	_prev_name = name

	popup_centered()
	edit_name_le.grab_focus()


func _on_confirmed() -> void:
	if _editing_prime_id == "":
		return

	var new_name := edit_name_le.text.strip_edges()
	var new_desc := edit_desc_te.text.strip_edges()

	update_requested.emit(_editing_prime_id, _prev_name, new_name, new_desc)


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
