extends Node

signal status_changed(text: String)
signal peer_ready
signal lobby_changed
signal view_received
signal match_begin
signal address_changed

const GAME_PORT := 27777
const BEACON_PORT := 27778
const BEACON_PREFIX := "AETHERFOLD|"
const MAX_TOTAL_PLAYERS := 6

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
		ok = u.add_port_mapping(GAME_PORT, GAME_PORT, "Aetherfold", "UDP", 3600) == UPNP.UPNP_RESULT_SUCCESS
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


func set_ready(is_ready: bool) -> void:
	if role != "client":
		return
	announce_ready.rpc_id(1, is_ready)


func all_guests_ready() -> bool:
	if connected_peer_ids.is_empty():
		return false
	for pid in connected_peer_ids:
		if not ready_peer_ids.has(pid):
			return false
	return true


func ready_count() -> int:
	return ready_peer_ids.size()


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
	# Every connected guest currently gets the same 2-seat (host vs.
	# seat 1) view until #19/#20 add real per-seat routing for 3+
	# networked players; guests past the first are spectating seat 1.
	for pid in connected_peer_ids:
		receive_view.rpc_id(pid, plain)


@rpc("any_peer", "reliable")
func announce_ready(is_ready: bool) -> void:
	if role != "host":
		return
	var sender := multiplayer.get_remote_sender_id()
	if is_ready:
		if not ready_peer_ids.has(sender):
			ready_peer_ids.append(sender)
	else:
		ready_peer_ids.erase(sender)
	lobby_changed.emit()


@rpc("any_peer", "reliable")
func announce_deck(deck_id: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	guest_decks[sender] = deck_id
	if remote_deck_id == "":
		remote_deck_id = deck_id


func start_match_rpc(player_deck: String, rival_deck: String) -> void:
	if role != "host":
		return
	begin_match.rpc(player_deck, rival_deck)


func _process(delta: float) -> void:
	if role == "host" and udp != null:
		_beacon_acc += delta
		if _beacon_acc >= 1.0:
			_beacon_acc = 0.0
			_send_beacon()
	if role == "client" and udp != null and peer == null:
		_poll_beacon()


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


func _on_peer_connected(id: int) -> void:
	if not connected_peer_ids.has(id):
		connected_peer_ids.append(id)
	ready_peer_ids.erase(id)
	_set_status("Room %s — %d/%d players joined.\n%s" % [code, player_count(), MAX_TOTAL_PLAYERS, share_text()])
	peer_ready.emit()
	lobby_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	connected_peer_ids.erase(id)
	ready_peer_ids.erase(id)
	guest_decks.erase(id)
	_set_status("A player left room %s (%d/%d).\n%s" % [code, player_count(), MAX_TOTAL_PLAYERS, share_text()])
	lobby_changed.emit()


func _on_connected_ok() -> void:
	if not connected_peer_ids.has(1):
		connected_peer_ids.append(1)
	_set_status("Joined room %s." % code)
	peer_ready.emit()
	lobby_changed.emit()


func _on_connection_failed() -> void:
	_set_status("Join failed. Check the code / IP and that the host is online.")


func _on_server_gone() -> void:
	_set_status("Host disconnected.")
	connected_peer_ids.clear()
	ready_peer_ids.clear()
	lobby_changed.emit()


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
	v.active_is_you = not v.active_is_you
	v.your_priority = not v.your_priority
	last_view = v
	view_received.emit()


@rpc("authority", "reliable")
func begin_match(host_deck: String, guest_deck: String) -> void:
	var app := get_node_or_null("/root/AppState")
	if app != null:
		if role == "host":
			app.player_deck_id = host_deck
			app.rival_deck_id = guest_deck
			app.you_seat = 0
		else:
			app.player_deck_id = guest_deck
			app.rival_deck_id = host_deck
			app.you_seat = 1
		app.mp_role = role
		app.mp_code = code
		app.skip_ai = true
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
