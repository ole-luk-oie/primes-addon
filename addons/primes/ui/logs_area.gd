@tool
extends RichTextLabel
class_name LogsArea

var _log_cleared := false


func _ready() -> void:
	bbcode_enabled = true
	focus_mode = Control.FOCUS_ALL
	selection_enabled = true
	text = "[i]Logs will appear here...[/i]"


func append_log(msg: String, color: String = "default") -> void:
	if not _log_cleared:
		clear()
		_log_cleared = true
		append(msg, color, false)
	else:
		append(msg, color)

	scroll_to_line(get_line_count())

	# Let the editor render
	await get_tree().process_frame
	await get_tree().process_frame


func append(msg: String, color: String = "default", new_line: bool = true):
	var with_dot
	if color == "orange":
		with_dot = "[color=orange]⦁[/color] %s" % msg
	elif color == "green":
		with_dot = "[color=green]⦁[/color] %s" % msg
	elif color == "red":
		with_dot = "[color=red]⦁[/color] %s" % msg
	else:
		with_dot = "⦁ %s" % msg

	if new_line:
		with_dot = "\n" + with_dot

	append_text(with_dot)


func clear_logs() -> void:
	clear()
	_log_cleared = false
	text = "[i]Logs will appear here...[/i]"
