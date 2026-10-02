class_name GameObject
extends RefCounted

## A game object in a zone. Zone changes retire this id (CR 400.7).

var object_id: int = 0
var instance_uuid: String = ""
var owner_id: int = 0
var controller_id: int = 0
var zone: int = EngineEnums.ZoneId.LIBRARY
var definition = null
var timestamp: int = 0
var linked_from: int = 0
var face_id: int = 0
var is_token: bool = false
var is_commander: bool = false
var tapped: bool = false
var summoned_this_turn: bool = false
var damage_marked: int = 0
## Dealt damage this turn by a source with deathtouch (CR 702.2b, 704.5h). Cleared in cleanup.
var deathtouch_damage: bool = false
var counters: Dictionary = {}
var attachments: Array[int] = []
## Equipment: the creature this is attached to (0 = unattached). Checked for validity when read.
var attached_to: int = 0
## "As ~ enters, choose a creature type" (Icon of Ancestry, Herald's Horn, ...).
var chosen_type: String = ""
## "As ~ enters, choose a color other than green" (Thriving lands): the color its second mana ability makes.
var chosen_color: String = ""
## Hideaway (CR 702.75): the object id of the card this permanent exiled face down (0 = none).
var hideaway_card: int = 0
## Triggers limited to once each turn: ability id -> turn number it last fired.
var trigger_turns: Dictionary = {}
## CR 601.3 / "you may play that card this turn". -1 means no permission.
var may_play_controller: int = -1
## Kicker / multikicker (CR 702.33): how many times the additional cost was paid when this spell was cast.
var kicked: int = 0
## Zone it was cast from (EngineEnums.ZoneId), or -1 if it was never cast ("if you cast it", CR 601.2).
var cast_from: int = -1
## How the spell was cast: "", flashback, escape, retrace, dash, prowl, emerge, madness, miracle, suspend, morph, rebound.
var cast_mode: String = ""
## Face-down permanent (morph, manifest, cloak, disguise): a 2/2 with no name, abilities or types (CR 708).
var face_down: bool = false
## Cloak gives ward {2} while face down; other sources of ward are read from the card.
var ward_extra: String = ""
## Suspect (CR 701.60): menace and can't block.
var suspected: bool = false
## Dash (CR 702.109): haste, returns to its owner's hand at the beginning of the next end step.
var dashed: bool = false
## Haste from an effect that isn't a keyword on the card (suspend, "gains haste").
var granted_haste: bool = false
## Goad (CR 701.15): player ids that goaded this creature (until their next turn).
var goaded_by: Array = []
## Phasing (CR 702.26): treated as though it doesn't exist.
var phased_out: bool = false
## Echo (CR 702.30): the echo cost is still owed at the next upkeep.
var echo_owed: bool = false
## Planeswalker loyalty abilities (CR 606.3): the turn one was last activated (-1 = never).
var loyalty_turn: int = -1
## Gift (CR 702.174): the gift was promised as this spell was cast; permanents keep it.
var gift_promised: bool = false
## Encore (CR 702.141) tokens are sacrificed at the beginning of the next end step.
var sacrifice_at_end: bool = false
## Imprint: object ids of the cards this permanent exiled with its imprint ability (Duplicant).
var imprinted: Array = []
## An Aura put into the graveyard because what it enchanted left the battlefield: that object's id (Angelic Destiny).
var aura_host_left: int = 0
## Designations with no rules meaning of their own that effects look for (CR 701.37b monstrous, 702.171b saddled,
## harnessed, renowned ...): name -> true.
var marks: Dictionary = {}
## Regeneration shields (CR 701.19): each replaces one destruction this turn.
var regen_shields: int = 0
## Double-faced cards (CR 712): the front face's definition while the back face is up (transformed / converted).
var front_def = null
## Detain (CR 701.35): the player whose next turn ends it (-1 = not detained).
var detained_by: int = -1
## Space sculptor (CR 702.158): "alpha", "beta" or "gamma".
var sector: String = ""
## Soulbond (CR 702.95): the creature it is paired with (0 = unpaired).
var paired_with: int = 0
## Cipher (CR 702.99): object ids of the cards encoded on this creature (in exile).
var encoded: Array = []
## Mutate (CR 702.140): definitions of the cards under the top card of this merged permanent.
var merged: Array = []
## Turn this permanent was last declared as an attacker (boast, CR 702.142a).
var attacked_turn: int = -1
## {X} paid when the spell was cast (CR 107.3), mana spent on it (increment) and its colors (sunburst).
var x_paid: int = 0
var mana_spent: int = 0
var colors_spent: Array = []
## The turn this card was discarded (mayhem), foretold, plotted or exiled by warp (-1 = never).
var discarded_turn: int = -1
var foretold_turn: int = -1
var plotted_turn: int = -1
## Exiled cards that can be cast: "warp", "airbend" ({2}), "foretell", "plot". "" = not castable this way.
var exile_cast: String = ""
## Unearth (CR 702.84): exiled at the next end step or if it would leave the battlefield.
var unearthed: bool = false
## Bestow (CR 702.103): cast as an Aura; becomes a creature again when unattached.
var bestowed: bool = false
## Haunt (CR 702.55): the creature this exiled card haunts (0 = none).
var haunting: int = 0
