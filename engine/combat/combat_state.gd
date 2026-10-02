class_name CombatState
extends RefCounted

var attacker_ids: Array[int] = []
var defending_player_id: int = -1
## attacker object id -> defending player id. Empty means every attacker uses defending_player_id.
var defenders: Dictionary = {}
## attacker object id -> Array of blocker object ids, in damage assignment order.
var blockers: Dictionary = {}
## True once the defending player has declared blockers this combat (even "no blocks").
var blocks_declared: bool = false
