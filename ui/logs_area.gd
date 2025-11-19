@tool
extends RichTextLabel
class_name LogsArea

var _log_cleared := false

func _ready() -> void:
	bbcode_enabled = true
	focus_mode = Control.FOCUS_ALL
	selection_enabled = true
	text = "[i]Logs will appear here...[/i]"

func append_log(msg: String) -> void:
	if not _log_cleared:
		clear()
		_log_cleared = true
		append_text("• %s" % msg)
	else:
		append_text("\n• %s" % msg)
	
	scroll_to_line(get_line_count())
	
	# Let the editor render
	await get_tree().process_frame
	await get_tree().process_frame

func clear_logs() -> void:
	clear()
	_log_cleared = false
	text = "[i]Logs will appear here...[/i]"
