@tool
extends ScrollContainer
class_name PublishedList

signal copy_link_requested(prime_id: String)
signal toggle_visibility_requested(prime_id: String, name: String, is_public: bool)
signal edit_prime_requested(prime_id: String, prev_name: String, name: String, description: String)
signal flag_details_requested(prime_id: String, prime_name: String)
signal delete_prime_requested(prime_id: String, name: String)

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

	custom_minimum_size = PrimesUIScaler.v2(0.0, 240.0)


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
	row_panel.custom_minimum_size = Vector2(0, PrimesUIScaler.px(40))
	row_panel.add_theme_stylebox_override("panel", ROW_BG_DARK if index % 2 == 1 else ROW_BG_LIGHT)
	return row_panel


func _populate_prime_row(row_panel: PanelContainer, meta: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", int(PrimesUIScaler.px(8)))
	row_panel.add_child(row)

	var desc_val = meta.get("description")
	var prime_id := String(meta.get("shortId", ""))
	var name := String(meta.get("name", ""))
	var desc := "" if desc_val == null else str(desc_val)
	var created_at_raw := String(meta.get("createdAt", ""))
	var likes := int(meta.get("likes", 0))
	var is_public := bool(meta.get("public", true))
	var flagged := bool(meta.get("flagged", false))

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
	likes_lbl.text = str(likes) + " ♥ "
	likes_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END

	# Copy link button
	var link_btn := _create_link_button(prime_id)

	# Visibility toggle button
	var vis_btn := _create_visibility_button(prime_id, name, is_public, flagged)

	# Edit button
	var edit_btn := _create_edit_button(prime_id, name, desc)

	# Delete button
	var delete_btn := _create_delete_button(prime_id, name)

	# Flags button
	var flags_btn := _create_flag_button(flagged, prime_id, name)

	row.add_child(date_lbl)
	row.add_child(name_lbl)
	row.add_child(likes_lbl)
	row.add_child(link_btn)
	row.add_child(vis_btn)
	row.add_child(edit_btn)
	row.add_child(delete_btn)
	row.add_child(flags_btn)


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
	btn.icon = PrimesUIScaler.icon("res://addons/primes/drawables/link.svg")
	btn.expand_icon = false

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


func _create_visibility_button(
	prime_id: String, name: String, is_public: bool, flagged: bool
) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_meta("prime_id", prime_id)
	btn.set_meta("name", name)
	btn.set_meta("is_public", is_public)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# If this game has one or more flags, we lock visibility as "hidden"
	# and prevent the user from toggling it in the plugin.
	if flagged:
		# Visually: always show as "hidden"
		_update_visibility_icon(btn, false)

		# Logically: disable interaction
		btn.disabled = false
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.modulate = Color(1, 1, 1, 0.35)
		btn.tooltip_text = "Locked due to flags"

		# Optional: slightly dim it to look disabled
		btn.self_modulate = Color(1, 1, 1, 0.6)

	else:
		# Normal behavior: toggle visibility
		_update_visibility_icon(btn, is_public)

		btn.tooltip_text = (
			"Hide from feed (still accessible by direct link)" if is_public else "Show in feed"
		)

		btn.pressed.connect(
			func():
				# Block further mouse events until server reply updates state
				btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
				toggle_visibility_requested.emit(
					prime_id, btn.get_meta("name"), btn.get_meta("is_public")
				)
		)

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


func _create_delete_button(prime_id: String, name: String) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var theme := EditorInterface.get_editor_theme()
	btn.icon = theme.get_icon("Close", "EditorIcons")

	btn.tooltip_text = "Delete from Primes"
	btn.self_modulate = Color(1.0, 0.4, 0.4, 1.0)  # soft red tint

	btn.set_meta("prime_id", prime_id)
	btn.set_meta("name", name)

	btn.pressed.connect(func(): delete_prime_requested.emit(prime_id, name))

	return btn


func _create_flag_button(flagged: bool, prime_id: String, prime_name: String) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE

	var theme := EditorInterface.get_editor_theme()
	var icon := theme.get_icon("NodeWarning", "EditorIcons")

	# Use the same style for all states so size doesn't change
	var empty_style := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty_style)
	btn.add_theme_stylebox_override("hover", empty_style)
	btn.add_theme_stylebox_override("pressed", empty_style)
	btn.add_theme_stylebox_override("focus", empty_style)
	btn.add_theme_stylebox_override("disabled", empty_style)

	# Fix the width based on the icon size (plus a little padding)
	var icon_width := float(icon.get_width())
	var icon_height := float(icon.get_height())
	btn.custom_minimum_size = Vector2(icon_width + 8.0, icon_height)

	if flagged:
		# Visible, interactive
		btn.icon = icon
		btn.disabled = false
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.tooltip_text = "View flags and appeal"
		btn.self_modulate = Color(1, 1, 1, 1)

		btn.pressed.connect(func(): flag_details_requested.emit(prime_id, prime_name))
	else:
		# Invisible spacer: same size, same style, but not clickable
		btn.disabled = true
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.tooltip_text = ""
		# Make it visually disappear while keeping the size
		btn.self_modulate = Color(1, 1, 1, 0)

	return btn


func _update_visibility_icon(btn: Button, is_public: bool) -> void:
	if is_public:
		btn.icon = EditorInterface.get_editor_theme().get_icon(
			"GuiVisibilityVisible", "EditorIcons"
		)
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
					child.mouse_filter = Control.MOUSE_FILTER_STOP
					child.set_meta("is_public", is_public)
					_update_visibility_icon(child, is_public)
					return
