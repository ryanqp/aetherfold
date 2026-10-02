extends Node

signal status_changed(text: String)
signal peer_ready
signal lobby_changed
signal view_received
signal match_begin
signal address_changed
signal countdown_changed(seconds: int)
signal chat_received(sender: String, text: String, mine: bool)
signal notice_received(text: String)
## The other player left (or dropped out of) the room. Emitted with their name.
signal peer_left(player_name: String)
## Host -> guest: the ways to play a card they clicked (labels only; they answer with the index).
signal menu_received(object_id: int, title: String, entries: Array)

const GAME_PORT := 27777
const BEACON_PORT := 27778
const BEACON_PREFIX := "AETHERFOLD|"
## Only two seats exist at the table (host = seat 0, guest = seat 1), so a room holds two. Raising it to 8 is pinned
## until the table can draw and route more than two players (T-004).
const MAX_TOTAL_PLAYERS := 2

var peer: ENetMultiplayerPeer
var udp: PacketPeerUDP
var code: String = ""
var role: String = ""
var last_status: String = "Offline"
var connected_peer_ids: Array[int] = []
var ready_peer_ids: Array[int] = []
var guest_decks: Dictionary = {}
var last_view = null
var _beacon_acc := 0.0
var _listen_ip: String = ""
var remote_deck_id: String = ""
var remote_name: String = ""
## How to reach this host from the internet: the public IP, and whether the router opened the port (UPnP).
var public_ip: String = ""
var port_open: bool = false
var upnp_tried: bool = false
var _upnp: UPNP = null
var _connect_token := 0
const UPNP_LEASE := 3600
const UPNP_RENEW_EVERY := 1800.0
var _renew_acc := 0.0
var _last_view_hash := 0


func generate_code() -> String:
	var alphabet := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out := ""
	for _i in 6:
		out += alphabet[rng.randi_range(0, alphabet.length() - 1)]
	return out


func host_room(wanted_code: String = "") -> String:
	leave()
	code = wanted_code.strip_edges().to_upper()
	if code == "":
		code = generate_code()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_TOTAL_PLAYERS - 1)
	if err != OK:
		_set_status("Could not host on port %d." % GAME_PORT)
		return ""
	multiplayer.multiplayer_peer = peer
	role = "host"
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_start_beacon()
	_lobby = {1: {"name": "Host", "deck": "", "ready": false, "rec": {}}}
	_count_left = -1.0
	countdown = -1
	_lobby_updated()
	_set_status("Room %s — waiting for players (1/%d)…" % [code, MAX_TOTAL_PLAYERS])
	_open_to_internet()
	return code


# --- Playing over the internet -------------------------------------------------------------------------
## A friend outside your network connects to your public IP on GAME_PORT (UDP). Most routers can open that port
## for you with UPnP; if yours can't, forward UDP 27777 by hand or put both players on a VPN (Tailscale, Radmin).

## Asks the router to forward GAME_PORT (off the main thread: discovery can take a couple of seconds), then looks
## up the public IP.
func _open_to_internet() -> void:
	public_ip = ""
	port_open = false
	upnp_tried = false
	WorkerThreadPool.add_task(_upnp_worker)
	_fetch_public_ip()


func _upnp_worker() -> void:
	var u := UPNP.new()
	var found := u.discover(2000, 2, "InternetGatewayDevice")
	var ok := false
	var ext := ""
	if found == UPNP.UPNP_RESULT_SUCCESS and u.get_gateway() != null and u.get_gateway().is_valid_gateway():
		ok = u.add_port_mapping(GAME_PORT, GAME_PORT, "Aetherfold", "UDP", UPNP_LEASE) == UPNP.UPNP_RESULT_SUCCESS
		ext = u.query_external_address()
	_upnp_done.call_deferred(u, ok, ext)


func _upnp_done(u: UPNP, ok: bool, ext: String) -> void:
	_upnp = u
	upnp_tried = true
	port_open = ok
	if role != "host":
		_close_port()
		return
	if ext != "" and public_ip == "":
		public_ip = ext
	_refresh_share()


func _fetch_public_ip() -> void:
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	http.request_completed.connect(func(_result: int, code_: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		var ip := body.get_string_from_utf8().strip_edges()
		if code_ == 200 and ip.is_valid_ip_address() and role == "host":
			public_ip = ip
			_refresh_share()
		http.queue_free()
	)
	if http.request("https://api.ipify.org") != OK:
		http.queue_free()


## The address to give a friend: "203.0.113.5" (the port is the default one), or "" until it is known.
func share_address() -> String:
	return public_ip


## What the host should tell the friend, shown under the room status.
func share_text() -> String:
	if role != "host":
		return ""
	var lines := PackedStringArray()
	if public_ip != "":
		lines.append("Online address for your friend: %s" % public_ip)
	else:
		lines.append("Looking up your online address…")
	if upnp_tried and not port_open:
		lines.append("Your router didn't open port %d automatically. Forward UDP %d to this PC, or play over a VPN such as Tailscale (use that IP)." % [GAME_PORT, GAME_PORT])
	elif port_open:
		lines.append("Port %d opened on your router." % GAME_PORT)
	return "\n".join(lines)


func _refresh_share() -> void:
	address_changed.emit()
	if role == "host":
		_set_status("Room %s — %d/%d players joined.\n%s" % [code, player_count(), MAX_TOTAL_PLAYERS, share_text()])


func _close_port() -> void:
	if _upnp != null and port_open:
		var u := _upnp
		WorkerThreadPool.add_task(func() -> void: u.delete_port_mapping(GAME_PORT, "UDP"))
	_upnp = null
	port_open = false


func join_room(wanted_code: String, ip: String = "") -> void:
	leave()
	code = wanted_code.strip_edges().to_upper()
	role = "client"
	_listen_ip = ip.strip_edges()
	if _listen_ip != "":
		_connect_to(_listen_ip)
		return
	udp = PacketPeerUDP.new()
	var bind_err := udp.bind(BEACON_PORT)
	if bind_err != OK:
		_set_status("Could not listen for rooms. Try joining with the host IP.")
		return
	_set_status("Looking for room %s on the LAN…" % code)


func leave() -> void:
	_connect_token += 1
	_last_view_hash = 0
	_lobby.clear()
	_unverified.clear()
	roster = []
	countdown = -1
	_count_left = -1.0
	_close_port()
	public_ip = ""
	upnp_tried = false
	if multiplayer.connected_to_server.is_connected(_on_connected_ok):
		multiplayer.connected_to_server.disconnect(_on_connected_ok)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_gone):
		multiplayer.server_disconnected.disconnect(_on_server_gone)
	if udp != null:
		udp.close()
		udp = null
	if peer != null:
		peer.close()
		peer = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	role = ""
	code = ""
	connected_peer_ids.clear()
	ready_peer_ids.clear()
	guest_decks.clear()
	remote_deck_id = ""
	last_view = null
	_set_status("Offline")


func is_connected_peer() -> bool:
	return not connected_peer_ids.is_empty()


## Total seated players, including the host itself.
func player_count() -> int:
	return 1 + connected_peer_ids.size()


func max_players() -> int:
	return MAX_TOTAL_PLAYERS



# --- The lobby: names, decks, ready flags and the start countdown -------------------------------------------
## Everyone picks a deck and presses Ready. The host keeps the truth (_lobby: peer id -> {name, deck, ready, rec},
## the host itself is id 1), tells everyone the roster after every change, and once every player is ready counts
## down START_DELAY seconds, then starts the match. Anyone un-readying or leaving cancels the countdown.

const START_DELAY := 3.0

## The roster as the host last sent it: [{id, name, deck, ready}], host first.
var roster: Array = []
## Seconds left before the match starts (3, 2, 1), or -1 when no countdown is running.
var countdown: int = -1
var _lobby: Dictionary = {}
var _count_left := -1.0


func my_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1


## Tell the lobby who you are and which deck you will play (the full deck record, so the host can build it).
## Changing either un-readies you.
func send_profile(player_name: String, deck_name: String, rec: Dictionary) -> void:
	if role == "host":
		_set_profile(1, player_name, deck_name, rec)
	elif role == "client":
		announce_profile.rpc_id(1, player_name, deck_name, rec)


func set_my_ready(is_ready: bool) -> void:
	if role == "host":
		_set_ready(1, is_ready)
	elif role == "client":
		announce_ready.rpc_id(1, is_ready)


## Compatibility: guests used to call this.
func set_ready(is_ready: bool) -> void:
	set_my_ready(is_ready)


func ready_count() -> int:
	var n := 0
	for r in roster:
		if bool((r as Dictionary).get("ready", false)):
			n += 1
	return n


func _set_profile(id: int, player_name: String, deck_name: String, rec: Dictionary) -> void:
	if not _lobby.has(id):
		return
	var e: Dictionary = _lobby[id]
	e["name"] = player_name.strip_edges().substr(0, 20) if player_name.strip_edges() != "" else "Player"
	e["deck"] = deck_name
	e["rec"] = rec
	e["ready"] = false
	_lobby_updated()


func _set_ready(id: int, is_ready: bool) -> void:
	if not _lobby.has(id):
		return
	var e: Dictionary = _lobby[id]
	if is_ready and (e.get("rec", {}) as Dictionary).is_empty():
		return  ## can't be ready without a deck
	e["ready"] = is_ready
	_lobby_updated()


@rpc("any_peer", "reliable")
func announce_profile(player_name: String, deck_name: String, rec: Dictionary) -> void:
	if role != "host":
		return
	_set_profile(multiplayer.get_remote_sender_id(), player_name, deck_name, rec)


@rpc("any_peer", "reliable")
func announce_ready(is_ready: bool) -> void:
	if role != "host":
		return
	_set_ready(multiplayer.get_remote_sender_id(), is_ready)


## Host: rebuild the roster, send it to everybody, and start or cancel the countdown.
func _lobby_updated() -> void:
	var out: Array = []
	var ids: Array = _lobby.keys()
	ids.sort()
	ready_peer_ids.clear()
	for id in ids:
		var e: Dictionary = _lobby[id]
		out.append({"id": int(id), "name": str(e.get("name", "Player")), "deck": str(e.get("deck", "")), "ready": bool(e.get("ready", false))})
		if int(id) != 1 and bool(e.get("ready", false)):
			ready_peer_ids.append(int(id))
	roster = out
	for pid in connected_peer_ids:
		receive_roster.rpc_id(pid, out)
	lobby_changed.emit()
	_check_start()


@rpc("authority", "reliable")
func receive_roster(r: Array) -> void:
	if role != "client":
		return
	roster = r
	lobby_changed.emit()


@rpc("authority", "reliable")
func receive_countdown(n: int) -> void:
	if role != "client":
		return
	countdown = n
	countdown_changed.emit(n)


## True when at least two players are in the lobby and every one of them is ready with a deck.
func everyone_ready() -> bool:
	if _lobby.size() < 2:
		return false
	for id in _lobby:
		var e: Dictionary = _lobby[id]
		if not bool(e.get("ready", false)) or (e.get("rec", {}) as Dictionary).is_empty():
			return false
	return true


func _check_start() -> void:
	if role != "host":
		return
	if everyone_ready():
		if _count_left < 0.0:
			_count_left = START_DELAY
			_announce_countdown(int(ceil(_count_left)))
	elif _count_left >= 0.0:
		_count_left = -1.0
		_announce_countdown(-1)


func _announce_countdown(n: int) -> void:
	countdown = n
	countdown_changed.emit(n)
	for pid in connected_peer_ids:
		receive_countdown.rpc_id(pid, n)


## Countdown over: build the match from the first two players' decks and send everyone to the table.
func _start_now() -> void:
	var guest_id := 0
	var ids: Array = _lobby.keys()
	ids.sort()
	for id in ids:
		if int(id) != 1:
			guest_id = int(id)
			break
	if guest_id == 0 or not everyone_ready():
		_announce_countdown(-1)
		return
	var host_e: Dictionary = _lobby[1]
	var guest_e: Dictionary = _lobby[guest_id]
	var app := get_node_or_null("/root/AppState")
	if app != null:
		app.player_rec = host_e.rec
		app.rival_rec = guest_e.rec
		app.player_name = str(host_e.name)
		app.rival_name = str(guest_e.name)
		app.mp_role = "host"
		app.mp_code = code
		app.you_seat = 0
		app.skip_ai = true
	_last_view_hash = 0
	begin_match.rpc(str(host_e.name), str(guest_e.name))
	match_begin.emit()


func send_action(kind: String, payload: Dictionary = {}) -> void:
	if role != "client":
		return
	receive_action.rpc_id(1, kind, payload)


func broadcast_view(view) -> void:
	if role != "host" or connected_peer_ids.is_empty():
		return
	var plain := {}
	if view != null and view.has_method("to_plain_for_remote"):
		plain = view.to_plain_for_remote()
		plain["selected_id"] = ""  ## the host's own selection means nothing to the guest and would defeat the change check
	## Nothing changed since the last send: skip it (T-013). A newly seated guest resets this so it gets the board.
	var h := plain.hash()
	if h == _last_view_hash:
		return
	_last_view_hash = h
	# Every connected guest currently gets the same 2-seat (host vs.
	# seat 1) view until #19/#20 add real per-seat routing for 3+
	# networked players; guests past the first are spectating seat 1.
	for pid in connected_peer_ids:
		receive_view.rpc_id(pid, plain)


func _process(delta: float) -> void:
	if role == "host" and udp != null:
		_beacon_acc += delta
		if _beacon_acc >= 1.0:
			_beacon_acc = 0.0
			_send_beacon()
	if role == "client" and udp != null and peer == null:
		_poll_beacon()
	## Keep the router's port mapping alive: UPnP leases are asked for 1 hour and renewed every 30 minutes (T-008).
	if role == "host" and port_open and _upnp != null:
		_renew_acc += delta
		if _renew_acc >= UPNP_RENEW_EVERY:
			_renew_acc = 0.0
			var u := _upnp
			WorkerThreadPool.add_task(func() -> void: u.add_port_mapping(GAME_PORT, GAME_PORT, "Aetherfold", "UDP", UPNP_LEASE))
	if role == "host" and _count_left >= 0.0:
		_count_left -= delta
		var shown := int(ceil(_count_left))
		if _count_left <= 0.0:
			_count_left = -1.0
			_announce_countdown(0)
			_start_now()
		elif shown != countdown:
			_announce_countdown(shown)


func _start_beacon() -> void:
	udp = PacketPeerUDP.new()
	udp.set_broadcast_enabled(true)
	udp.bind(0)
	_send_beacon()


func _send_beacon() -> void:
	if udp == null or code == "":
		return
	var msg := "%s%s|%d" % [BEACON_PREFIX, code, GAME_PORT]
	udp.set_dest_address("255.255.255.255", BEACON_PORT)
	udp.put_packet(msg.to_utf8_buffer())


func _poll_beacon() -> void:
	while udp.get_available_packet_count() > 0:
		var packet := udp.get_packet().get_string_from_utf8()
		if not packet.begins_with(BEACON_PREFIX):
			continue
		var rest := packet.substr(BEACON_PREFIX.length())
		var bits := rest.split("|")
		if bits.size() < 1:
			continue
		if str(bits[0]).to_upper() != code:
			continue
		var ip := udp.get_packet_ip()
		if ip == "":
			continue
		udp.close()
		udp = null
		_connect_to(ip)
		return


## "203.0.113.5", "203.0.113.5:27777" or "my.host.name" -> {host, port}.
static func parse_address(text: String) -> Dictionary:
	var t := text.strip_edges()
	var port := GAME_PORT
	var colon := t.rfind(":")
	if colon > 0 and t.find(":") == colon:
		var p := t.substr(colon + 1)
		if p.is_valid_int() and int(p) > 0 and int(p) < 65536:
			port = int(p)
		t = t.substr(0, colon)
	return {"host": t, "port": port}


func _connect_to(address: String) -> void:
	var a := parse_address(address)
	var host := str(a.host)
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(host, int(a.port))
	if err != OK:
		peer = null
		_set_status("Could not connect to %s." % address)
		return
	multiplayer.multiplayer_peer = peer
	if not multiplayer.connected_to_server.is_connected(_on_connected_ok):
		multiplayer.connected_to_server.connect(_on_connected_ok)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_gone)
	_set_status("Connecting to %s…" % address)
	## A host that can't be reached just stays silent; say so after a while.
	_connect_token += 1
	get_tree().create_timer(12.0).timeout.connect(_connect_timeout.bind(_connect_token, address))


func _connect_timeout(token: int, address: String) -> void:
	if token != _connect_token or role != "client" or is_connected_peer():
		return
	_set_status("No answer from %s. Check the address, that the host is in a room, and that UDP port %d is open on their router (or use a VPN)." % [address, GAME_PORT])


## Bump this whenever an RPC signature or the lobby / match flow changes: host and guest must match (see T-001).
const PROTOCOL_VERSION := 4
const VERSION_WAIT := 5.0

## Peers that connected but have not yet said which version they run (host only).
var _unverified: Dictionary = {}


func _on_peer_connected(id: int) -> void:
	## A guest is only seated once it has told us its version; one that never does is running an older build.
	_unverified[id] = true
	get_tree().create_timer(VERSION_WAIT).timeout.connect(func() -> void:
		if role == "host" and _unverified.has(id):
			_unverified.erase(id)
			_set_status("A player connected with an older version of the game and was turned away. You both need the latest version.")
			if peer != null:
				peer.disconnect_peer(id)
	)


@rpc("any_peer", "reliable")
func announce_version(version: int) -> void:
	if role != "host":
		return
	var id := multiplayer.get_remote_sender_id()
	if not _unverified.has(id):
		return
	_unverified.erase(id)
	if version != PROTOCOL_VERSION:
		_set_status("A player on a different version (theirs %d, yours %d) was turned away. You both need the latest version." % [version, PROTOCOL_VERSION])
		reject_version.rpc_id(id, "Your game is a different version from the host's (yours %d, host %d). Update to the latest version and try again." % [version, PROTOCOL_VERSION])
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if peer != null:
				peer.disconnect_peer(id)
		)
		return
	_accept_peer(id)


@rpc("authority", "reliable")
func reject_version(text: String) -> void:
	if role != "client":
		return
	leave()
	_set_status(text)
	lobby_changed.emit()


func _accept_peer(id: int) -> void:
	_last_view_hash = 0
	if not connected_peer_ids.has(id):
		connected_peer_ids.append(id)
	ready_peer_ids.erase(id)
	_lobby[id] = {"name": "Player", "deck": "", "ready": false, "rec": {}}
	_set_status("Room %s — %d/%d players joined.\n%s" % [code, player_count(), MAX_TOTAL_PLAYERS, share_text()])
	peer_ready.emit()
	_lobby_updated()


func _on_peer_disconnected(id: int) -> void:
	_unverified.erase(id)
	if not _lobby.has(id):
		return  ## never seated (turned away or still unverified)
	var gone_name := str((_lobby[id] as Dictionary).get("name", "The other player"))
	connected_peer_ids.erase(id)
	ready_peer_ids.erase(id)
	guest_decks.erase(id)
	_lobby.erase(id)
	_set_status("A player left room %s (%d/%d).\n%s" % [code, player_count(), MAX_TOTAL_PLAYERS, share_text()])
	_lobby_updated()
	peer_left.emit(gone_name)


func _on_connected_ok() -> void:
	announce_version.rpc_id(1, PROTOCOL_VERSION)
	if not connected_peer_ids.has(1):
		connected_peer_ids.append(1)
	_set_status("Joined room %s." % code)
	peer_ready.emit()
	lobby_changed.emit()


func _on_connection_failed() -> void:
	_set_status("Join failed. Check the code or address, that the host is online with a room open, and that the table is not already full.")


func _on_server_gone() -> void:
	var host_name := "The host"
	for r in roster:
		if int((r as Dictionary).get("id", 0)) == 1:
			host_name = str((r as Dictionary).get("name", "The host"))
	_set_status("Host disconnected.")
	connected_peer_ids.clear()
	ready_peer_ids.clear()
	lobby_changed.emit()
	peer_left.emit(host_name)


func _set_status(text: String) -> void:
	last_status = text
	status_changed.emit(text)


@rpc("any_peer", "reliable")
func receive_action(kind: String, payload: Dictionary) -> void:
	if role != "host":
		return
	# Only the first guest occupies an active seat until #19 adds
	# real per-seat routing for 3+ networked players; ignore actions
	# from anyone else so a spectating guest can't drive seat 1.
	if connected_peer_ids.is_empty() or multiplayer.get_remote_sender_id() != connected_peer_ids[0]:
		return
	var table := get_tree().get_first_node_in_group("aetherfold_table")
	if table != null and table.has_method("apply_net_action"):
		table.apply_net_action(kind, payload, 1)


@rpc("authority", "reliable")
func receive_view(data: Dictionary) -> void:
	if role != "client":
		return
	var v: TableView = TableView.from_plain(data)
	var tmp: Dictionary = v.you
	v.you = v.rival
	v.rival = tmp
	var kept_tmp := v.you_kept
	v.you_kept = v.rival_kept
	v.rival_kept = kept_tmp
	var prompt_tmp := v.you_prompt
	v.you_prompt = v.rival_prompt
	v.rival_prompt = prompt_tmp
	var blocks_tmp := v.blocks_for_you
	v.blocks_for_you = v.blocks_for_rival
	v.blocks_for_rival = blocks_tmp
	var draw_tmp := v.draw_waiting_you
	v.draw_waiting_you = v.draw_waiting_rival
	v.draw_waiting_rival = draw_tmp
	var putback_tmp := v.putback_you
	v.putback_you = v.putback_rival
	v.putback_rival = putback_tmp
	v.first_is_you = not v.first_is_you
	v.caller_is_you = not v.caller_is_you
	v.active_is_you = not v.active_is_you
	v.your_priority = not v.your_priority
	last_view = v
	view_received.emit()


## Sent by the host to every guest when the countdown ends; the host runs the same setup for itself in _start_now().
@rpc("authority", "reliable")
func begin_match(host_name: String, guest_name: String) -> void:
	var app := get_node_or_null("/root/AppState")
	if app != null:
		app.mp_role = "client"
		app.mp_code = code
		app.you_seat = 1
		app.skip_ai = true
		app.player_name = guest_name
		app.rival_name = host_name
	match_begin.emit()


func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for addr in IP.get_local_addresses():
		var s := str(addr)
		if s.find(":") >= 0:
			continue
		if s.begins_with("127."):
			continue
		out.append(s)
	return out


# --- Chat ----------------------------------------------------------------------------------------------------
## Text chat during the lobby and the match. Guests send to the host, which names the sender and relays to everyone.

func send_chat(text: String) -> void:
	var t := text.strip_edges().substr(0, 200)
	if t == "" or role == "":
		return
	if role == "host":
		_broadcast_chat(1, t)
	else:
		chat_to_host.rpc_id(1, t)


@rpc("any_peer", "reliable")
func chat_to_host(text: String) -> void:
	if role != "host":
		return
	var t := text.strip_edges().substr(0, 200)
	if t != "":
		_broadcast_chat(multiplayer.get_remote_sender_id(), t)


func _broadcast_chat(id: int, text: String) -> void:
	var who := str((_lobby.get(id, {}) as Dictionary).get("name", "Player"))
	for pid in connected_peer_ids:
		receive_chat.rpc_id(pid, who, text, id)
	chat_received.emit(who, text, id == 1)


@rpc("authority", "reliable")
func receive_chat(sender: String, text: String, id: int) -> void:
	if role != "client":
		return
	chat_received.emit(sender, text, id == my_id())


## Host -> the guest sitting in `seat`: a short message, e.g. why their action was refused.
func send_notice(seat: int, text: String) -> void:
	if role != "host" or seat != 1 or connected_peer_ids.is_empty():
		return
	receive_notice.rpc_id(connected_peer_ids[0], text)


@rpc("authority", "reliable")
func receive_notice(text: String) -> void:
	if role == "client":
		notice_received.emit(text)


## Host -> the guest in `seat`: the ways to play a card ({label, detail} each); the guest answers with menu_pick.
func send_menu(seat: int, object_id: int, title: String, entries: Array) -> void:
	if role != "host" or seat != 1 or connected_peer_ids.is_empty():
		return
	receive_menu.rpc_id(connected_peer_ids[0], object_id, title, entries)


@rpc("authority", "reliable")
func receive_menu(object_id: int, title: String, entries: Array) -> void:
	if role == "client":
		menu_received.emit(object_id, title, entries)
