@tool
class_name AuthorSection
extends HBoxContainer

signal logout_requested

var _name_font_px := 0

@onready var author_icon: TextureRect = $AuthorIcon
@onready var author_value: Label = $AuthorValue
@onready var logout_btn: Button = $LogoutBtn


func _ready() -> void:
	var theme := EditorInterface.get_editor_theme()
	author_value.add_theme_font_override("font", theme.get_font("bold", "EditorFonts"))
	author_value.add_theme_font_size_override(
		"font_size", theme.get_font_size("main_size", "EditorFonts") * 1.3
	)

	author_icon.texture = PrimesUIScaler.icon("res://addons/primes/drawables/person.svg")
	author_icon.custom_minimum_size = Vector2(16, 16)
	author_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED

	logout_btn.icon = PrimesUIScaler.icon("res://addons/primes/drawables/logout.svg")
	logout_btn.custom_minimum_size = Vector2(20, 20)
	logout_btn.expand_icon = false

	logout_btn.flat = true
	logout_btn.focus_mode = Control.FOCUS_NONE
	logout_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	logout_btn.modulate = Color(1, 1, 1, 0.8)
	logout_btn.mouse_entered.connect(func(): logout_btn.modulate = Color(0.7, 0.7, 1))
	logout_btn.mouse_exited.connect(func(): logout_btn.modulate = Color(1, 1, 1, 0.8))

	logout_btn.pressed.connect(func(): logout_requested.emit())


func set_username(username: String) -> void:
	var display_name := username if username != "" else "(unknown)"
	author_value.text = display_name


func clear() -> void:
	author_value.text = ""
