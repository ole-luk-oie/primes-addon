@tool
extends HBoxContainer
class_name AuthorSection

signal logout_requested

@onready var author_icon: TextureRect = $AuthorIcon
@onready var author_value: RichTextLabel = $AuthorValue
@onready var logout_btn: Button = $LogoutBtn

var ROW_BG_EMPTY := StyleBoxEmpty.new()

func _ready() -> void:
	logout_btn.flat = true
	logout_btn.focus_mode = Control.FOCUS_NONE
	logout_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	logout_btn.modulate = Color(1, 1, 1, 0.8)
	logout_btn.mouse_entered.connect(func(): logout_btn.modulate = Color(0.7, 0.7, 1))
	logout_btn.mouse_exited.connect(func(): logout_btn.modulate = Color(1, 1, 1, 0.8))
	
	logout_btn.pressed.connect(func(): logout_requested.emit())

func set_username(username: String) -> void:
	var display_name := username if username != "" else "(unknown)"
	author_value.text = "[font_size=18][b]%s[/b]" % display_name

func clear() -> void:
	author_value.text = ""
