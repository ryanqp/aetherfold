class_name KeywordDb
extends RefCounted

## Reference table of keyword abilities and keyword actions, looked up by name when a card is loaded.
## `status` says what the engine does with it today:
##   ENFORCED  the engine applies the rule itself (combat, damage, targeting ...); nothing to read
##   READ      OracleIr turns it into an ability (equip, prowess)
##   NONE      has no effect the engine needs (devoid, partner, ascend)
##   MISSING   known, but not implemented yet; the card is listed as "not coded" with the keyword's name
## Add a keyword here once the engine does something with it, then change its status.

const KEYWORDS := {
	"flying": {"status": "ENFORCED", "cr": "702.9", "note": "Can be blocked only by creatures with flying or reach."},
	"reach": {"status": "ENFORCED", "cr": "702.17", "note": "Can block creatures with flying."},
	"menace": {"status": "ENFORCED", "cr": "702.110", "note": "Can't be blocked except by two or more creatures."},
	"first strike": {"status": "ENFORCED", "cr": "702.7", "note": "Deals combat damage before creatures without first strike."},
	"double strike": {"status": "ENFORCED", "cr": "702.4", "note": "Deals first-strike and regular combat damage."},
	"trample": {"status": "ENFORCED", "cr": "702.19", "note": "Excess combat damage goes to the player."},
	"deathtouch": {"status": "ENFORCED", "cr": "702.2", "note": "Any damage it deals to a creature is lethal."},
	"lifelink": {"status": "ENFORCED", "cr": "702.15", "note": "Damage dealt also gains you that much life."},
	"indestructible": {"status": "ENFORCED", "cr": "702.12", "note": "Not destroyed by lethal damage or destroy effects."},
	"hexproof": {"status": "ENFORCED", "cr": "702.11", "note": "Can't be the target of spells or abilities your opponents control."},
	"shroud": {"status": "ENFORCED", "cr": "702.18", "note": "Can't be the target of spells or abilities."},
	"haste": {"status": "ENFORCED", "cr": "702.10", "note": "Can attack and use {T} abilities the turn it arrives."},
	"defender": {"status": "ENFORCED", "cr": "702.3", "note": "Can't attack."},
	"vigilance": {"status": "ENFORCED", "cr": "702.20", "note": "Attacking doesn't cause it to tap."},
	"flash": {"status": "ENFORCED", "cr": "702.8", "note": "Can be cast any time you could cast an instant."},
	"protection from": {"status": "ENFORCED", "cr": "702.16", "note": "Colors only: can't be damaged, enchanted, blocked or targeted by that color."},
	"equip": {"status": "READ", "cr": "702.6", "note": "Attach to a creature you control, at sorcery speed."},
	"prowess": {"status": "READ", "cr": "702.108", "note": "Gets +1/+1 until end of turn whenever you cast a noncreature spell."},
	"devoid": {"status": "NONE", "cr": "702.114", "note": "Colorless."},
	"partner": {"status": "NONE", "cr": "702.124", "note": "Deck building only."},
	"ascend": {"status": "NONE", "cr": "702.131", "note": "City's blessing at ten permanents."},
	"ward": {"status": "MISSING", "cr": "702.21", "note": "Counter a spell or ability that targets it unless its controller pays the ward cost."},
	"kicker": {"status": "MISSING", "cr": "702.33", "note": "Optional extra cost on casting."},
	"multikicker": {"status": "MISSING", "cr": "702.33c", "note": "Optional extra cost, any number of times."},
	"cycling": {"status": "MISSING", "cr": "702.29", "note": "Pay the cost and discard this card: draw a card."},
	"landcycling": {"status": "MISSING", "cr": "702.29", "note": "Pay the cost and discard this card: search for a land."},
	"flashback": {"status": "MISSING", "cr": "702.34", "note": "Cast from the graveyard for its flashback cost."},
	"crew": {"status": "MISSING", "cr": "702.122", "note": "Tap creatures with total power N: this Vehicle becomes a creature."},
	"convoke": {"status": "MISSING", "cr": "702.51", "note": "Tapping creatures helps pay for the spell."},
	"hideaway": {"status": "MISSING", "cr": "702.75", "note": "Look at the top cards, exile one face down."},
	"evolve": {"status": "MISSING", "cr": "702.100", "note": "+1/+1 counter when a bigger creature enters."},
	"undying": {"status": "MISSING", "cr": "702.93", "note": "Returns with a +1/+1 counter if it had none."},
	"persist": {"status": "MISSING", "cr": "702.79", "note": "Returns with a -1/-1 counter if it had none."},
	"cascade": {"status": "MISSING", "cr": "702.85", "note": "Cast a cheaper card from the top of your library for free."},
	"annihilator": {"status": "MISSING", "cr": "702.86", "note": "Defending player sacrifices permanents when it attacks."},
	"exalted": {"status": "MISSING", "cr": "702.83", "note": "A creature attacking alone gets +1/+1."},
	"extort": {"status": "MISSING", "cr": "702.101", "note": "Pay {W/B} on cast: drain 1."},
	"fabricate": {"status": "MISSING", "cr": "702.123", "note": "Counters or a Servo token on entering."},
	"proliferate": {"status": "MISSING", "cr": "701.34", "note": "Add one more counter of each kind already on permanents or players."},
	"explore": {"status": "MISSING", "cr": "701.44", "note": "Reveal the top card: land to hand, else +1/+1 counter."},
	"discover": {"status": "MISSING", "cr": "701.57", "note": "Cast or play a cheaper card found in the library for free."},
	"investigate": {"status": "MISSING", "cr": "701.16", "note": "Create a Clue token."},
	"the monarch": {"status": "MISSING", "cr": "724", "note": "Draw at your end step."},
	"changeling": {"status": "MISSING", "cr": "702.73", "note": "Is every creature type."},
	"enlist": {"status": "MISSING", "cr": "702.154", "note": "Tap a creature to add its power when attacking."},
	"affinity": {"status": "MISSING", "cr": "702.41", "note": "Costs {1} less for each of the named permanent."},
	"toxic": {"status": "MISSING", "cr": "702.164", "note": "Combat damage gives poison counters."},
	"infect": {"status": "MISSING", "cr": "702.90", "note": "Damage as -1/-1 counters and poison."},
}


## "Ward {2}" -> {"name": "ward", ...entry}; {} when the line doesn't start with a known keyword.
static func lookup(line: String) -> Dictionary:
	var low := line.to_lower().strip_edges()
	var best := ""
	for k in KEYWORDS:
		var key := str(k)
		if low == key or (low.begins_with(key) and key.length() > best.length() and _boundary(low, key.length())):
			best = key
	if best == "":
		return {}
	var out: Dictionary = (KEYWORDS[best] as Dictionary).duplicate()
	out["name"] = best
	return out


static func _boundary(low: String, n: int) -> bool:
	if low.length() <= n:
		return true
	return low[n] in [" ", "{", "—", ","]


## Whether every comma-separated part of a line is a keyword the engine already handles (or needs none).
static func line_is_handled(line: String) -> bool:
	var parts := line.split(",")
	for part in parts:
		var e := lookup(str(part))
		if e.is_empty() or not str(e.get("status")) in ["ENFORCED", "READ", "NONE"]:
			return false
		if str(e.get("name")) == "protection from" and not _color_protection(str(part)):
			return false
	return true


static func _color_protection(part: String) -> bool:
	var low := part.to_lower().strip_edges()
	for c in ["white", "blue", "black", "red", "green"]:
		if low == "protection from " + c:
			return true
	return false


## "Ward {1}" -> "Ward {1} (not enforced yet)" for a known but unimplemented keyword, else the line.
static func describe_unread(line: String) -> String:
	var e := lookup(line)
	if not e.is_empty() and str(e.get("status")) == "MISSING":
		return "%s (%s: not enforced yet)" % [line, str(e.get("name"))]
	return line
