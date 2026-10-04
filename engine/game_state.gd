class_name GameState
extends RefCounted

var rules: FormatRules
var players: Array[PlayerState] = []
var objects: Dictionary = {}
var next_object_id: int = 1
var next_stack_id: int = 1
var next_timestamp: int = 1
var turn_number: int = 1
## CR 724: the player who is the monarch (draws at their end step), -1 for none.
var monarch_id: int = -1
var active_player_id: int = 0
var priority_player_id: int = 0
var passed_since_action: Array[int] = []
var phase: int = EngineEnums.Phase.MAIN_1
var step: int = EngineEnums.Step.PRECOMBAT_MAIN
var land_played: Dictionary = {}
## Per player {turn, n}: land drops taken, for effects that allow more than one (CR 305.2).
## Progenitor's Icon: {pid, subtype, turn} grants of "the next spell of that type has flash".
var flash_grants: Array = []
var land_drops: Dictionary = {}
var stack = null
var zones = null
var combat = null
var effects: Array = []
var waiting_triggers: Array = []
var mode: int = EngineEnums.EngineMode.GIVING_PRIORITY
var awaiting: Dictionary = {}
var rng: RngStream
var rng_seed: int = 1
var ended: bool = false
var winners: Array[int] = []
var log: GameLog
var replacement = null
var pending_decision = null
## The active player must draw for the turn before the turn can go on (manual draw seats only).
var draw_pending: bool = false
## Permanents that exiled cards "until it leaves the battlefield": source object id -> exiled object ids.
var exile_links: Dictionary = {}
## Rebound (CR 702.88): cards exiled to be cast again at their owner's next upkeep: {owner, object_id, turn}.
var rebound_queue: Array = []
## Emblems (CR 114) players have: {player_id, text}. Their rules live in `effects` (continuous, never ending).
var emblems: Array = []


func _init() -> void:
	rules = FormatRules.commander_4p()
	rng = RngStream.new()
	log = GameLog.new()
## Day and night (CR 726): "" before it has ever been day or night, then "day" or "night".
var day_night: String = ""
## The initiative (CR 725): the player who has it (-1 = nobody).
var initiative_id: int = -1
## Permanents put into a graveyard from the battlefield this turn (gravestorm).
var died_this_turn: int = 0
## Delayed effects ("sacrifice it at the beginning of the next end step"): {step, whose, turn, step_index, controller, object_id, action}.
var delayed: Array = []
## Damage prevention shields ("prevent the next 3 damage that would be dealt to any target this turn"): {to, player_id, object_id, combat_only, n (-1 = all)}.
var prevention: Array = []
## "You may play an additional land this turn": {turn, n} per player.
var extra_land_once: Dictionary = {}
## Creatures put into a graveyard from the battlefield this turn (morbid).
var creatures_died_this_turn: int = 0
## Delayed "return it when it dies or is exiled" for earthbent lands: object ids.
var earthbent: Array = []
## Firebending mana a player keeps until end of combat: player id -> amount of {R}.
var combat_mana: Dictionary = {}
