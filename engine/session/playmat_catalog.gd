class_name PlaymatCatalog
extends RefCounted

## Picks the felt playmat for a commander's color identity. Files live in res://assets/playmats and are
## named in WUBRG order: "Red", "White-Blue", "Black-Red-Green", "Colorless", ...

const DIR := "res://assets/playmats"
const NAMES := {"W": "White", "U": "Blue", "B": "Black", "R": "Red", "G": "Green"}

static var _cache: Dictionary = {}


## identity: color letters in any order, e.g. ["G", "U"] -> "Blue-Green.jpg".
static func file_for(identity: Array) -> String:
	var parts: Array = []
	for c in ["W", "U", "B", "R", "G"]:
		if identity.has(c):
			parts.append(NAMES[c])
	if parts.is_empty():
		return "Colorless.jpg"
	return "%s.jpg" % "-".join(PackedStringArray(parts))


## The mat's texture. Uses the imported resource when the editor has imported it, otherwise reads the
## image file directly, so a freshly copied mat still shows.
static func texture(file: String) -> Texture2D:
	if _cache.has(file):
		return _cache[file]
	var path := "%s/%s" % [DIR, file]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	_cache[file] = tex
	return tex
