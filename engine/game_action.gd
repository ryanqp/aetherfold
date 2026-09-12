class_name GameAction
extends RefCounted

enum Kind {
	PASS_PRIORITY,
	PLAY_LAND,
	CAST_SPELL,
	ACTIVATE_ABILITY,
	ACTIVATE_MANA_ABILITY,
	CHOOSE_TARGETS,
	PAY_MANA,
	CONFIRM_PAY,
	CANCEL_CAST,
	DECLARE_ATTACKERS,
	DECLARE_BLOCKERS,
	ASSIGN_COMBAT_DAMAGE,
	CHOOSE_SBA,
	CHOOSE_REPLACEMENT,
	CONCEDE,
}

var kind: Kind = Kind.PASS_PRIORITY
var player_id: int = 0
var object_id: int = 0
var stack_id: int = 0
var ability_id: StringName = &""
var targets: Array = []
var extra: Dictionary = {}
