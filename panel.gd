@tool
extends PanelContainer
class_name CloudPublisherPanel

var plugin: EditorPlugin

@onready var stack: VBoxContainer       = $Root/Stack
@onready var sign_in: VBoxContainer     = $Root/Stack/SignIn
@onready var email_le: LineEdit         = $Root/Stack/SignIn/Email
@onready var key_le: LineEdit           = $Root/Stack/SignIn/Key
@onready var sign_in_btn: Button        = $Root/Stack/SignIn/SignInRow/SignInBtn

@onready var publish_vb: VBoxContainer  = $Root/Stack/Publish
@onready var name_le: LineEdit          = $Root/Stack/Publish/Grid/Name
@onready var desc_te: TextEdit          = $Root/Stack/Publish/Grid/Desc
@onready var thumb_le: LineEdit         = $Root/Stack/Publish/Grid/ThumbRow/ThumbPath
@onready var browse_btn: Button         = $Root/Stack/Publish/Grid/ThumbRow/Browse
@onready var visibility_ob: OptionButton= $Root/Stack/Publish/Grid/Visibility
@onready var publish_btn: Button        = $Root/Stack/Publish/Row/PublishBtn
@onready var log_rt: RichTextLabel      = $Root/Stack/Publish/Log
@onready var file_dlg: FileDialog       = $FileDialog

var exporter: PrimesExporter

func _ready() -> void:
	# Sign-In
	sign_in_btn.pressed.connect(_on_sign_in)

	log_rt.custom_minimum_size.y = 200

	# Publish
	browse_btn.pressed.connect(_on_browse)
	file_dlg.file_selected.connect(_on_file_selected)
	publish_btn.pressed.connect(_on_publish)

	visibility_ob.clear()
	visibility_ob.add_item("Public", 0)
	visibility_ob.add_item("Private", 1)
	visibility_ob.select(0)

	# Prefill if we already have creds
	ensure_correct_subview()

func ensure_correct_subview() -> void:
	if plugin and plugin.is_signed_in():
		_show_publish()
	else:
		_show_sign_in()
		if plugin:
			var a: Dictionary = plugin.load_auth()
			email_le.text = String(a.get("email", ""))
			key_le.text   = String(a.get("api_key", ""))

func _show_sign_in() -> void:
	sign_in.visible = true
	publish_vb.visible = false
	email_le.grab_focus()

func _show_publish() -> void:
	sign_in.visible = false
	publish_vb.visible = true
	name_le.grab_focus()

# --- Sign-In ---
func _on_sign_in() -> void:
	var email: String = email_le.text.strip_edges()
	var api_key: String = key_le.text.strip_edges()
	if email == "" or api_key == "":
		push_warning("Email and API key required.")
		return
	# TODO real auth; mock token for now
	var token: String = "dev-" + str(Time.get_ticks_msec())
	plugin.save_auth(email, api_key, token)
	_show_publish()
	_append_log("Signed in as [b]%s[/b]." % email)

# --- Publish ---
func _on_browse() -> void:
	file_dlg.popup_centered(Vector2i(640, 480))

func _on_file_selected(path: String) -> void:
	thumb_le.text = path

func _on_publish() -> void:
	if not plugin or not plugin.is_signed_in():
		_append_log("[color=orange]Please sign in first.[/color]")
		return
	var name: String    = name_le.text.strip_edges()
	var desc: String    = desc_te.text.strip_edges()
	var thumb: String   = thumb_le.text.strip_edges()
	var is_public: bool = visibility_ob.get_selected_id() == 0

	publish_btn.disabled = true
	_append_log("Packing project…")
	var pkg = exporter.pack_zip(Callable(self, "_append_log"))
	_append_log("Uploading %s…" % pkg)
	var result = await exporter.upload_zip_with_meta(self, pkg, "ole-luk-oie")

	if !result["success"]:
		_append_log("[color=red]Failed to publish[/color] %s" % result["error"])
	else:
		var link: String = "https://ole-luk-oie.com/primes/i?id=" + result["id"]
		DisplayServer.clipboard_set(link)
		_append_log("[color=green]Published[/color] %s (%s). Link copied: %s"
			% [name if name != "" else "(auto)", ("Public" if is_public else "Private"), link])
	publish_btn.disabled = false

func _append_log(msg: String) -> void:
	log_rt.append_text("\n• %s" % msg)
	log_rt.scroll_to_line(log_rt.get_line_count())
