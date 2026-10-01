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
## CR 601.3 / "you may play that card this turn". -1 means no permission.
var may_play_controller: int = -1
