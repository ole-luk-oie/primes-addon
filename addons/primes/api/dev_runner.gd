class_name DevRunner
extends Object

const ANDROID_PACKAGE := "com.olelukoie.primes"
const ANDROID_ACTIVITY := "com.olelukoie.primes.ui.MainActivity"

const EXTRA_DEV_BUNDLE_PATH = "com.olelukoie.primes.EXTRA_DEV_BUNDLE_PATH"
const EXTRA_DEV_ENGINE = "com.olelukoie.primes.EXTRA_DEV_ENGINE"
const EXTRA_DEV_ID = "com.olelukoie.primes.EXTRA_DEV_ID"
const EXTRA_DEV_AUTHOR = "com.olelukoie.primes.EXTRA_DEV_AUTHOR"
const EXTRA_DEV_NAME = "com.olelukoie.primes.EXTRA_DEV_NAME"
const EXTRA_DEV_DESC = "com.olelukoie.primes.EXTRA_DEV_DESC"

const DEV_ID_SETTING := "primes/dev_id"

var _packager: Packager = Packager.new()
var _uploader: Uploader = Uploader.new()

# HTTP server for serving dev builds
var _server: TCPServer = null
var _server_port: int = 8765
var _file_to_serve: String = ""
var _server_running: bool = false

var _process_conn_id: int = -1

# Device used for the current dev run session
var _active_device_serial: String = ""

# --- Public API ---


func list_android_devices() -> Array:
	# Returns: [{ "serial": String, "label": String }]
	var output: Array = []
	var exit_code := OS.execute("adb", PackedStringArray(["devices"]), output, true, false)
	if exit_code != 0:
		return []

	if output.is_empty():
		return []

	var text := String(output[0])
	var devices: Array = []

	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line == "":
			continue
		if line.to_lower().contains("list of devices"):
			continue

		line = line.replace("\t", " ")

		var cols: Array = []
		for token in line.split(" ", false):
			var t := String(token).strip_edges()
			if t != "":
				cols.append(t)

		if cols.size() < 2:
			continue

		var serial := String(cols[0])
		var state := String(cols[1])

		if state != "device":
			continue

		var model := _adb_getprop(serial, "ro.product.model")
		if model == "":
			model = "Android"

		var label := "%s (%s)" % [model, serial]
		(
			devices
			. append(
				{
					"serial": serial,
					"label": label,
				}
			)
		)

	return devices


func probe_android_device() -> bool:
	return list_android_devices().size() > 0


# --- Internal: adb helpers ---


func _adb_getprop(serial: String, prop: String) -> String:
	var out: Array = []
	var args := PackedStringArray(["-s", serial, "shell", "getprop", prop])
	var code := OS.execute("adb", args, out, true, false)
	if code != 0 or out.is_empty():
		return ""
	return String(out[0]).strip_edges()


func _is_app_installed(device_serial: String) -> bool:
	var out: Array = []
	var code := OS.execute(
		"adb",
		PackedStringArray(["-s", device_serial, "shell", "pm", "path", ANDROID_PACKAGE]),
		out,
		true,
		false
	)
	if code != 0:
		return false

	if out.is_empty():
		return false

	var text := String(out[0])
	return text.find("package:") != -1


func run_dev_on_phone(
	host: Node,
	logs,
	username: String,
	form_name: String,
	form_desc: String,
	device_serial: String = ""
) -> bool:
	# Resolve device serial
	var devices := list_android_devices()

	if devices.size() == 0:
		await logs.append_log("[color=orange]No Android device detected via adb.[/color]", "orange")
		return false

	var chosen_serial := String(device_serial).strip_edges()
	if chosen_serial == "":
		if devices.size() == 1:
			chosen_serial = String(devices[0].get("serial", ""))
		else:
			chosen_serial = String(devices[0].get("serial", ""))
			await (
				logs
				. append_log(
					(
						"[color=orange]Multiple Android devices detected; selecting the first one: %s[/color]"
						% String(devices[0].get("label", chosen_serial))
					),
					"orange"
				)
			)

	if chosen_serial == "":
		await logs.append_log("[color=red]No device selected.[/color]", "red")
		return false

	_active_device_serial = chosen_serial

	if not _is_app_installed(_active_device_serial):
		await logs.append_log(
			"[color=orange]Primes app is not installed on the selected device.[/color]", "orange"
		)
		return false

	await logs.append_log("Packing project for dev run on phone...")

	# 1) Pack current project as web bundle
	var pack_result := _packager.pack_zip()
	if not pack_result.get("success", false):
		await logs.append_log(
			(
				"[color=red]Dev run failed to build package:[/color] %s"
				% String(pack_result.get("error", ""))
			),
			"red"
		)
		return false

	var zip_path: String = pack_result.get("zip_path", "")
	await logs.append_log("Dev bundle built at: [code]%s[/code]" % zip_path)

	# 2) Start HTTP server on computer
	await logs.append_log("Starting local HTTP server...")
	if not _start_http_server(zip_path, host):
		await logs.append_log("[color=red]Failed to start HTTP server[/color]", "red")
		return false

	# 3) Set up adb reverse so device can reach computer's localhost
	await logs.append_log("Setting up port forwarding...")
	var reverse_args := PackedStringArray(
		["-s", _active_device_serial, "reverse", "tcp:%d" % _server_port, "tcp:%d" % _server_port]
	)
	var reverse_code := OS.execute("adb", reverse_args, [], true, false)

	if reverse_code != 0:
		await logs.append_log("[color=red]Failed to set up port forwarding[/color]", "red")
		_stop_http_server()
		return false

	# 4) Derive dev meta from form + project settings
	var dev_name := _get_dev_name(form_name)
	var dev_id := _get_or_create_dev_id(dev_name)
	var dev_author := _get_dev_author(username)
	var dev_desc := _get_dev_desc(form_desc)

	var engine_result := _uploader.get_engine_string()
	if not engine_result.get("success", false):
		print(str(engine_result))
		await logs.append_log(
			(
				"[color=red]Dev run aborted:[/color] %s"
				% String(engine_result.get("error", "Unknown engine error"))
			),
			"red"
		)
		_stop_http_server()
		return false
	var dev_engine := String(engine_result.get("engine", ""))

	await logs.append_log(
		"Dev meta → id=[b]%s[/b], author=[b]%s[/b], name=[b]%s[/b]" % [dev_id, dev_author, dev_name]
	)

	# 5) Start activity with download URL
	var zip_filename := zip_path.get_file()
	var download_url := "http://localhost:%d/%s" % [_server_port, zip_filename]

	var ok := await _start_dev_on_android(
		logs,
		download_url,
		dev_id,
		dev_engine,
		dev_author,
		dev_name,
		dev_desc,
		_active_device_serial
	)

	if ok:
		await logs.append_log("App is downloading the bundle, your prime should start shortly...")
		# Keep server running for download
		await host.get_tree().create_timer(15.0).timeout

	_stop_http_server()
	_active_device_serial = ""

	return ok


# --- HTTP server ---


func _start_http_server(file_path: String, host: Node) -> bool:
	_server = TCPServer.new()

	# Try multiple ports
	var ports_to_try := [8765, 8766, 8767, 8768, 8769]
	var success := false

	for port in ports_to_try:
		var err := _server.listen(port, "127.0.0.1")
		if err == OK:
			_server_port = port
			success = true
			break

	if not success:
		push_error("Failed to start HTTP server on any port")
		return false

	_file_to_serve = file_path
	_server_running = true
	if _process_conn_id == -1:
		_process_conn_id = host.get_tree().process_frame.connect(_process_http_server)

	print("HTTP server started on port %d" % _server_port)
	return true


func _stop_http_server() -> void:
	_server_running = false

	if _server:
		_server.stop()
		_server = null

	var tree := Engine.get_main_loop()
	if _process_conn_id != -1 and tree and tree.process_frame.is_connected(_process_http_server):
		tree.process_frame.disconnect(_process_http_server)
		_process_conn_id = -1

	# Remove only our reverse mapping, on the active device if known
	if _active_device_serial.strip_edges() != "":
		OS.execute(
			"adb",
			PackedStringArray(
				["-s", _active_device_serial, "reverse", "--remove", "tcp:%d" % _server_port]
			),
			[],
			true,
			false
		)
	else:
		# Fallback (keeps old behavior in case something calls stop without a device)
		OS.execute(
			"adb",
			PackedStringArray(["reverse", "--remove", "tcp:%d" % _server_port]),
			[],
			true,
			false
		)


func _process_http_server() -> void:
	if not _server_running or not _server:
		return

	if _server.is_connection_available():
		var client := _server.take_connection()
		_handle_http_client(client)


func _handle_http_client(client: StreamPeerTCP) -> void:
	var request := ""
	if client.get_available_bytes() > 0:
		request = client.get_string(client.get_available_bytes())

	# Read file
	var file := FileAccess.open(_file_to_serve, FileAccess.READ)
	if not file:
		var response := "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
		client.put_data(response.to_utf8_buffer())
		client.disconnect_from_host()
		return

	var file_data := file.get_buffer(file.get_length())
	file.close()

	# Send HTTP response
	var response := "HTTP/1.1 200 OK\r\n"
	response += "Content-Type: application/zip\r\n"
	response += "Content-Length: %d\r\n" % file_data.size()
	response += "Connection: close\r\n"
	response += "\r\n"

	client.put_data(response.to_utf8_buffer())
	client.put_data(file_data)

	# Give time for data to flush
	OS.delay_msec(100)
	client.disconnect_from_host()


# --- adb launch ---


func _start_dev_on_android(
	logs,
	download_url: String,
	dev_id: String,
	engine: String,
	author: String,
	name: String,
	desc: String,
	device_serial: String
) -> bool:
	await logs.append_log("Starting Primes app dev run via adb...")

	var comp := "%s/%s" % [ANDROID_PACKAGE, ANDROID_ACTIVITY]

	var am_args := PackedStringArray(
		[
			"-s",
			device_serial,
			"shell",
			"am",
			"start",
			"-n",
			comp,
			"--es",
			EXTRA_DEV_BUNDLE_PATH,
			download_url,
			"--es",
			EXTRA_DEV_ENGINE,
			engine,
			"--es",
			EXTRA_DEV_ID,
			dev_id,
			"--es",
			EXTRA_DEV_AUTHOR,
			author,
			"--es",
			EXTRA_DEV_NAME,
			name,
		]
	)

	if desc.strip_edges() != "":
		am_args.append_array(["--es", EXTRA_DEV_DESC, desc])

	var am_out: Array = []
	var am_code := OS.execute("adb", am_args, am_out, true, false)

	if am_code != 0:
		await logs.append_log(
			(
				"[color=red]adb shell am start failed (exit %d):[/color]\n[code]%s[/code]"
				% [am_code, String(am_out[0]) if am_out.size() > 0 else ""]
			),
			"red"
		)
		return false

	return true


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
	if ProjectSettings.has_setting(DEV_ID_SETTING):
		var existing := String(ProjectSettings.get_setting(DEV_ID_SETTING))
		if existing != "":
			return existing

	var fresh := _make_dev_id(dev_name)
	ProjectSettings.set_setting(DEV_ID_SETTING, fresh)
	ProjectSettings.save()

	return fresh


func _make_dev_id(name: String) -> String:
	var slug := String(name).strip_edges().to_lower()
	slug = slug.replace(" ", "-")

	var re := RegEx.new()
	re.compile("[^a-z0-9-]")
	slug = re.sub(slug, "-", true)

	slug = slug.trim_prefix("-").trim_suffix("-")

	if slug == "":
		slug = "dev"

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var hi := rng.randi()
	var lo := rng.randi()
	var hex := "%08x%08x" % [hi, lo]

	return "dev_%s_%s" % [slug, hex]
