class_name GameState
extends RefCounted

var rules: FormatRules
var players: Array[PlayerState] = []
var objects: Dictionary = {}
var next_object_id: int = 1
var next_stack_id: int = 1
var next_timestamp: int = 1
var turn_number: int = 1
var active_player_id: int = 0
var priority_player_id: int = 0
var passed_since_action: Array[int] = []
var phase: int = EngineEnums.Phase.MAIN_1
var step: int = EngineEnums.Step.PRECOMBAT_MAIN
var land_played: Dictionary = {}
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


func _init() -> void:
	rules = FormatRules.commander_4p()
	rng = RngStream.new()
	log = GameLog.new()
