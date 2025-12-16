@tool
extends EditorPlugin

var panel: CloudPublisherPanel  # class defined below
var exporter: PrimesExporter = PrimesExporter.new()


func _enter_tree() -> void:
	add_export_plugin(exporter.get_plugin())
	# Instance our main-screen panel and add it to the editor's main screen container.
	panel = preload("res://addons/primes/panel.tscn").instantiate()
	var main_screen: Control = get_editor_interface().get_editor_main_screen()
	main_screen.add_child(panel)
	panel.visible = false
	panel.plugin = self
	panel.exporter = exporter


func _exit_tree() -> void:
	if is_instance_valid(panel):
		panel.queue_free()


func _get_plugin_icon() -> Texture2D:
	return PrimesUIScaler.icon("res://addons/primes/drawables/icon.svg")


# --- Main Screen hooks (this creates the button next to 2D/3D/Script/AssetLib) ---
func _get_plugin_name() -> String:
	return "Primes"


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if not is_instance_valid(panel):
		return
	panel.visible = visible
	if visible:
		panel.ensure_correct_subview()


# --- Simple auth persistence ---
func save_token(token: String) -> void:
	get_editor_interface().get_editor_settings().set_setting("primes/token", token)


func load_token() -> String:
	var es := get_editor_interface().get_editor_settings()
	var v = es.get_setting("primes/token")
	if v == null:
		return ""
	return String(v)


func clear_token() -> void:
	get_editor_interface().get_editor_settings().erase("primes/token")
