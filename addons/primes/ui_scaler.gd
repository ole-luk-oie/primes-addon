@tool
class_name PrimesUIScaler
extends RefCounted

static var _icon_cache: Dictionary = {}  # key -> Texture2D


static func scale() -> float:
	return EditorInterface.get_base_control().get_theme_default_base_scale()


static func px(v: float) -> float:
	return v * scale()


static func v2(x: float, y: float) -> Vector2:
	return Vector2(px(x), px(y))


# --- Icons (SVG rasterization with optical compensation) ---
static func _pick_icon_px(logical_px: int) -> int:
	var s := scale()

	if s >= 2.75:
		return int(round(logical_px * 3.0))
	if s >= 1.75:
		return int(round(logical_px * 2.0))
	return logical_px


static func icon(svg_path: String, logical_px: int = 24) -> Texture2D:
	var px_size := _pick_icon_px(logical_px)
	var key := "%s|%d" % [svg_path, px_size]
	if _icon_cache.has(key):
		return _icon_cache[key]

	var bytes := FileAccess.get_file_as_bytes(svg_path)
	if bytes.is_empty():
		push_warning("Missing icon SVG: %s" % svg_path)
		return null

	var img := Image.new()
	var scale_factor := float(px_size) / float(logical_px)

	var err := img.load_svg_from_buffer(bytes, scale_factor)
	if err != OK:
		push_warning("SVG render failed (%s): %s" % [str(err), svg_path])
		return null

	# Normalize final size
	if img.get_width() != px_size or img.get_height() != px_size:
		img.resize(px_size, px_size, Image.INTERPOLATE_LANCZOS)

	var tex := ImageTexture.create_from_image(img)
	_icon_cache[key] = tex
	return tex
