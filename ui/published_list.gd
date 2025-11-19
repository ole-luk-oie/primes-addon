@tool
extends ScrollContainer
class_name PublishedList

signal copy_link_requested(prime_id: String)
signal toggle_visibility_requested(prime_id: String, is_public: bool)
signal edit_prime_requested(prime_id: String, name: String, description: String)

@onready var list_container: VBoxContainer = $PublishedListContainer

var ROW_BG_DARK := StyleBoxFlat.new()
var ROW_BG_LIGHT := StyleBoxFlat.new()

func _ready() -> void:
	var theme := EditorInterface.get_editor_theme()
	
	ROW_BG_DARK = StyleBoxFlat.new()
	ROW_BG_DARK.bg_color = theme.get_color("dark_color_1", "Editor")
	ROW_BG_DARK.set_content_margin_all(3)
	ROW_BG_DARK.draw_center = true
	
	ROW_BG_LIGHT = StyleBoxFlat.new()
	ROW_BG_LIGHT.bg_color = theme.get_color("dark_color_2", "Editor")
	ROW_BG_LIGHT.set_content_margin_all(3)
	ROW_BG_LIGHT.draw_center = true
	
	list_container.add_theme_constant_override("separation", 0)

func update_list(items: Array) -> void:
	for c in list_container.get_children():
		c.queue_free()
	
	var num_items := items.size()
	var total_rows := max(num_items, 3)
	
	for i in range(total_rows):
		var row_panel := _create_row_panel(i)
		
		if i < num_items:
			_populate_prime_row(row_panel, items[i])
		elif num_items == 0 and i == 1:
			_populate_empty_message_row(row_panel)
		
		list_container.add_child(row_panel)

func _create_row_panel(index: int) -> PanelContainer:
	var row_panel := PanelContainer.new()
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_panel.custom_minimum_size = Vector2(0, 40)
	row_panel.add_theme_stylebox_override(
		"panel",
		ROW_BG_DARK if index % 2 == 1 else ROW_BG_LIGHT
	)
	return row_panel

func _populate_prime_row(row_panel: PanelContainer, meta: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	row_panel.add_child(row)
	
	var desc_val = meta.get("description")
	var prime_id := String(meta.get("shortId", ""))
	var name := String(meta.get("name", ""))
	var desc := "" if desc_val == null else str(desc_val)
	var created_at_raw := String(meta.get("createdAt", ""))
	var likes := int(meta.get("likes", 0))
	var is_public := bool(meta.get("public", true))
	
	if name == "":
		name = prime_id
	
	var date_label_text := created_at_raw
	if created_at_raw.length() >= 10:
		date_label_text = created_at_raw.substr(0, 10)
	
	# Date
	var date_lbl := Label.new()
	date_lbl.text = date_label_text
	date_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	date_lbl.modulate = Color(1, 1, 1, 0.55)
	
	# Name
	var name_lbl := Label.new()
	name_lbl.text = name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Likes
	var likes_lbl := Label.new()
	likes_lbl.text = "♥ " + str(likes)
	likes_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
	
	# Copy link button
	var link_btn := _create_link_button(prime_id)
	
	# Visibility toggle button
	var vis_btn := _create_visibility_button(prime_id, is_public)
	
	# Edit button
	var edit_btn := _create_edit_button(prime_id, name, desc)
	
	row.add_child(date_lbl)
	row.add_child(name_lbl)
	row.add_child(likes_lbl)
	row.add_child(link_btn)
	row.add_child(vis_btn)
	row.add_child(edit_btn)

func _populate_empty_message_row(row_panel: PanelContainer) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	row_panel.add_child(row)
	
	var lbl := Label.new()
	lbl.text = "You haven't published anything yet"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

func _create_link_button(prime_id: String) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.icon = preload("res://addons/primes/drawables/link.svg")
	
	var normal_col = Color(1, 1, 1, 0.8)
	var hover_col = Color(1, 1, 1, 1.0)
	var pressed_col = EditorInterface.get_editor_theme().get_color("icon_pressed_color", "Button")
	btn.add_theme_color_override("icon_normal_color", normal_col)
	btn.add_theme_color_override("icon_hover_color", hover_col)
	btn.add_theme_color_override("icon_pressed_color", pressed_col)
	
	btn.tooltip_text = "Copy share link"
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_meta("prime_id", prime_id)
	btn.pressed.connect(func(): copy_link_requested.emit(prime_id))
	
	return btn

func _create_visibility_button(prime_id: String, is_public: bool) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_meta("prime_id", prime_id)
	btn.set_meta("is_public", is_public)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_update_visibility_icon(btn, is_public)
	btn.pressed.connect(func(): toggle_visibility_requested.emit(prime_id, btn.get_meta("is_public")))
	
	return btn

func _create_edit_button(prime_id: String, name: String, desc: String) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.icon = EditorInterface.get_editor_theme().get_icon("Edit", "EditorIcons")
	btn.tooltip_text = "Edit name and description"
	btn.flat = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(func(): edit_prime_requested.emit(prime_id, name, desc))
	
	return btn

func _update_visibility_icon(btn: Button, is_public: bool) -> void:
	if is_public:
		btn.icon = EditorInterface.get_editor_theme().get_icon("GuiVisibilityVisible", "EditorIcons")
	else:
		btn.icon = EditorInterface.get_editor_theme().get_icon("GuiVisibilityHidden", "EditorIcons")

func update_visibility_state(prime_id: String, is_public: bool) -> void:
	for row_panel in list_container.get_children():
		var row = row_panel.get_child(0) if row_panel.get_child_count() > 0 else null
		if not row:
			continue
		
		for child in row.get_children():
			if child is Button and child.has_meta("prime_id"):
				if child.get_meta("prime_id") == prime_id and child.has_meta("is_public"):
					child.set_meta("is_public", is_public)
					_update_visibility_icon(child, is_public)
					return
