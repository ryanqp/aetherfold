class_name ContinuousEffect
extends RefCounted

## Layer 7c modifiers. Empty object_ids and empty query means "every object" (older pumps).
var power: int = 0
var toughness: int = 0
var until_eot: bool = true
var query: Dictionary = {}
var controller_id: int = 0
var source_id: int = 0
var object_ids: Array = []
var timestamp: int = 0
## Layer 4: replace creature subtypes. Empty means "do not touch types".
var set_subtypes: PackedStringArray = PackedStringArray()
## Layer 7b. Flags distinguish "set to 0" from "do not set".
var sets_power: bool = false
var set_power: int = 0
var sets_toughness: bool = false
var set_toughness: int = 0
## Layer 6.
var add_keywords: PackedStringArray = PackedStringArray()
var gain_ability_ids: Array = []

## Layer 4: card types added (a crewed Vehicle becomes an artifact creature).
var add_types: PackedStringArray = PackedStringArray()
## Abilities (Ability objects) the affected permanents gain (backup, "gains '...'").
var add_abilities: Array = []
