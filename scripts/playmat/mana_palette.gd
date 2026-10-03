@tool
class_name ManaPalette
extends RefCounted
## Color-identity database for SuperPlaymat.
## Names, 5-slot palettes, accent colors and "personality" traits for all 32
## Magic: The Gathering color identities. Everything is static — no instancing.
##
## Identity keys are always written in WUBRG order ("WU", "UBR", "WBRG") and
## colorless is "C". normalize() accepts almost anything a player or a deck
## importer might hand you: "uw", "{U}{W}", "Azorius", "green white", "".

const ORDER := "WUBRG"

## Shader uniforms driven by build_style(). "speed" is handled by the script.
const LAYER_KEYS := [
	"warp_strength", "ripple_amount", "cell_amount",
	"ray_amount", "ember_amount", "void_amount", "shimmer_amount",
]

const NAMES := {
	"C": "Colorless",
	"W": "Mono-White", "U": "Mono-Blue", "B": "Mono-Black", "R": "Mono-Red", "G": "Mono-Green",
	"WU": "Azorius", "UB": "Dimir", "BR": "Rakdos", "RG": "Gruul", "WG": "Selesnya",
	"WB": "Orzhov", "UR": "Izzet", "BG": "Golgari", "WR": "Boros", "UG": "Simic",
	"WUG": "Bant", "WUB": "Esper", "UBR": "Grixis", "BRG": "Jund", "WRG": "Naya",
	"WBG": "Abzan", "WUR": "Jeskai", "UBG": "Sultai", "WBR": "Mardu", "URG": "Temur",
	"WUBR": "Yore-Tiller", "UBRG": "Glint-Eye", "WBRG": "Dune-Brood",
	"WURG": "Ink-Treader", "WUBG": "Witch-Maw",
	"WUBRG": "Five-Color",
}

## All 32 identities in a sensible browsing order.
const ALL := [
	"C",
	"W", "U", "B", "R", "G",
	"WU", "UB", "BR", "RG", "WG", "WB", "UR", "BG", "WR", "UG",
	"WUG", "WUB", "UBR", "BRG", "WRG",
	"WBG", "WUR", "UBG", "WBR", "URG",
	"WUBR", "UBRG", "WBRG", "WURG", "WUBG",
	"WUBRG",
]

const SHARDS := ["WUG", "WUB", "UBR", "BRG", "WRG"]
const COLOR_WORDS := {"white": "W", "blue": "U", "black": "B", "red": "R", "green": "G"}


static func all_identities() -> PackedStringArray:
	return PackedStringArray(ALL)


## Turns any reasonable input into a canonical key ("WU", "C", ...).
static func normalize(text: String) -> String:
	var raw := text.strip_edges()
	var lower := raw.to_lower()
	if lower in ["", "c", "colorless", "none", "{c}"]:
		return "C"
	if lower in ["5c", "5-color", "rainbow", "wubrg"]:
		return "WUBRG"

	# Guild / shard / wedge / Nephilim names.
	for key in NAMES:
		if (NAMES[key] as String).to_lower() == lower:
			return key

	# "green white", "Black/Red", "blue, red"
	var tokens := lower.replace("-", " ").replace("/", " ").replace(",", " ").split(" ", false)
	var from_words := ""
	for tk in tokens:
		if not COLOR_WORDS.has(tk):
			from_words = ""
			break
		from_words += COLOR_WORDS[tk]
	if from_words != "":
		return _sorted(from_words)

	# Letters: "uw", "{U}{W}", "R G"
	var key := _sorted(raw.to_upper())
	return key if key != "" else "C"


static func get_display_name(identity: String) -> String:
	return NAMES.get(normalize(identity), "Unknown")


static func get_group(identity: String) -> String:
	var key := normalize(identity)
	if key == "C":
		return "Colorless"
	match key.length():
		1: return "Mono"
		2: return "Guild"
		3: return "Shard" if key in SHARDS else "Wedge"
		4: return "Four-Color"
	return "Five-Color"


static func colors_of(identity: String) -> PackedStringArray:
	var key := normalize(identity)
	var out := PackedStringArray()
	for ch in key:
		out.append(ch)
	return out


## Always 5 colors — the shader samples them as a cyclic gradient.
static func build_palette(identity: String) -> PackedColorArray:
	var cols := colors_of(identity)
	var s: Array[Dictionary] = []
	for c in cols:
		s.append(swatch(c))

	var dark := Color(0, 0, 0)
	for sw in s:
		dark += sw.deep
	dark = dark / float(s.size())
	dark.a = 1.0

	match s.size():
		1:
			return PackedColorArray([s[0].deep, s[0].base, s[0].light, s[0].base, s[0].deep.lerp(s[0].base, 0.5)])
		2:
			return PackedColorArray([s[0].base, s[0].light, dark, s[1].light, s[1].base])
		3:
			return PackedColorArray([s[0].base, s[1].base, dark, s[2].base, s[0].light])
		4:
			return PackedColorArray([s[0].base, s[1].base, s[2].base, s[3].base, dark])
	return PackedColorArray([s[0].base, s[1].base, s[2].base, s[3].base, s[4].base])


## Glow color for highlights, sigil, sparks. Averaged then brightened.
static func build_accent(identity: String) -> Color:
	var cols := colors_of(identity)
	var acc := Color(0, 0, 0)
	for c in cols:
		acc += swatch(c).accent
	acc = acc / float(cols.size())
	var m := maxf(acc.r, maxf(acc.g, acc.b))
	if m > 0.0:
		acc = Color(acc.r / m, acc.g / m, acc.b / m)
	acc.a = 1.0
	return acc


## Blends each color's personality. Layers are weighted by 1/sqrt(n) so a
## 5-color mat still shows every effect instead of fading them all to 20%.
static func build_style(identity: String) -> Dictionary:
	var cols := colors_of(identity)
	var n := float(cols.size())
	var w := 1.0 / sqrt(n)
	var out := {"speed": 0.0}
	for k in LAYER_KEYS:
		out[k] = 0.0
	for c in cols:
		var tr := traits(c)
		out["speed"] += tr.get("speed", 1.0) / n
		out["warp_strength"] += tr.get("warp_strength", 1.0) / n
		for k in LAYER_KEYS:
			if k != "warp_strength":
				out[k] += tr.get(k, 0.0) * w
	for k in LAYER_KEYS:
		if k != "warp_strength":
			out[k] = minf(out[k], 1.2)
	return out


## Base colors for one mana color. Tweak these to restyle every identity at once.
static func swatch(c: String) -> Dictionary:
	match c:
		"W": return {"deep": Color("8f7440"), "base": Color("e2cf96"), "light": Color("fff4d6"), "accent": Color("ffe9a8")}
		"U": return {"deep": Color("0b2c66"), "base": Color("1f6fd1"), "light": Color("6fb8ff"), "accent": Color("9fe3ff")}
		"B": return {"deep": Color("120a1c"), "base": Color("3b2350"), "light": Color("6e4a8c"), "accent": Color("b48cff")}
		"R": return {"deep": Color("5a0e08"), "base": Color("c8341f"), "light": Color("ff7a3d"), "accent": Color("ffb347")}
		"G": return {"deep": Color("0e3a1a"), "base": Color("2e8b3e"), "light": Color("7fd06a"), "accent": Color("c8f27a")}
	# Colorless
	return {"deep": Color("2f343c"), "base": Color("7d8592"), "light": Color("d9dee6"), "accent": Color("e8f4ff")}


## Per-color "personality" — which shader layers it switches on.
static func traits(c: String) -> Dictionary:
	match c:
		"W": return {"speed": 0.9, "warp_strength": 0.7, "ray_amount": 1.0}
		"U": return {"speed": 0.9, "warp_strength": 1.2, "ripple_amount": 1.0}
		"B": return {"speed": 0.6, "warp_strength": 0.9, "void_amount": 1.0}
		"R": return {"speed": 1.4, "warp_strength": 1.5, "ember_amount": 1.0}
		"G": return {"speed": 0.8, "warp_strength": 1.0, "cell_amount": 1.0}
	return {"speed": 0.7, "warp_strength": 0.6, "shimmer_amount": 1.0, "cell_amount": 0.35}


static func _sorted(letters: String) -> String:
	var out := ""
	for ch in ORDER:
		if letters.contains(ch):
			out += ch
	return out
