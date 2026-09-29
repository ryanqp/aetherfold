class_name CardFace
extends RefCounted

## How a card dictionary should be drawn.
## "art" — real catalog art (or still loading it).
## "printed" — a normal card whose artwork is genuinely unavailable.
## "token" — an actual token permanent, not a card missing a picture.

const MODE_ART := "art"
const MODE_PRINTED := "printed"
const MODE_TOKEN := "token"


static func mode(card: Dictionary) -> String:
	if bool(card.get("is_token", false)):
		return MODE_TOKEN
	if has_artwork(card):
		return MODE_ART
	return MODE_PRINTED


static func has_artwork(card: Dictionary) -> bool:
	if str(card.get("scryfall_id", "")).strip_edges() != "":
		return true
	if str(card.get("imageUrl", "")).strip_edges() != "":
		return true
	var images: Variant = card.get("images", {})
	return images is Dictionary and not (images as Dictionary).is_empty()


## Caption inside the illustration window. A normal card never says "Card frame".
static func art_caption(card: Dictionary) -> String:
	if mode(card) == MODE_ART:
		return "Loading art…"
	return ""


static func is_normal_card(card: Dictionary) -> bool:
	if bool(card.get("is_token", false)):
		return false
	if str(card.get("name", "")).strip_edges() == "":
		return false
	if str(card.get("type", "")).strip_edges() == "":
		return false
	return mode(card) != MODE_TOKEN
