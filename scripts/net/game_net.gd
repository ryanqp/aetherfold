extends Node

signal status_changed(text: String)
signal peer_ready
signal view_received
signal match_begin

const GAME_PORT := 27777
const BEACON_PORT := 27778
const BEACON_PREFIX := "AETHERFOLD|"

var peer: ENetMultiplayerPeer
var udp: PacketPeerUDP
var code: String = ""
var role: String = ""
var last_status: String = "Offline"
var connected_peer_id: int = 0
var last_view = null
var _beacon_acc := 0.0
var _listen_ip: String = ""
var remote_deck_id: String = ""
var remote_name: String = ""


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
	var err := peer.create_server(GAME_PORT, 1)
	if err != OK:
		_set_status("Could not host on port %d." % GAME_PORT)
		return ""
	multiplayer.multiplayer_peer = peer
	role = "host"
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_start_beacon()
	_set_status("Room %s — waiting for a player…" % code)
	return code


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
	connected_peer_id = 0
	last_view = null
	_set_status("Offline")


func is_connected_peer() -> bool:
	return connected_peer_id != 0


func send_action(kind: String, payload: Dictionary = {}) -> void:
	if role != "client":
		return
	receive_action.rpc_id(1, kind, payload)


func broadcast_view(view) -> void:
	if role != "host" or connected_peer_id == 0:
		return
	var plain := {}
	if view != null and view.has_method("to_plain_for_remote"):
		plain = view.to_plain_for_remote()
	receive_view.rpc_id(connected_peer_id, plain)


@rpc("any_peer", "reliable")
func announce_deck(deck_id: String) -> void:
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


func _connect_to(ip: String) -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, GAME_PORT)
	if err != OK:
		_set_status("Could not connect to %s." % ip)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	_set_status("Connecting to %s…" % ip)


func _on_peer_connected(id: int) -> void:
	connected_peer_id = id
	_set_status("Player joined room %s." % code)
	peer_ready.emit()


func _on_peer_disconnected(_id: int) -> void:
	connected_peer_id = 0
	_set_status("Player left.")


func _on_connected_ok() -> void:
	connected_peer_id = 1
	_set_status("Joined room %s." % code)
	peer_ready.emit()


func _on_connection_failed() -> void:
	_set_status("Join failed. Check the code / IP and that the host is online.")


func _on_server_gone() -> void:
	_set_status("Host disconnected.")
	connected_peer_id = 0


func _set_status(text: String) -> void:
	last_status = text
	status_changed.emit(text)


@rpc("any_peer", "reliable")
func receive_action(kind: String, payload: Dictionary) -> void:
	if role != "host":
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
