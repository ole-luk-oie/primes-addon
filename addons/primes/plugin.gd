# plugin.gd
@tool
extends EditorPlugin

var panel: CloudPublisherPanel
var exporter: PrimesExporter = PrimesExporter.new()

var toolbar_run_btn: Button


func _enter_tree() -> void:
	add_export_plugin(exporter.get_plugin())

	# Create panel
	panel = preload("res://addons/primes/panel.tscn").instantiate()
	var main_screen: Control = get_editor_interface().get_editor_main_screen()
	main_screen.add_child(panel)
	panel.visible = false
	panel.plugin = self
	panel.exporter = exporter

	# Create toolbar button (do NOT add to container API)
	toolbar_run_btn = Button.new()
	toolbar_run_btn.focus_mode = Control.FOCUS_NONE
	toolbar_run_btn.icon = PrimesUIScaler.icon(
		"res://addons/primes/drawables/run_icon.svg",
		16
	)

	# Place it into the run bar directly
	call_deferred("_insert_into_runbar")

	# Connect shared logic
	call_deferred("_wire_toolbar_button")


func _insert_into_runbar() -> void:
	if not is_instance_valid(toolbar_run_btn):
		return

	var base := get_editor_interface().get_base_control()

	# Find EditorRunBar
	var run_bar := _find_descendant_by_class(base, "EditorRunBar", 12, 2000)
	if not run_bar:
		push_warning("Primes: EditorRunBar not found")
		return

	# Find wrapper PanelContainer
	var panel_container := _find_descendant_by_type(run_bar, "PanelContainer", 4, 400)
	if not panel_container:
		push_warning("Primes: runbar PanelContainer not found")
		return

	# Find actual button row
	var target_hbox := _find_descendant_by_type(panel_container, "HBoxContainer", 2, 200) as HBoxContainer
	if not target_hbox:
		push_warning("Primes: runbar button row not found")
		return

	# Add button
	target_hbox.add_child(toolbar_run_btn)

	# Move it to FIRST position
	target_hbox.move_child(toolbar_run_btn, 0)

	# Match native runbar button styling
	toolbar_run_btn.theme_type_variation = "RunBarButton"
	toolbar_run_btn.flat = false
	toolbar_run_btn.text = ""
	toolbar_run_btn.expand_icon = false

	toolbar_run_btn.custom_minimum_size = Vector2.ZERO
	toolbar_run_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toolbar_run_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _wire_toolbar_button() -> void:
	if is_instance_valid(panel) and is_instance_valid(toolbar_run_btn):
		panel.register_run_button(toolbar_run_btn)


func _exit_tree() -> void:
	# Unregister shared logic
	if is_instance_valid(panel) and is_instance_valid(toolbar_run_btn):
		panel.unregister_run_button(toolbar_run_btn)

	# Remove button safely
	if is_instance_valid(toolbar_run_btn):
		var parent := toolbar_run_btn.get_parent()
		if parent:
			parent.remove_child(toolbar_run_btn)
		toolbar_run_btn.queue_free()
		toolbar_run_btn = null

	# Remove panel
	if is_instance_valid(panel):
		panel.queue_free()
		panel = null


# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------

func _find_descendant_by_class(root: Node, clazz_name: String, max_depth: int, max_nodes: int) -> Node:
	var queue: Array = [{"n": root, "d": 0}]
	var visited := 0

	while queue.size() > 0 and visited < max_nodes:
		var item = queue.pop_front()
		var node: Node = item["n"]
		var depth: int = item["d"]
		visited += 1

		if node.get_class() == clazz_name:
			return node

		if depth >= max_depth:
			continue

		for child in node.get_children():
			if child is Node:
				queue.append({"n": child, "d": depth + 1})

	return null


func _find_descendant_by_type(root: Node, type_name: String, max_depth: int, max_nodes: int) -> Node:
	var queue: Array = [{"n": root, "d": 0}]
	var visited := 0

	while queue.size() > 0 and visited < max_nodes:
		var item = queue.pop_front()
		var node: Node = item["n"]
		var depth: int = item["d"]
		visited += 1

		if node.get_class() == type_name:
			return node

		if depth >= max_depth:
			continue

		for child in node.get_children():
			if child is Node:
				queue.append({"n": child, "d": depth + 1})

	return null


# -------------------------------------------------------------------
# EditorPlugin UI integration
# -------------------------------------------------------------------

func _get_plugin_icon() -> Texture2D:
	return PrimesUIScaler.icon("res://addons/primes/drawables/icon.svg")


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


# -------------------------------------------------------------------
# Token persistence
# -------------------------------------------------------------------

func save_token(token: String) -> void:
	get_editor_interface().get_editor_settings().set_setting("primes/token", token)


func load_token() -> String:
	var es := get_editor_interface().get_editor_settings()
	var v = es.get_setting("primes/token")
	return "" if v == null else String(v)


func clear_token() -> void:
	get_editor_interface().get_editor_settings().erase("primes/token")
