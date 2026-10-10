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
## Combat damage the attacking player divided by hand: "attacker:pass" -> {blocker id (or the defending player's target id): amount}.
var damage_plans: Dictionary = {}
## Damage passes finished so far this combat (0, 1 after first strike, 2 when done) and whether there are two of them.
var damage_passes_done: int = 0
var damage_split: bool = false
