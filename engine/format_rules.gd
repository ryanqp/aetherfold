class_name FormatRules
extends Resource

## Commander-first format flags. Engine default is 4-player; the shipping table uses 1v1.

@export var format_id: StringName = &"commander"
@export var player_count: int = 4
@export var starting_life: int = 40
@export var starting_hand: int = 7
@export var first_player_skips_draw: bool = false
@export var commander_enabled: bool = true
@export var commander_damage_to_lose: int = 21
@export var commander_tax_step: int = 2
@export var singleton: bool = true
@export var allow_demo_illegal_decks: bool = false
@export var range_of_influence: int = 0


static func commander_4p() -> FormatRules:
	var f := FormatRules.new()
	f.player_count = 4
	f.first_player_skips_draw = false
	return f


static func commander_1v1_table() -> FormatRules:
	var f := FormatRules.new()
	f.player_count = 2
	f.first_player_skips_draw = true
	f.allow_demo_illegal_decks = false
	return f
