@tool
class_name ArtMasks
extends RefCounted
## Finds where the "living" effects belong in a painting, so any image can be animated without hand-made masks.
## Returns a small RGBA texture (mipmapped, sampled smoothly by the shader):
##   R = water   (cyan..blue, some saturation)      → ripples, glints, shimmer
##   G = hot     (lava, fire, torches: warm, saturated and brighter than its surroundings) → glow, flicker, heat haze
##   B = foliage (green/yellow-green)                → sway, dappled light
##   A = sky     (bright, smooth, near the top)      → drifting cloud light (only used where a scene preset asks)
## Built once per image at 240×160 and cached.

## Bump when the detection rules change, so saved masks are rebuilt.
const VERSION := 1
const W := 240
const H := 160

static var _cache: Dictionary = {}


static func for_texture(tex: Texture2D, cache_key: String = "") -> ImageTexture:
	if tex == null:
		return null
	var key := cache_key if cache_key != "" else str(tex.get_rid())
	if _cache.has(key):
		return _cache[key]
	# Saved masks (user://playmat_masks) make later runs instant; the name changes if the painting changes.
	var disk := ""
	if cache_key != "":
		var stamp := FileAccess.get_modified_time(cache_key) if FileAccess.file_exists(cache_key) else 0
		disk = "user://playmat_masks/%s.png" % ("%s|%d|%d|%d|v%d" % [cache_key, stamp, tex.get_width(), tex.get_height(), VERSION]).md5_text()
		if FileAccess.file_exists(disk):
			var saved := Image.load_from_file(ProjectSettings.globalize_path(disk))
			if saved != null and not saved.is_empty():
				saved.generate_mipmaps()
				_cache[key] = ImageTexture.create_from_image(saved)
				return _cache[key]
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(W, H, Image.INTERPOLATE_BILINEAR)
	var mask := build(img)
	_cache[key] = mask
	if disk != "":
		DirAccess.make_dir_recursive_absolute("user://playmat_masks")
		var plain := mask.get_image().duplicate()
		plain.clear_mipmaps()
		plain.save_png(disk)
	return mask


static func build(img: Image) -> ImageTexture:
	var px := img.get_data()
	var n := W * H
	var hue := PackedFloat32Array(); hue.resize(n)
	var sat := PackedFloat32Array(); sat.resize(n)
	var val := PackedFloat32Array(); val.resize(n)
	for i in n:
		var r := px[i * 4] / 255.0
		var g := px[i * 4 + 1] / 255.0
		var b := px[i * 4 + 2] / 255.0
		var mx := maxf(r, maxf(g, b))
		var mn := minf(r, minf(g, b))
		var d := mx - mn + 0.000001
		var h := 0.0
		if mx == r:
			h = fposmod((g - b) / d, 6.0)
		elif mx == g:
			h = (b - r) / d + 2.0
		else:
			h = (r - g) / d + 4.0
		hue[i] = h * 60.0
		sat[i] = (mx - mn) / (mx + 0.000001) if mx > 0.0001 else 0.0
		val[i] = mx

	var v_local := _blur(val, 15, 10)   # neighbourhood brightness (large blur)
	var v_soft := _blur(val, 120, 80)   # tiny blur, for texture detection

	var out := PackedByteArray(); out.resize(n * 4)
	for i in n:
		var h := hue[i]
		var s := sat[i]
		var v := val[i]
		var y := floorf(float(i) / float(W)) / float(H - 1)
		var water := _ss(160.0, 185.0, h) * (1.0 - _ss(235.0, 255.0, h)) * _ss(0.12, 0.3, s) * _ss(0.08, 0.2, v)
		# lava: deep red, saturated, glowing against dark ground (red rock and dirt are more orange and sit in bright light)
		var deep := maxf(1.0 - _ss(11.0, 17.0, h), _ss(340.0, 350.0, h))
		var lava := deep * _ss(0.45, 0.6, s) * _ss(0.25, 0.4, v) * (1.0 - _ss(0.28, 0.42, v_local[i])) * _ss(0.05, 0.15, v - v_local[i])
		# flames and torches: small, bright, yellow-orange, far brighter than their surroundings
		var flame := _ss(0.7, 0.88, v) * _ss(15.0, 25.0, h) * (1.0 - _ss(50.0, 62.0, h)) * _ss(0.35, 0.55, s) * _ss(0.15, 0.3, v - v_local[i])
		var hot := maxf(lava, flame)
		var foliage := _ss(50.0, 75.0, h) * (1.0 - _ss(160.0, 175.0, h)) * _ss(0.15, 0.3, s) * _ss(0.06, 0.15, v)
		var sky := (1.0 - _ss(0.25, 0.5, y)) * (1.0 - _ss(0.02, 0.06, absf(v - v_soft[i]))) * _ss(0.45, 0.7, v)
		out[i * 4] = int(clampf(water, 0.0, 1.0) * 255.0)
		out[i * 4 + 1] = int(clampf(hot, 0.0, 1.0) * 255.0)
		out[i * 4 + 2] = int(clampf(foliage, 0.0, 1.0) * 255.0)
		out[i * 4 + 3] = int(clampf(sky, 0.0, 1.0) * 255.0)

	var mask := Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, out)
	# soften: down to half size and back (a cheap blur)
	mask.resize(120, 80, Image.INTERPOLATE_BILINEAR)
	mask.resize(W, H, Image.INTERPOLATE_BILINEAR)
	mask.generate_mipmaps()
	return ImageTexture.create_from_image(mask)


## Blur a W×H channel by shrinking it to sw×sh and growing it back (bilinear).
static func _blur(ch: PackedFloat32Array, sw: int, sh: int) -> PackedFloat32Array:
	var bytes := PackedByteArray(); bytes.resize(ch.size())
	for i in ch.size():
		bytes[i] = int(clampf(ch[i], 0.0, 1.0) * 255.0)
	var im := Image.create_from_data(W, H, false, Image.FORMAT_L8, bytes)
	im.resize(sw, sh, Image.INTERPOLATE_BILINEAR)
	im.resize(W, H, Image.INTERPOLATE_BILINEAR)
	var back := im.get_data()
	var out := PackedFloat32Array(); out.resize(ch.size())
	for i in ch.size():
		out[i] = back[i] / 255.0
	return out


static func _ss(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
