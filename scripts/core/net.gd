extends Node
## Networked versus mode (remake addition).
##
## Host-authoritative: the host runs the whole simulation (MasterController) as Player1 and
## up to seven joining players control Player2, Player3, ... in the order they joined; the host
## starts the match from the menu's Start planet. Clients only render: each receives the map once, then
## ~20 snapshots a second (ships, planet owners, countdowns, links, ship counts) and sends its
## commands (send ships / link / unlink / pause) back to the host, which applies them exactly
## like a local click.
##
## Transport: ENet (UDP) on PORT. Games on the local network are found automatically: the host
## broadcasts a beacon and also answers broadcast queries from clients (either direction is
## enough, which helps on devices that filter incoming broadcasts, e.g. Quest).
## Command line (after `--`): `--host` starts hosting, `--join=ADDRESS[:PORT]` joins.

signal status_changed(text: String)
signal hosts_changed
signal match_starting          # both sides: switch to the game level now
signal map_received(data: Dictionary)
signal snapshot_received(data: PackedByteArray)
signal command_received(player: String, cmd: Array)
signal game_over_received(won: bool)
signal lobby_changed
signal notice(text: String)        # in-match message (someone left)
signal remote_left(player: String) # host: a client left; client: the host left ("Player1")

const PORT := 7777
const BEACON_PORT := 7779      # clients listen here for host beacons
const QUERY_PORT := 7778       # hosts listen here for client queries
const PROTOCOL := 2
const MAX_PLAYERS := 8
const MAGIC := "lazerbait-vs"
const SNAPSHOT_RATE := 20.0
const HOST_TIMEOUT := 4.0

enum Role { OFFLINE, HOST, CLIENT }

## Settings fields the host decides for every player.
const SETTINGS_KEYS := ["ship_translational_speed", "ship_rotational_speed", "number_of_players",
	"number_of_ships", "game_speed", "ai_diff", "planet_count", "min_x", "max_x", "min_z", "max_z"]

var role := Role.OFFLINE
var in_match := false
var local_player := "Player1"
## host: peer id -> {name, color, ready (said hello), player (assigned at match start)}
## client: the lobby as reported by the host, peer id -> {name}
var remotes := {}
var _join_order: Array = []     # host: peer ids in the order they connected
var status := ""
var pending_map := {}           # client: map that arrived before the game level was ready
var found_hosts := {}           # "ip:port" -> {name, ip, port, seen}

var _peer: ENetMultiplayerPeer
var _udp: PacketPeerUDP
var _searching := false
var _beacon_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _exit_tree() -> void:
	close()


func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


func versus() -> bool:
	return in_match and role != Role.OFFLINE


func player_name() -> String:
	var n := OS.get_environment("USER")
	if n.is_empty():
		n = OS.get_environment("USERNAME")
	if n.is_empty():
		n = OS.get_model_name()
	return n


func _set_status(t: String) -> void:
	status = t
	status_changed.emit(t)


# ------------------------------------------------------------------ hosting / joining

func host(port := PORT) -> bool:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		_peer = null
		_set_status("Could not host on port %d (in use?)" % port)
		return false
	_peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = _peer
	role = Role.HOST
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	if _udp.bind(QUERY_PORT) != OK:
		push_warning("[Net] discovery query port %d busy; relying on beacons" % QUERY_PORT)
	_beacon_timer = 0.0
	_lobby_status()
	return true


func join(address: String, port := PORT) -> void:
	close()
	var a := address.strip_edges()
	if a.contains(":") and a.count(":") == 1:
		port = int(a.get_slice(":", 1))
		a = a.get_slice(":", 0)
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(a, port)
	if err != OK:
		_peer = null
		_set_status("Could not connect to %s" % a)
		return
	_peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = _peer
	role = Role.CLIENT
	_set_status("Connecting to %s..." % a)


## Look for games on the local network (results in `found_hosts`, signal `hosts_changed`).
func start_search() -> void:
	if role != Role.OFFLINE:
		close()
	_searching = true
	found_hosts.clear()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	if _udp.bind(BEACON_PORT) != OK:
		push_warning("[Net] beacon port %d busy" % BEACON_PORT)
	_beacon_timer = 0.0
	_set_status("Searching for games on your network...")
	hosts_changed.emit()


func stop_search() -> void:
	_searching = false
	if role == Role.OFFLINE and _udp:
		_udp.close()
		_udp = null


func close() -> void:
	_searching = false
	if _udp:
		_udp.close()
		_udp = null
	if _peer:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	role = Role.OFFLINE
	in_match = false
	local_player = "Player1"
	remotes.clear()
	_join_order.clear()
	pending_map = {}
	found_hosts.clear()
	_set_status("")


static func local_addresses() -> Array:
	var out := []
	for ip in IP.get_local_addresses():
		if ip.contains(":") or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue
		out.append(ip)
	out.sort_custom(func(a, b): return _ip_rank(a) < _ip_rank(b))
	return out


static func _ip_rank(ip: String) -> int:
	if ip.begins_with("192.168."):
		return 0
	if ip.begins_with("10."):
		return 1
	if ip.begins_with("172."):
		return 2
	return 3


# ------------------------------------------------------------------ discovery

func _process(delta: float) -> void:
	if _udp == null:
		return
	_beacon_timer -= delta
	if role == Role.HOST and not in_match:
		while _udp.get_available_packet_count() > 0:
			var pkt := _udp.get_packet()
			var ip := _udp.get_packet_ip()
			var port := _udp.get_packet_port()
			var q: Variant = JSON.parse_string(pkt.get_string_from_utf8())
			if typeof(q) == TYPE_DICTIONARY and q.get("magic") == MAGIC and q.get("query", false):
				_udp.set_dest_address(ip, port)
				_udp.put_packet(_beacon())
		if _beacon_timer <= 0.0:
			_beacon_timer = 1.0
			_udp.set_dest_address("255.255.255.255", BEACON_PORT)
			_udp.put_packet(_beacon())
	elif _searching:
		var changed := false
		while _udp.get_available_packet_count() > 0:
			var pkt := _udp.get_packet()
			var ip := _udp.get_packet_ip()
			var b: Variant = JSON.parse_string(pkt.get_string_from_utf8())
			if typeof(b) != TYPE_DICTIONARY or b.get("magic") != MAGIC or b.get("query", false):
				continue
			if int(b.get("protocol", 0)) != PROTOCOL:
				continue
			var port := int(b.get("port", PORT))
			var key := "%s:%d" % [ip, port]
			if not found_hosts.has(key):
				changed = true
			var entry := {"name": str(b.get("name", ip)), "ip": ip, "port": port, "players": int(b.get("players", 1)), "seen": Time.get_ticks_msec()}
			if found_hosts.has(key) and found_hosts[key]["players"] != entry["players"]:
				changed = true
			found_hosts[key] = entry
		var now := Time.get_ticks_msec()
		for k in found_hosts.keys():
			if now - int(found_hosts[k]["seen"]) > HOST_TIMEOUT * 1000.0:
				found_hosts.erase(k)
				changed = true
		if _beacon_timer <= 0.0:
			_beacon_timer = 1.0
			var q := JSON.stringify({"magic": MAGIC, "query": true}).to_utf8_buffer()
			for dest in ["255.255.255.255", "127.0.0.1"]:
				_udp.set_dest_address(dest, QUERY_PORT)
				_udp.put_packet(q)
		if changed:
			if found_hosts.is_empty():
				_set_status("Searching for games on your network...")
			else:
				_set_status("Found %d game%s" % [found_hosts.size(), "" if found_hosts.size() == 1 else "s"])
			hosts_changed.emit()


func _beacon() -> PackedByteArray:
	return JSON.stringify({"magic": MAGIC, "protocol": PROTOCOL, "name": player_name(), "port": PORT,
		"players": 1 + ready_count()}).to_utf8_buffer()


# ------------------------------------------------------------------ connection events

## Host: joined players that completed the handshake.
func ready_count() -> int:
	var n := 0
	for id in remotes.keys():
		if remotes[id]["ready"]:
			n += 1
	return n


## Host: the player name controlled by peer `id` ("" if none).
func player_of(id: int) -> String:
	return remotes[id].get("player", "") if remotes.has(id) else ""


## Host: human players other than Player1 -> {name, color}, in slot order.
func remote_players() -> Dictionary:
	var out := {}
	for id in _join_order:
		var r: Dictionary = remotes[id]
		if r.get("player", "") != "":
			out[r["player"]] = r
	return out


func _lobby_status() -> void:
	var ips := local_addresses()
	var where: String = ips[0] if ips.size() > 0 else "this machine"
	var names := [player_name() + " (you)"]
	for id in _join_order:
		if remotes[id]["ready"]:
			names.append(remotes[id]["name"])
	if names.size() == 1:
		_set_status("Hosting on %s - waiting for players..." % where)
	else:
		_set_status("Hosting on %s - %d players: %s\nClick Start to play" % [where, names.size(), ", ".join(names)])
	lobby_changed.emit()
	if role == Role.HOST and not in_match:
		_lobby.rpc(names)


func _on_peer_connected(id: int) -> void:
	if role != Role.HOST:
		return
	if in_match:
		_peer.disconnect_peer(id)
		return
	remotes[id] = {"name": "Player", "color": Color(1, 0, 0, 1) / 1.5, "ready": false}
	_join_order.append(id)


func _on_peer_disconnected(id: int) -> void:
	if role != Role.HOST or not remotes.has(id):
		return
	var r: Dictionary = remotes[id]
	remotes.erase(id)
	_join_order.erase(id)
	print("[Net] %s disconnected" % r["name"])
	if in_match:
		if r.get("player", "") != "":
			var msg := "%s left - the A.I. takes over" % r["name"]
			_notice.rpc(msg)
			remote_left.emit(r["player"])
			notice.emit(msg)
	else:
		_lobby_status()


func _on_connected() -> void:
	_set_status("Connected - waiting for the host to start...")
	_hello.rpc_id(1, PROTOCOL, MenuLevel.MENU_COLORS[Settings.color_settings_count], player_name())


func _on_connection_failed() -> void:
	_peer = null
	multiplayer.multiplayer_peer = null
	role = Role.OFFLINE
	_set_status("Connection failed")


func _on_server_disconnected() -> void:
	var was_in_match := in_match
	_peer = null
	multiplayer.multiplayer_peer = null
	role = Role.OFFLINE
	remotes.clear()
	print("[Net] disconnected from host")
	if was_in_match:
		in_match = false
		remote_left.emit("Player1")
	else:
		_set_status("Disconnected from host")


# ------------------------------------------------------------------ lobby RPCs

@rpc("any_peer", "call_remote", "reliable")
func _hello(protocol: int, color: Color, pname: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if role != Role.HOST or not remotes.has(id):
		return
	if protocol != PROTOCOL:
		_reject.rpc_id(id, "Version mismatch (host %d, you %d)" % [PROTOCOL, protocol])
		_peer.disconnect_peer(id, false)
		return
	remotes[id]["color"] = color
	remotes[id]["name"] = pname
	remotes[id]["ready"] = true
	_lobby_status()


@rpc("authority", "call_remote", "reliable")
func _reject(reason: String) -> void:
	_set_status(reason)


@rpc("authority", "call_remote", "reliable")
func _lobby(names: Array) -> void:
	if role == Role.CLIENT and not in_match:
		_set_status("Connected - %d players: %s\nWaiting for the host to start..." % [names.size(), ", ".join(names)])


## Host: called by the menu after it applied its settings, right before loading the game.
## Assigns Player2, Player3, ... in join order and tells every client to start.
func begin_match() -> void:
	if role != Role.HOST or ready_count() == 0:
		return
	in_match = true
	var cfg := {}
	for k in SETTINGS_KEYS:
		cfg[k] = Settings.get(k)
	var slot := 2
	for id in _join_order.duplicate():
		if not remotes[id]["ready"]:
			_peer.disconnect_peer(id) # still handshaking: too late for this match
			continue
		remotes[id]["player"] = "Player%d" % slot
		slot += 1
	for id in _join_order:
		if remotes.has(id) and remotes[id].get("player", "") != "":
			var c := cfg.duplicate()
			c["player"] = remotes[id]["player"]
			_start.rpc_id(id, c)


@rpc("authority", "call_remote", "reliable")
func _start(cfg: Dictionary) -> void:
	if role != Role.CLIENT:
		return
	for k in SETTINGS_KEYS:
		if cfg.has(k):
			Settings.set(k, cfg[k])
	local_player = str(cfg.get("player", "Player2"))
	in_match = true
	pending_map = {}
	_set_status("Starting...")
	match_starting.emit()


@rpc("authority", "call_remote", "reliable")
func _notice(text: String) -> void:
	notice.emit(text)


# ------------------------------------------------------------------ game RPCs

func _match_peers() -> Array:
	var out := []
	for id in _join_order:
		if remotes.has(id) and remotes[id].get("player", "") != "":
			out.append(id)
	return out


func has_clients() -> bool:
	return role == Role.HOST and not _match_peers().is_empty()


func send_map(data: Dictionary) -> void:
	for id in _match_peers():
		_map.rpc_id(id, data)


@rpc("authority", "call_remote", "reliable")
func _map(data: Dictionary) -> void:
	pending_map = data
	map_received.emit(data)


## Host: `make(player)` builds the snapshot for one client (they differ only in the header).
func send_snapshots(make: Callable) -> void:
	for id in _match_peers():
		_snapshot.rpc_id(id, make.call(remotes[id]["player"]))


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _snapshot(data: PackedByteArray) -> void:
	snapshot_received.emit(data)


## Client -> host: [seq, kind, args...]
func send_command(cmd: Array) -> void:
	if role == Role.CLIENT:
		_command.rpc_id(1, cmd)


@rpc("any_peer", "call_remote", "reliable")
func _command(cmd: Array) -> void:
	var p := player_of(multiplayer.get_remote_sender_id())
	if role != Role.HOST or p == "":
		return
	command_received.emit(p, cmd)


func send_game_over(player: String, won: bool) -> void:
	for id in _match_peers():
		if remotes[id]["player"] == player:
			_game_over.rpc_id(id, won)


@rpc("authority", "call_remote", "reliable")
func _game_over(won: bool) -> void:
	game_over_received.emit(won)


## Leaving the match (back to the menu) ends the session (for everyone, when the host leaves).
func leave_match() -> void:
	close()
