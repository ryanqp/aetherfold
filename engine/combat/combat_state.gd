class_name CombatState
extends RefCounted

var attacker_ids: Array[int] = []
var defending_player_id: int = 1
## attacker object id -> Array of blocker object ids. v1 allows one blocker.
var blockers: Dictionary = {}
