class_name StackEntry
extends RefCounted

enum Kind { SPELL, ACTIVATED, TRIGGERED }

var stack_id: int = 0
var kind: int = Kind.SPELL
var object_id: int = 0
var source_id: int = 0
var controller_id: int = 0
var ability_id: StringName = &""
var targets: Array = []
var effects: Array = []
