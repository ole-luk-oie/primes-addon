extends Object
class_name DevRunner

const ANDROID_PACKAGE    := "com.olelukoie.primes"
const ANDROID_ACTIVITY   := "com.olelukoie.primes.ui.MainActivity"

const EXTRA_DEV_BUNDLE_PATH = "com.olelukoie.primes.EXTRA_DEV_BUNDLE_PATH"
const EXTRA_DEV_ENGINE      = "com.olelukoie.primes.EXTRA_DEV_ENGINE"
const EXTRA_DEV_ID          = "com.olelukoie.primes.EXTRA_DEV_ID"
const EXTRA_DEV_AUTHOR      = "com.olelukoie.primes.EXTRA_DEV_AUTHOR"
const EXTRA_DEV_NAME        = "com.olelukoie.primes.EXTRA_DEV_NAME"
const EXTRA_DEV_DESC        = "com.olelukoie.primes.EXTRA_DEV_DESC"

const DEV_ID_SETTING        := "primes/dev_id"

# For building the dev zip; keeps this helper self-contained.
var _packager: Packager = Packager.new()
# For figuring out engine string
var _uploader: Uploader = Uploader.new()

# --- Public API ---

func probe_android_device() -> bool:
	var output: Array = []
	var exit_code := OS.execute("adb", PackedStringArray(["devices"]), output, true, false)
	if exit_code != 0:
		return false

	if output.is_empty():
		return false

	var text := String(output[0])

	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line == "":
			continue

		# Skip obvious header-ish lines without depending on exact wording
		if line.to_lower().contains("list of devices"):
			continue

		# Normalize tabs → spaces, then collapse runs of spaces
		line = line.replace("\t", " ")

		var cols: Array = []
		for token in line.split(" ", false): # ignore empty
			var t := String(token).strip_edges()
			if t != "":
				cols.append(t)

		if cols.size() < 2:
			continue

		var state := String(cols[1])
		if state == "device":
			return true

	return false

func _is_app_installed() -> bool:
	var out: Array = []
	var code := OS.execute(
		"adb",
		PackedStringArray(["shell", "pm", "path", ANDROID_PACKAGE]),
		out,
		true,
		false
	)
	if code != 0:
		return false

	if out.is_empty():
		return false

	var text := String(out[0])
	# Typical output: "package:/data/app/~~.../com.olelukoie.primes-XXXXX==/base.apk"
	return text.find("package:") != -1

## High-level “run on phone” flow.
## Returns `true` on success, `false` on any failure.
func run_dev_on_phone(
	host: Node,
	logs,
	username: String,
	form_name: String,
	form_desc: String
) -> bool:
	if not _is_app_installed():
		await logs.append_log(
			"[color=orange]Primes app is not installed on the connected device.[/color]",
			"orange"
		)
		return false
	
	await logs.append_log("Packing project for dev run on phone...")

	# 1) Pack current project as web bundle
	var pack_result := _packager.pack_zip()
	if not pack_result.get("success", false):
		await logs.append_log(
			"[color=red]Dev run failed to build package:[/color] %s"
			% String(pack_result.get("error", "")),
			"red"
		)
		return false

	var zip_path: String = pack_result.get("zip_path", "")
	await logs.append_log("Dev bundle built at: [code]%s[/code]" % zip_path)

	# 2) Derive dev meta from form + project settings
	var dev_name   := _get_dev_name(form_name)
	var dev_id     := _get_or_create_dev_id(dev_name)
	var dev_author := _get_dev_author(username)
	var dev_desc   := _get_dev_desc(form_desc)
	
	var engine_result := _uploader.get_engine_string()
	if not engine_result.get("success", false):
		print(str(engine_result))
		await logs.append_log(
			"[color=red]Dev run aborted:[/color] %s"
			% String(engine_result.get("error", "Unknown engine error")),
			"red"
		)
		return false
	var dev_engine := String(engine_result.get("engine", ""))

	await logs.append_log(
		"Dev meta → id=[b]%s[/b], author=[b]%s[/b], name=[b]%s[/b]"
		% [dev_id, dev_author, dev_name]
	)

	# 3) Push bundle & start activity via adb
	var ok := await _push_and_start_on_android(
		logs,
		zip_path,
		dev_id,
		dev_engine,
		dev_author,
		dev_name,
		dev_desc
	)

	return ok

# --- Helpers: meta building ---

func _get_dev_author(username: String) -> String:
	var u := String(username)
	if u != "":
		return u
	return "unknown-dev"

func _get_dev_name(form_name: String) -> String:
	var name := String(form_name).strip_edges()
	if name != "":
		return name

	if ProjectSettings.has_setting("application/config/name"):
		var ps_name := String(ProjectSettings.get_setting("application/config/name"))
		if ps_name != "":
			return ps_name

	return "Dev build"

func _get_dev_desc(form_desc: String) -> String:
	var desc := String(form_desc).strip_edges()
	if desc != "":
		return desc

	if ProjectSettings.has_setting("application/config/description"):
		var ps_desc := String(ProjectSettings.get_setting("application/config/description"))
		if ps_desc != "":
			return ps_desc

	return ""

func _get_or_create_dev_id(dev_name: String) -> String:
	# If it already exists, reuse it.
	if ProjectSettings.has_setting(DEV_ID_SETTING):
		var existing := String(ProjectSettings.get_setting(DEV_ID_SETTING))
		if existing != "":
			return existing

	# Otherwise generate a fresh one and persist it.
	var fresh := _make_dev_id(dev_name)
	ProjectSettings.set_setting(DEV_ID_SETTING, fresh)
	ProjectSettings.save() # writes project.godot

	return fresh

func _make_dev_id(name: String) -> String:
	var slug := String(name).strip_edges().to_lower()

	# Replace spaces with hyphens (DNS-friendly form)
	slug = slug.replace(" ", "-")

	# Remove all not allowed DNS chars
	var re := RegEx.new()
	re.compile("[^a-z0-9-]")
	slug = re.sub(slug, "-", true)

	# Trim leading/trailing hyphens
	slug = slug.trim_prefix("-").trim_suffix("-")

	if slug == "":
		slug = "dev"

	# 64-bit random hex suffix
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var hi := rng.randi()
	var lo := rng.randi()
	var hex := "%08x%08x" % [hi, lo]

	return "dev_%s_%s" % [slug, hex]


# --- Helpers: adb push + am start ---

func _push_and_start_on_android(
	logs,
	local_zip_path: String,
	dev_id: String,
	engine: String,
	author: String,
	name: String,
	desc: String
) -> bool:
	# 1) Ensure remote dir exists
	var mkdir_args := PackedStringArray([
		"shell", "mkdir", "-p", _get_dev_remote_dir()
	])
	OS.execute("adb", mkdir_args, [], true, false)  # ignore error; dir may exist

	# 2) Push file
	var remote_path := "%s/%s.zip" % [_get_dev_remote_dir(), dev_id]
	await logs.append_log("Pushing bundle to device:\n[code]%s[/code]" % remote_path)

	var push_out: Array = []
	var push_args := PackedStringArray([
		"push", local_zip_path, remote_path
	])
	var push_code := OS.execute("adb", push_args, push_out, true, false)

	if push_code != 0:
		await logs.append_log(
			"[color=red]adb push failed (exit %d):[/color]\n[code]%s[/code]"
			% [push_code, String(push_out[0]) if push_out.size() > 0 else ""],
			"red"
		)
		return false

	# 3) Start activity with dev extras
	await logs.append_log("Starting Primes app dev run via adb...")

	var comp := "%s/%s" % [ANDROID_PACKAGE, ANDROID_ACTIVITY]

	var am_args := PackedStringArray([
		"shell", "am", "start",
		"-n", comp,
		"--es", EXTRA_DEV_BUNDLE_PATH, remote_path,
		"--es", EXTRA_DEV_ENGINE,      engine,
		"--es", EXTRA_DEV_ID,          dev_id,
		"--es", EXTRA_DEV_AUTHOR,      author,
		"--es", EXTRA_DEV_NAME,        name,
	])

	# Only add description extra if we actually have text
	if desc.strip_edges() != "":
		am_args.append_array([
			"--es", EXTRA_DEV_DESC, desc
		])

	var am_out: Array = []
	var am_code := OS.execute("adb", am_args, am_out, true, false)

	if am_code != 0:
		await logs.append_log(
			"[color=red]adb shell am start failed (exit %d):[/color]\n[code]%s[/code]"
			% [am_code, String(am_out[0]) if am_out.size() > 0 else ""],
			"red"
		)
		return false

	return true
	
func _get_dev_remote_dir() -> String:
	return "/sdcard/Android/data/%s/files/dev" % ANDROID_PACKAGE
