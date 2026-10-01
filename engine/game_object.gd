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
