@tool
extends McpTestSuite

## Online matches: the guest calls the coin, and the guest's actions run on the host as seat 1.


func suite_name() -> String:
	return "online_session"


func _online_session() -> GameSession:
	var s := GameSession.new()
	s.skip_ai = true
	s.coin_flip = true
	s.start_table_demo(1)
	return s


func test_guest_calls_the_coin() -> void:
	var s := _online_session()
	assert_eq(s.match_start, GameSession.MatchStart.COIN_FLIP, "online matches flip a coin")
	assert_eq(s.flip_caller, 1, "the guest (seat 1) calls it")
	s.call_coin(true, 1)
	assert_true(s.flip_called)
	var guest_wins: bool = s.coin_heads
	assert_eq(s.first_player, 1 if guest_wins else 0, "the caller goes first when the call is right")
	var v := TableView.from_engine(s.engine, s)
	assert_false(v.caller_is_you, "from the host's seat the guest is the caller")
	assert_true(v.flip_called)


func test_finish_flip_deals_hands_and_starts_the_mulligan() -> void:
	var s := _online_session()
	s.call_coin(false, 1)
	s.finish_coin_flip()
	assert_eq(s.match_start, GameSession.MatchStart.MULLIGAN_DECISION)
	assert_eq(s.engine.hand_size(0), 7)
	assert_eq(s.engine.hand_size(1), 7)
	assert_false(bool(s.kept.get(1, true)), "the guest still has to keep")


func test_as_seat_restores_the_hosts_seat() -> void:
	var s := _online_session()
	s.call_coin(true, 1)
	s.finish_coin_flip()
	var seen := [-1]
	s.as_seat(1, func() -> void: seen[0] = s.you_seat)
	assert_eq(seen[0], 1, "ran as the guest")
	assert_eq(s.you_seat, 0, "back to the host afterwards")
