class_name PlayerState
extends RefCounted

var player_id: int = 0
var name: String = ""
var life: int = 40
var mana = null
var commander_ids: Array[int] = []
var commander_cast_count: Dictionary = {}
var commander_damage_from: Dictionary = {}
var lost: bool = false
## CR 704.5c: ten or more poison counters lose the game (infect, toxic).
var poison: int = 0
var mulligan_count: int = 0
## Damage dealt to this player this turn (bloodthirst, prowl).
var damaged_this_turn: bool = false
## Types and subtypes of creatures this player controls that dealt combat damage to a player this turn (prowl).
var combat_damagers_types: Array = []
var draws_this_turn: int = 0
## Nonland permanents that entered the battlefield under this player's control this turn (celebration).
var nonland_entered_this_turn: int = 0
## Spells this player cast this turn: one Array of lower-case types per spell ("first noncreature spell each turn").
var spells_this_turn: Array = []
## Start your engines! (CR 702.179): speed 0 means no speed yet; the turn it last went up.
var speed: int = 0
var speed_turn: int = -1
## Dungeons (CR 309): the dungeon being explored ("" = none), the room the venture marker is in, completed dungeons.
var dungeon: String = ""
var dungeon_room: String = ""
var dungeons_completed: Array = []
## The Ring tempts you (CR 701.54): how many times, and the current Ring-bearer's object id.
var ring_level: int = 0
var ring_bearer: int = 0
## Epic (CR 702.50): this player can't cast spells for the rest of the game.
var epic_locked: bool = false
## Life gained / lost this turn (spectacle, "if you gained life this turn").
var life_gained_this_turn: int = 0
var life_lost_this_turn: int = 0
## Storied (CR 702.195): enduring story.
var enduring_story: bool = false
## Freerunning (CR 702.173): your commander dealt combat damage to a player this turn.
var commander_hit_this_turn: bool = false
