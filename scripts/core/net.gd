extends Node
## Networked versus mode (remake addition).
##
## Host-authoritative: the host runs the whole simulation (MasterController) as Player1 and the
## joining player controls Player2. The client only renders: it receives the map once, then
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
signal command_received(cmd: Array)
signal game_over_received(won: bool)
signal remote_left

const PORT := 7777
const BEACON_PORT := 7779      # clients listen here for host beacons
const QUERY_PORT := 7778       # hosts listen here for client queries
const PROTOCOL := 1
const MAGIC := "lazerbait-vs"
const SNAPSHOT_RATE := 20.0
const HOST_TIMEOUT := 4.0

enum Role { OFFLINE, HOST, CLIENT }

## Settings fields the host decides for both players.
const SETTINGS_KEYS := ["ship_translational_speed", "ship_rotational_speed", "number_of_players",
	"number_of_ships", "game_speed", "ai_diff", "planet_count", "min_x", "max_x", "min_z", "max_z"]

var role := Role.OFFLINE
var in_match := false
var remote_id := 0
var remote_color := Color(1, 0, 0, 1) / 1.5
var remote_name := ""
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
	var err := _peer.create_server(port, 1)
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
	var ips := local_addresses()
	_set_status("Hosting on %s - waiting for an opponent..." % (ips[0] if ips.size() > 0 else "this machine"))
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
	remote_id = 0
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
			found_hosts[key] = {"name": str(b.get("name", ip)), "ip": ip, "port": port, "seen": Time.get_ticks_msec()}
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
	return JSON.stringify({"magic": MAGIC, "protocol": PROTOCOL, "name": player_name(), "port": PORT}).to_utf8_buffer()


# ------------------------------------------------------------------ connection events

func _on_peer_connected(id: int) -> void:
	if role != Role.HOST:
		return
	if remote_id != 0 or in_match:
		_peer.disconnect_peer(id)
		return
	remote_id = id
	_set_status("Opponent connecting...")


func _on_peer_disconnected(id: int) -> void:
	if role != Role.HOST or id != remote_id:
		return
	remote_id = 0
	print("[Net] opponent disconnected")
	if in_match:
		remote_left.emit()
	else:
		var ips := local_addresses()
		_set_status("Opponent left. Hosting on %s - waiting..." % (ips[0] if ips.size() > 0 else "this machine"))


func _on_connected() -> void:
	remote_id = 1
	_set_status("Connected - waiting for the host...")
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
	remote_id = 0
	print("[Net] disconnected from host")
	if was_in_match:
		in_match = false
		remote_left.emit()
	else:
		_set_status("Disconnected from host")


# ------------------------------------------------------------------ lobby RPCs

@rpc("any_peer", "call_remote", "reliable")
func _hello(protocol: int, color: Color, pname: String) -> void:
	if role != Role.HOST or multiplayer.get_remote_sender_id() != remote_id:
		return
	if protocol != PROTOCOL:
		_reject.rpc_id(remote_id, "Version mismatch (host %d, you %d)" % [PROTOCOL, protocol])
		_peer.disconnect_peer(remote_id, false)
		return
	remote_color = color
	remote_name = pname
	_set_status("%s joined - starting!" % pname)
	match_starting.emit()


@rpc("authority", "call_remote", "reliable")
func _reject(reason: String) -> void:
	_set_status(reason)


## Host: called by the menu after it applied its settings, right before loading the game.
func begin_match() -> void:
	if role != Role.HOST or remote_id == 0:
		return
	in_match = true
	var cfg := {}
	for k in SETTINGS_KEYS:
		cfg[k] = Settings.get(k)
	_start.rpc_id(remote_id, cfg)


@rpc("authority", "call_remote", "reliable")
func _start(cfg: Dictionary) -> void:
	if role != Role.CLIENT:
		return
	for k in SETTINGS_KEYS:
		if cfg.has(k):
			Settings.set(k, cfg[k])
	in_match = true
	pending_map = {}
	_set_status("Starting...")
	match_starting.emit()


# ------------------------------------------------------------------ game RPCs

func send_map(data: Dictionary) -> void:
	if role == Role.HOST and remote_id != 0:
		_map.rpc_id(remote_id, data)


@rpc("authority", "call_remote", "reliable")
func _map(data: Dictionary) -> void:
	pending_map = data
	map_received.emit(data)


func send_snapshot(data: PackedByteArray) -> void:
	if role == Role.HOST and remote_id != 0:
		_snapshot.rpc_id(remote_id, data)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _snapshot(data: PackedByteArray) -> void:
	snapshot_received.emit(data)


## Client -> host: [seq, kind, args...]
func send_command(cmd: Array) -> void:
	if role == Role.CLIENT:
		_command.rpc_id(1, cmd)


@rpc("any_peer", "call_remote", "reliable")
func _command(cmd: Array) -> void:
	if role != Role.HOST or multiplayer.get_remote_sender_id() != remote_id:
		return
	command_received.emit(cmd)


func send_game_over(won: bool) -> void:
	if role == Role.HOST and remote_id != 0:
		_game_over.rpc_id(remote_id, won)


@rpc("authority", "call_remote", "reliable")
func _game_over(won: bool) -> void:
	game_over_received.emit(won)


## Leaving the match (back to the menu) ends the session for both players.
func leave_match() -> void:
	close()
