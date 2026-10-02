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


func test_nested_as_seat_keeps_the_swap_flag_until_the_outer_call_ends() -> void:
	var s := _online_session()
	var inner_swapped := [false]
	var after_inner := [false]
	s.as_seat(1, func() -> void:
		s.as_seat(0, func() -> void: inner_swapped[0] = s._swapped)
		after_inner[0] = s._swapped
	)
	assert_true(inner_swapped[0])
	assert_true(after_inner[0], "still swapped inside the outer call")
	assert_false(s._swapped, "and cleared at the end")
	assert_eq(s.you_seat, 0)


func test_prompt_for_is_empty_when_nothing_is_asked() -> void:
	var s := _online_session()
	assert_true(s.prompt_for(0).is_empty())
	assert_true(s.prompt_for(1).is_empty())


func test_land_prompt_belongs_to_the_seat_that_opened_it() -> void:
	var s := _online_session()
	s.land_prompt = {"object_id": 5, "text": "Pay 2 life?", "yes": "Pay", "no": "Tapped"}
	s.prompt_seat = 1
	assert_true(s.prompt_for(0).is_empty(), "not the host's question")
	var p := s.prompt_for(1)
	assert_eq(str(p.kind), "land")
	assert_eq((p.options as Array).size(), 2)


func test_guest_chooses_which_cards_go_to_the_bottom() -> void:
	var s := _online_session()
	s.call_coin(true, 1)
	s.finish_coin_flip()
	s.take_mulligan(1)
	s.keep_hand(1)
	assert_eq(int(s.put_back_need.get(1, 0)), 1, "one card to put back after one mulligan")
	assert_false(bool(s.kept.get(1, false)), "not kept until the card is chosen")
	var hand: Zone = s.engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 1)
	var pick := int(hand.object_ids[0])
	var lib_before := s.engine.library_size(1)
	s.put_back_for(1, pick)
	assert_true(bool(s.kept.get(1, false)), "kept once the card is back")
	assert_eq(s.engine.library_size(1), lib_before + 1)
	assert_eq(s.engine.hand_size(1), 6)


func test_guest_can_keep_while_the_host_is_putting_cards_back() -> void:
	var s := _online_session()
	s.call_coin(true, 1)
	s.finish_coin_flip()
	s.take_mulligan(0)
	s.keep_hand(0)
	assert_eq(s.match_start, GameSession.MatchStart.PUT_BACK)
	s.keep_hand(1)
	assert_true(bool(s.kept.get(1, false)), "the guest's keep is not ignored")
