@tool
extends EditorPlugin

var panel: CloudPublisherPanel    # class defined below
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

# --- Main Screen hooks (this creates the button next to 2D/3D/Script/AssetLib) ---
func _get_plugin_name() -> String: return "Publish"
func _has_main_screen() -> bool: return true
func _make_visible(visible: bool) -> void:
	if not is_instance_valid(panel): return
	panel.visible = visible
	if visible:
		panel.ensure_correct_subview()  # shows Sign-In first if not authenticated

# --- Simple auth persistence ---
func save_auth(email: String, api_key: String, token: String) -> void:
	var es := get_editor_interface().get_editor_settings()
	es.set_setting("cloud_publisher/email", email)
	es.set_setting("cloud_publisher/api_key", api_key)
	es.set_setting("cloud_publisher/token", token)
	es.save()

func load_auth() -> Dictionary:
	var es := get_editor_interface().get_editor_settings()
	return {
		"email":   es.get_setting("cloud_publisher/email"),
		"api_key": es.get_setting("cloud_publisher/api_key"),
		"token":   es.get_setting("cloud_publisher/token"),
	}

func is_signed_in() -> bool:
	var a: Dictionary = load_auth()
	return String(a.get("token", "")) != ""
