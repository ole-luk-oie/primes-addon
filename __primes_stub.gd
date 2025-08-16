# Editor/dev stub for the native Primes module.
# Static API so you can call:  Primes.store_string(...)

class_name Primes
extends Object

const PERSIST_PATH := "user://primes.bin"

static var _loaded := false
static var _store: Dictionary = {}   # key: String -> PackedByteArray

# ------------ internal helpers ------------
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PERSIST_PATH):
		var blob := FileAccess.get_file_as_bytes(PERSIST_PATH)
		if blob.size() > 0:
			var dict := bytes_to_var(blob)
			if typeof(dict) == TYPE_DICTIONARY:
				_store.clear()
				for k in dict.keys():
					var v = dict[k]
					if v is PackedByteArray:
						_store[k] = v
					elif typeof(v) == TYPE_STRING:
						_store[k] = String(v).to_utf8_buffer()
					else:
						_store[k] = var_to_bytes(v)  # last‑resort coercion

static func _flush_now() -> void:
	var tmp := "%s.tmp" % PERSIST_PATH
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f:
		var blob := var_to_bytes(_store)
		f.store_buffer(blob)
		f.flush()
		f = null
		var da := DirAccess.open("user://")
		if da:
			da.remove(PERSIST_PATH) # ignore error if not present
			da.rename(tmp, PERSIST_PATH)

# ------------ storage ------------
static func clear_key(key: String) -> void:
	_ensure_loaded()
	_store.erase(key)
	_flush_now()

static func keys() -> PackedStringArray:
	_ensure_loaded()
	return PackedStringArray(_store.keys())

static func store_bytes(key: String, data: PackedByteArray) -> void:
	_ensure_loaded()
	_store[key] = data
	_flush_now()

static func append_bytes(key: String, data: PackedByteArray) -> void:
	_ensure_loaded()
	var cur: PackedByteArray = _store.get(key, PackedByteArray())
	if data.size() > 0:
		cur.append_array(data)
	_store[key] = cur
	_flush_now()

static func load_bytes(key: String) -> PackedByteArray:
	_ensure_loaded()
	return _store.get(key, PackedByteArray())

static func store_string(key: String, text: String) -> void:
	_ensure_loaded()
	_store[key] = text.to_utf8_buffer()
	_flush_now()

static func append_string(key: String, text: String) -> void:
	_ensure_loaded()
	var cur: PackedByteArray = _store.get(key, PackedByteArray())
	var add := text.to_utf8_buffer()
	if add.size() > 0:
		cur.append_array(add)
	_store[key] = cur
	_flush_now()

static func load_string(key: String) -> String:
	_ensure_loaded()
	var arr: PackedByteArray = _store.get(key, PackedByteArray())
	return arr.get_string_from_utf8()

# ------------ perf / delay / finish ------------
static func get_performance_pref() -> int:
	return 2 # BALANCED

static func delay_usec(usec: int) -> void:
	OS.delay_usec(usec)

static func delay_msec(msec: int) -> void:
	OS.delay_usec(msec * 1000)

static func finish() -> void:
	pass
