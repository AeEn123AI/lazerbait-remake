class_name MasterController
extends Node3D
## Port of MasterController.cs (+ Env.cs). Map generation, ship spawning, planet ownership,
## end-game detection. Also hosts the emulated physics step (trigger detection between ships
## and planets) that Unity's physics engine provided.

const FIXED_TIMESTEP := 0.08  # TimeManager "Fixed Timestep" of the original project
const SHIP_SCALE := 2.5       # Ship prefab localScale
const VOLUME := 0.1
const POS_SCALE := 256.0       # versus snapshots: positions as int16 / 256 (+-128 units)
const INTERP_DELAY := 0.12     # versus client: render this far behind the newest snapshot

## Emitted once the planets exist (immediately offline / on the host, when the map arrives
## on a versus client).
signal map_ready

# ------------------------------------------------------------------ Env.cs
class Env:
	var ai_diff := 0
	var player_names := ["neutral", "Player1", "Player2", "Player3", "Player4", "Player5", "Player6", "Player7", "Player8"]
	var player_colors := {
		"neutral": Color(1, 1, 1, 1),
		"Player1": Color(0, 1, 1, 1),
		"Player2": Color(1, 0, 0, 1) / 1.5,
		"Player3": Color(0.4, 0.4, 0.4, 1),
		"Player4": Color(1, 0.92156863, 0.015686275, 1), # Unity Color.yellow
		"Player5": Color(1, 0.5, 0, 1),
		"Player6": Color(1, 0, 1, 1),
		"Player7": Color(0, 1, 0, 1),
		"Player8": Color(0, 0, 1, 1),
	}
	var player_layers := {"neutral": 10, "Player1": 8, "Player2": 9, "Player3": 11, "Player4": 12, "Player5": 13, "Player6": 14, "Player7": 15, "Player8": 16}
	var player_spawn_rates := {"neutral": 3.0, "Player1": 1.0, "Player2": 1.0, "Player3": 1.0, "Player4": 1.0, "Player5": 1.0, "Player6": 1.0, "Player7": 1.0, "Player8": 1.0}
	var planet_ownership_frames := 45
	var planet_count := 40.0
	var number_of_players := 2
	var ship_translational_speed := 4.0
	var ship_rotational_speed := 200.0
	var ship_move_closer := 0
	var game_speed := 1.0
	var base_ship_limit := 100
	var base_planet_health := 85.0
	var limit_weight := 1.0
	var update_ai_this_often := 15.0
	var ai_attack_threshold := 1.2
	var initialized := false
	var min_x := 0.0
	var max_x := 18.0
	var min_y := 2.0
	var max_y := 15.0
	var min_z := 0.0
	var max_z := 18.0

# MasterController.explosions colour -> particleSystems index
var explosion_colors := []

var environment := Env.new()
var player := {"selected_planet": null}
var level # GameLevel
var rig: PlayerRig

var _audio: AudioStreamPlayer
var _game_over := false
var _last_update_frame := 0
var planet_links := {}        # Planet -> Planet
var ship_count := 0
var ship_counts := {}
var ship_limits := {}
var ships: Array = []         # live ships (Unity's shipControllers list)
var _planets_to_change: Array = []
var mini_map: Array = []      # [[Vector3 pos, Color], ...]
var adjacency := {}
var reverse_adjacency := {}
var planets: Array = []
var ais: Array = []
var _physics_accum := 0.0
var _last_fixed_time := 0.0
var _next_ship_id := 0
var explosions: ExplosionPool
var _ship_mm: MultiMeshInstance3D
var _lasers: LaserBatch
var _mm_capacity := 0

# versus mode (see Net). The host simulates everything; the client mirrors snapshots.
var net_role := 0              # Net.Role
var local_player := "Player1"  # the player this machine controls
var human_players := ["Player1"]
var _player_index := {}        # player name -> index in environment.player_names
var _snap_timer := 0.0
var _remote_ack := 0           # host: last command sequence number applied
var _remote_kills := 0         # host: enemy ships destroyed by Player2
var _remote_result := -1       # host: result sent to the client (-1 none, 0 lost, 1 won)
var _client_ships := {}        # client: ship id -> Ship
var _snaps: Array = []         # client: received, not yet applied snapshots
var _cur_snap_t := -1.0
var _latest_t := -1.0
var _render_time := -1.0
var _pending_links := {}       # client: Planet -> command seq whose link change isn't confirmed yet
var _cmd_seq := 0
var _kills_seen := 0


func _make_explosion_colors() -> void:
	explosion_colors = [
		[Color(1, 1, 1, 1), 0],
		[Color(0, 1, 1, 1), 1],
		[Color(1, 0, 0, 1) / 1.5, 2],
		[Color(0.4, 0.4, 0.4, 1), 3],
		[Color(1, 0.92156863, 0.015686275, 1), 4],
		[Color(1, 0.5, 0, 1), 5],
		[Color(1, 0, 1, 1), 6],
		[Color(0, 1, 0, 1), 7],
		[Color(0, 0, 1, 1), 8],
	]


func explosion_index(c: Color) -> int:
	for e in explosion_colors:
		if (e[0] as Color).is_equal_approx(c):
			return e[1]
	return 0


# ------------------------------------------------------------------ Start()
func start_game(p_level, p_rig: PlayerRig) -> void:
	level = p_level
	rig = p_rig
	if Net.in_match:
		net_role = Net.role
		human_players = ["Player1", "Player2"]
		if net_role == Net.Role.CLIENT:
			local_player = "Player2"
	for i in environment.player_names.size():
		_player_index[environment.player_names[i]] = i
	_make_explosion_colors()
	explosions = ExplosionPool.new()
	add_child(explosions)
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	_ship_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = A.mesh("ship")
	_ship_mm.multimesh = mm
	_ship_mm.material_override = A.lambert1(Color.WHITE, true)
	_ship_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ship_mm.extra_cull_margin = 16384.0
	add_child(_ship_mm)
	_lasers = LaserBatch.new()
	add_child(_lasers)

	for i in range(2, 9):
		var ai := AIController.new()
		ai.player_name = "Player%d" % i
		ai.update_ai_this_often = [1.0, 1.1, 1.2, 9.5, 10.0, 10.5, 11.0][i - 2]
		ai.is_ai_enabled = i == 2 and net_role == Net.Role.OFFLINE
		ai.master = self
		ais.append(ai)

	_apply_game_settings()
	_populate_ship_counter()
	if net_role == Net.Role.CLIENT:
		Net.map_received.connect(_client_build_map)
		Net.snapshot_received.connect(_client_on_snapshot)
		Net.game_over_received.connect(func(won: bool): _end_game(won))
		if not Net.pending_map.is_empty():
			_client_build_map(Net.pending_map)
		return
	var radius := _get_range_from_rand(1.0) / 4.0 + float(Settings.planet_count) * 0.25
	var e := environment
	var dictionary = _generate_map_new(e.min_x, e.max_x, e.min_y, e.max_y, e.min_z, e.max_z, radius, e.number_of_players)
	var num := 0
	while dictionary == null and num < 100:
		num += 1
		dictionary = _generate_map_new(e.min_x, e.max_x, e.min_y, e.max_y, e.min_z, e.max_z, radius, e.number_of_players)
	if dictionary == null:
		push_error("Map generation went infinite")
		return
	if net_role == Net.Role.HOST:
		Net.send_map({"map": dictionary, "colors": e.player_colors})
		Net.command_received.connect(_host_on_command)
	_spawn_planets(dictionary)
	_populate_adjacency_matrix()
	_place_rig_at_home(dictionary)
	_update_ship_limits()
	for planet in planets:
		_spawn_ship(planet.player, planet)
		_spawn_ship(planet.player, planet)
		planet.spawn_timer = _spawn_wait(planet)
	_last_fixed_time = GameTime.time
	map_ready.emit()


func _place_rig_at_home(dictionary: Dictionary) -> void:
	var p1: Vector3 = dictionary[local_player][0][0]
	var rp := rig.rig_position()
	rig.set_rig_position(Vector3(p1.x, rp.y, -p1.z))


func local_color() -> Color:
	return environment.player_colors[local_player]


func _spawn_wait(planet: Planet) -> float:
	return environment.player_spawn_rates[planet.player] / (environment.game_speed * 0.33 * 2.0) / planet.scale


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if net_role == Net.Role.CLIENT:
		_client_process()
		return
	if net_role == Net.Role.HOST:
		_host_send_snapshot()
	if GameTime.paused():
		_render_ships()
		return
	_physics_step(GameTime.delta)
	_interpolate_ships()
	_update()
	for ai in ais:
		ai.update()
	_update_spawners(GameTime.delta)
	_render_ships()


func _update() -> void:
	_move_ships()
	if _last_update_frame + environment.planet_ownership_frames < GameTime.frame_count:
		_last_update_frame = GameTime.frame_count
		_update_ship_limits()
		for planet2 in planets:
			var num := 0
			for s in planet2.ships:
				if not s.dead and s.in_orbit:
					num += 1
			var num2 := 0
			for s in planet2.enemy_ships:
				if not s.dead and s.in_orbit:
					num2 += 1
			if num2 <= 2:
				continue
			if num < 3:
				if planet2.last_changed_hands + 2.0 < GameTime.time:
					planet2.last_changed_hands = GameTime.time
					planet2.node.enable_countdown()
			else:
				planet2.node.disable_countdown()
		if net_role == Net.Role.HOST:
			_check_end_versus()
		else:
			var num3 := _check_end_scenario()
			if num3 > 0:
				_end_game(num3 == 1)
		_update_mini_map()
	if _planets_to_change.size() > 0:
		var planet: Planet = _planets_to_change.pop_front()
		_change_planet_hands(planet)


func _update_spawners(dt: float) -> void:
	for planet in planets:
		planet.spawn_timer -= dt
		if planet.spawn_timer <= 0.0:
			_spawn_ship(planet.player, planet)
			planet.spawn_timer += _spawn_wait(planet)
			if planet.spawn_timer < 0.0:
				planet.spawn_timer = _spawn_wait(planet)


func _move_ships() -> void:
	var now := GameTime.realtime()
	# iterate over a snapshot: ships may die (and be removed) during the loop
	var snapshot := ships.duplicate()
	for s in snapshot:
		if not s.dead:
			s.custom_update(now)


# ------------------------------------------------------------------ emulated physics

func _interpolate_ships() -> void:
	var alpha := clampf((GameTime.time - _last_fixed_time) / FIXED_TIMESTEP, 0.0, 1.0)
	for s in ships:
		if s.in_orbit:
			s.pos = s.body_prev.lerp(s.body_cur, alpha)


func _physics_step(dt: float) -> void:
	_physics_accum += dt
	var steps := 0
	while _physics_accum >= FIXED_TIMESTEP and steps < 4 * int(ceil(GameTime.debug_speed)):
		_physics_accum -= FIXED_TIMESTEP
		_last_fixed_time = GameTime.time - _physics_accum
		steps += 1
		_fixed_update()
	if _physics_accum > FIXED_TIMESTEP:
		_physics_accum = 0.0


func _cell_of(p: Vector3, size: float) -> Vector3i:
	return Vector3i(floori(p.x / size), floori(p.y / size), floori(p.z / size))


func _fixed_update() -> void:
	# 1) kinematic bodies move to their MovePosition targets
	for s in ships:
		if s.pending:
			s.body_prev = s.body_cur
			s.body_cur = s.pending_target
			s.pending = false
		else:
			s.body_prev = s.body_cur
		if not s.in_orbit:
			s.body_prev = s.pos
			s.body_cur = s.pos
	# 2) trigger detection
	const SHIP_CELL := 1.5
	const R2 := (Ship.TRIGGER_RADIUS * 2.0) * (Ship.TRIGGER_RADIUS * 2.0)
	var grid := {}
	var active: Array = []
	for s in ships:
		if s.dead or not s.is_initialized:
			continue
		if not s.collider_enabled:
			# a disabled collider silently loses its contacts (no OnTriggerExit in Unity 5.4)
			if not s.overlap_ships.is_empty():
				for o in s.overlap_ships.keys():
					o.overlap_ships.erase(s)
				s.overlap_ships.clear()
			s.overlap_planets.clear()
			continue
		var c := _cell_of(s.body_cur, SHIP_CELL)
		s.cell = c
		if grid.has(c):
			grid[c].append(s)
		else:
			grid[c] = [s]
		active.append(s)
	var enters: Array = []
	var exits: Array = []
	var now_map := {}
	for s in active:
		var now_overlap := {}
		var c: Vector3i = s.cell
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var key := Vector3i(c.x + dx, c.y + dy, c.z + dz)
					if not grid.has(key):
						continue
					for o in grid[key]:
						if o == s or o.player_name == s.player_name:
							continue
						if s.body_cur.distance_squared_to(o.body_cur) < R2:
							now_overlap[o] = true
		for o in now_overlap.keys():
			if not s.overlap_ships.has(o) and s._id_lt(o):
				enters.append([s, o])
		for o in s.overlap_ships.keys():
			if not now_overlap.has(o) and s._id_lt(o):
				exits.append([s, o])
		now_map[s] = now_overlap
	for s in active:
		s.overlap_ships = now_map[s]
	for pr in exits:
		pr[0].on_trigger_exit_ship(pr[1])
		pr[1].on_trigger_exit_ship(pr[0])
	for pr in enters:
		pr[0].on_trigger_enter_ship(pr[1])
		pr[1].on_trigger_enter_ship(pr[0])
	# ship <-> planet
	for s in active:
		if s.dead or not s.collider_enabled:
			continue
		var now_p := {}
		for p in _planets_near(s.body_cur):
			var rr: float = Ship.TRIGGER_RADIUS + 0.6 * p.scale
			if s.body_cur.distance_squared_to(p.position) < rr * rr:
				now_p[p] = true
		var newly := []
		for p in now_p.keys():
			if not s.overlap_planets.has(p):
				newly.append(p)
		s.overlap_planets = now_p
		for p in newly:
			if s.dead or not s.collider_enabled:
				break
			s.on_trigger_enter_planet(p)


var _planet_grid := {}
const PLANET_CELL := 2.0


func _build_planet_grid() -> void:
	_planet_grid.clear()
	for p in planets:
		var c := _cell_of(p.position, PLANET_CELL)
		if _planet_grid.has(c):
			_planet_grid[c].append(p)
		else:
			_planet_grid[c] = [p]


func _planets_near(pos: Vector3) -> Array:
	var out := []
	var c := _cell_of(pos, PLANET_CELL)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				var key := Vector3i(c.x + dx, c.y + dy, c.z + dz)
				if _planet_grid.has(key):
					out.append_array(_planet_grid[key])
	return out


# ------------------------------------------------------------------ rendering

func _render_ships() -> void:
	var mm := _ship_mm.multimesh
	var n := ships.size()
	if n > _mm_capacity:
		_mm_capacity = maxi(256, n * 2)
		mm.instance_count = _mm_capacity
	var buf := PackedFloat32Array()
	buf.resize(_mm_capacity * 16)
	var k := 0
	_lasers.begin()
	for s in ships:
		var b: Basis = s.basis.scaled_local(Vector3.ONE * SHIP_SCALE)
		var o: Vector3 = s.pos
		var c: Color = s.color
		buf[k] = b.x.x; buf[k + 1] = b.y.x; buf[k + 2] = b.z.x; buf[k + 3] = o.x
		buf[k + 4] = b.x.y; buf[k + 5] = b.y.y; buf[k + 6] = b.z.y; buf[k + 7] = o.y
		buf[k + 8] = b.x.z; buf[k + 9] = b.y.z; buf[k + 10] = b.z.z; buf[k + 11] = o.z
		buf[k + 12] = c.r; buf[k + 13] = c.g; buf[k + 14] = c.b; buf[k + 15] = 1.0
		k += 16
		if s.laser_enabled:
			_lasers.add(s.laser_from, s.laser_to, c)
	mm.buffer = buf
	mm.visible_instance_count = n
	_lasers.commit()


func spawn_explosion(index: int, pos: Vector3) -> void:
	explosions.spawn(index, pos)


func destroy_ship(s: Ship) -> void:
	s.dead = true
	for o in s.overlap_ships.keys():
		o.overlap_ships.erase(s)
	s.overlap_ships.clear()
	ships.erase(s)


# ------------------------------------------------------------------ public API (MasterController)

func change_planet_hands_queued(planet: Planet) -> void:
	if net_role == Net.Role.CLIENT:
		return # the host decides; the new owner arrives in a snapshot
	_planets_to_change.append(planet)


func establish_link(source: Planet, destination: Planet) -> void:
	if planet_links.has(source):
		# Dictionary.Add would throw on a duplicate key in the original.
		return
	planet_links[source] = destination


func delete_link(source: Planet) -> void:
	planet_links.erase(source)


func get_planet_assignment(to_check: Planet) -> Planet:
	return planet_links.get(to_check, to_check)


func get_planets() -> Array:
	return planets


func send_wave(source: Planet, dest: Planet, percent := 1.0) -> void:
	var num := float(source.ships.size()) * percent
	if num < 3.0 and source.ships.size() >= 3:
		num = 3.0
	var lst := []
	for s in source.ships:
		if not s.dead and s.in_orbit:
			lst.append(s)
	for item in lst:
		var check := num
		num -= 1.0
		if check < 0.0:
			break
		item.change_planet(dest)
	if not (source.player != dest.player):
		return
	for s in dest.ships.duplicate():
		if not s.dead:
			s.defend()


func get_spawn_rates() -> Dictionary:
	return environment.player_spawn_rates


func get_ship_count() -> int:
	return ship_count


func decrement_ship_count(p: String) -> void:
	ship_count -= 1
	ship_counts[p] = ship_counts[p] - 1


func get_mini_map() -> Array:
	return mini_map


func get_player_ship_count(p: String) -> int:
	return ship_counts[p]


func get_player_ship_limit(p: String) -> int:
	return ship_limits.get(p, 0)


func add_to_ship_counter(n: int) -> void:
	Stats.add_to_counter("ShipKills", n)


## A ship of `victim` was destroyed, last hit by `killer`.
func count_kill(victim: String, killer: String) -> void:
	if victim != local_player and killer == local_player:
		add_to_ship_counter(1)
	elif net_role == Net.Role.HOST and victim != "Player2" and killer == "Player2":
		_remote_kills += 1


func get_planets_in_range(planet: Planet) -> Array:
	return adjacency[planet].duplicate()


func get_planets_in_reverse_range(planet: Planet) -> Array:
	return reverse_adjacency[planet].duplicate()


func _spawn_ship(player_name: String, planet: Planet) -> void:
	if planet.player != player_name or ship_counts[player_name] > ship_limits.get(player_name, 0):
		return
	ship_counts[player_name] += 1
	var planet2 := planet
	if planet_links.has(planet):
		planet2 = planet_links[planet]
	var s := Ship.new(self, planet2, planet.player)
	s.translational_speed = environment.ship_translational_speed
	s.rotational_speed = environment.ship_rotational_speed
	s.current_planet = planet2
	s.set_transform_position(U.on_unit_sphere() * 1.5 + planet.position)
	s.color = planet.color
	s.impact_index = explosion_index(planet.color)
	s.player_name = planet.player
	s.id = _next_ship_id
	_next_ship_id += 1
	if planet2.player != player_name:
		planet2.enemy_ships.append(s)
	else:
		planet2.ships.append(s)
	ship_count += 1
	s.start()
	ships.append(s)


# ------------------------------------------------------------------ settings

func _apply_game_settings() -> void:
	var e := environment
	if Settings.number_of_players > 0:
		e.number_of_players = Settings.number_of_players
		e.ship_translational_speed = Settings.ship_translational_speed
		e.ship_rotational_speed = Settings.ship_rotational_speed
		e.base_ship_limit = Settings.number_of_ships
		e.game_speed = Settings.game_speed
		e.base_planet_health *= Settings.game_speed * 6.0
		for ai in ais:
			var idx := int(String(ai.player_name).substr(6))
			if idx >= 3:
				ai.is_ai_enabled = Settings.number_of_players > idx - 1
		# the AI that owns the chosen colour swaps to cyan
		for key in e.player_colors.keys():
			if U.color_eq(e.player_colors[key], Settings.player_color):
				e.player_colors[key] = Color(0, 1, 1, 1)
				break
		e.player_colors["Player1"] = Settings.player_color
		if net_role == Net.Role.HOST:
			_assign_remote_color(Net.remote_color)
		e.ai_diff = Settings.ai_diff
		if Settings.ai_diff == 0:
			e.update_ai_this_often = 15.0
			e.ai_attack_threshold = 0.8
			for k in e.player_spawn_rates.keys():
				if k != "neutral" and not human_players.has(k):
					e.player_spawn_rates[k] *= 1.5
		elif Settings.ai_diff == 1:
			e.update_ai_this_often = 12.0
			e.ai_attack_threshold = 1.0
		elif Settings.ai_diff == 2:
			e.update_ai_this_often = 2.0
			e.ai_attack_threshold = 1.2
		elif Settings.ai_diff == 3:
			e.update_ai_this_often = 1.0
			e.ai_attack_threshold = 1.2
			for k in e.player_spawn_rates.keys():
				if k != "neutral" and not human_players.has(k):
					e.player_spawn_rates[k] *= 0.5
		var num := Settings.planet_count * 2
		if Settings.number_of_players == 8:
			e.planet_count = 16 + num * 12
		else:
			e.planet_count = 16 + num * 24
		e.min_x = Settings.min_x * 2.0 * float(num + 3)
		e.max_x = Settings.max_x * 2.0 * float(num + 3)
		e.min_z = Settings.min_z * 2.0 * float(num + 3)
		e.max_z = Settings.max_z * 2.0 * float(num + 3)
		e.max_y += num
	if level:
		level.set_player_color_disc(local_color())
	e.initialized = true


## Versus: Player2 gets the joining player's colour, unless the host already uses it.
func _assign_remote_color(want: Color) -> void:
	var cols := environment.player_colors
	if U.color_eq(want, cols["Player1"]) or U.color_eq(want, cols["Player2"]):
		return
	for key in cols.keys():
		if key != "Player1" and key != "Player2" and U.color_eq(cols[key], want):
			cols[key] = cols["Player2"]
			break
	cols["Player2"] = want


# ------------------------------------------------------------------ map generation

func _get_scale_from_random(r: float) -> float:
	return r * 1.2 + 0.2


func _get_range_from_rand(r: float) -> float:
	return 7.0 * _get_scale_from_random(r) + float(Settings.planet_count) * 1.5


## Port of GenerateMapNew (Unity coordinates). Entries are [Vector3, float value].
func _generate_map_new(xmin: float, xmax: float, ymin: float, ymax: float, zmin: float, zmax: float, radius: float, players: int):
	var num := 0
	var y := ymin
	xmin += radius / 2.0
	xmax -= radius / 2.0
	zmin += radius / 2.0
	zmax -= radius / 2.0
	if players < 8:
		var num2 := ymin
		var num3 := ymax + (ymax - ymin)
		ymin += (num3 - num2) / 4.0
		ymax += (num3 - num2) / 4.0
		y = (ymax - ymin) / 2.0 + ymin
	var d := {}
	for key in environment.player_layers.keys():
		d[key] = []
	d["Player1"].append([Vector3(xmin, y, zmin), 1.0])
	d["Player2"].append([Vector3(xmax, y, zmax), 1.0])
	var num4 := 1.0
	var num5 := 0.5
	d["neutral"].append([Vector3(0.0 + radius * num4, y, (zmax - radius) * randf() + radius * num4 * 2.0), randf() * num5 + num5 * 0.5])
	d["neutral"].append([Vector3((xmax - radius) * randf() + radius * num4 * 2.0, y, 0.0 + radius * num4), randf() * num5 + num5 * 0.5])
	if players > 2:
		d["Player3"].append([Vector3(xmax, y, zmin), 1.0])
		d["Player4"].append([Vector3(xmin, y, zmax), 1.0])
	if players == 8:
		d["Player5"].append([Vector3(xmin, ymax * 2.0 - ymin, zmin), 1.0])
		d["Player6"].append([Vector3(xmax, ymax * 2.0 - ymin, zmax), 1.0])
		d["Player7"].append([Vector3(xmax, ymax * 2.0 - ymin, zmin), 1.0])
		d["Player8"].append([Vector3(xmin, ymax * 2.0 - ymin, zmax), 1.0])
		d["neutral"].append([Vector3((xmax / 2.0 - radius) * randf() + radius * num4, ymax - radius * num4, (zmax / 2.0 - radius) * randf() + radius * num4), randf() * num5 + num5 * 0.5])
	var bridges: Array = d["neutral"].duplicate()
	while true:
		var x := randf() * (xmax - radius * 1.0) + radius * 0.5
		var y2 := randf() * (ymax - ymin) + ymin - radius * 0.5
		var z := randf() * (zmax - radius * 1.0) + radius * 0.5
		var test_position := Vector3(x, y2, z)
		var value := randf()
		var test_range := _get_range_from_rand(value)
		var list2: Array = d["Player2"].duplicate()
		list2.append_array(d["neutral"])
		var list3 := []
		for p in list2:
			var dist: float = (p[0] as Vector3).distance_to(test_position)
			if dist < _get_range_from_rand(p[1]) and dist < test_range:
				list3.append(p)
		if list3.size() > 0:
			var too_close := false
			for p in list3:
				if (p[0] as Vector3).distance_to(test_position) < radius * 2.0:
					too_close = true
					break
			if not too_close:
				d["neutral"].append([test_position, value])
				if _bridges_graph_to_home(bridges, d):
					break
		if num == 100:
			num += 1
		num += 1
		if num > 25000:
			return null
	var list4 := []
	for item in d["neutral"]:
		var k: Vector3 = item[0]
		list4.append([Vector3(xmax - (k.x - xmin), k.y, k.z), item[1]])
		list4.append([Vector3(xmax - (k.x - xmin), k.y, zmax - (k.z - zmin)), item[1]])
		list4.append([Vector3(k.x, k.y, zmax - (k.z - zmin)), item[1]])
	d["neutral"].append_array(list4)
	if players == 8:
		list4 = []
		for item2 in d["neutral"]:
			var k2: Vector3 = item2[0]
			list4.append([Vector3(k2.x, k2.y + (ymax - k2.y) * 2.0, k2.z), item2[1]])
		d["neutral"].append_array(list4)
	if players == 2:
		d["neutral"].append([Vector3(xmax, y, zmin), 1.0])
		d["neutral"].append([Vector3(xmin, y, zmax), 1.0])
	if not _graph_search(d["Player1"][0], d["Player2"][0], d):
		return null
	return d


func _bridges_graph_to_home(bridges: Array, world: Dictionary) -> bool:
	for bridge in bridges:
		if not _graph_search(bridge, world["Player2"][0], world) or not _graph_search(world["Player2"][0], bridge, world):
			return false
	return true


func _same_entry(a: Array, b: Array) -> bool:
	return (a[0] as Vector3) == (b[0] as Vector3) and is_equal_approx(float(a[1]), float(b[1]))


func _graph_search(start: Array, target: Array, world: Dictionary) -> bool:
	var visited := {}
	var queue: Array = [start]
	while queue.size() > 0:
		var to_test: Array = queue.pop_front()
		if visited.has(to_test[0]):
			continue
		var in_range := _get_entries_in_range(to_test, world)
		for e in in_range:
			if _same_entry(e, target):
				return true
		visited[to_test[0]] = true
		for item in in_range:
			if not visited.has(item[0]):
				queue.append(item)
	return false


func _get_entries_in_range(to_test: Array, world: Dictionary) -> Array:
	var lst := []
	var r := _get_range_from_rand(to_test[1])
	var p: Vector3 = to_test[0]
	for item in world["neutral"]:
		if not ((item[0] as Vector3) == p) and (item[0] as Vector3).distance_to(p) < r:
			lst.append(item)
	if (world["Player2"][0][0] as Vector3).distance_to(p) < r:
		lst.append_array(world["Player2"])
	return lst


func _spawn_planets(positions: Dictionary) -> void:
	var id := 0
	for key in positions.keys():
		for item in positions[key]:
			var up: Vector3 = item[0]
			var node := PlanetController.new()
			node.name = "Planet%d" % id
			add_child(node)
			node.global_position = Vector3(up.x, up.y, -up.z)
			var s := _get_scale_from_random(item[1])
			node.scale = Vector3.ONE * s
			var col: Color = environment.player_colors[key]
			node.build(true, col, 0.6, "Planet")
			var rng := _get_range_from_rand(item[1])
			node.planet_range = rng
			node.set_outline_scale(rng / s * 2.0)
			var planet := Planet.new(self, node, key, col)
			node.parent = planet
			planet.scale = s
			planet.health = environment.base_planet_health * s
			planet.id = id
			id += 1
			planets.append(planet)
			node.start()
	for planet2 in planets:
		mini_map.append([planet2.node.global_position, environment.player_colors[planet2.player]])
		planet2.position = planet2.node.global_position
	_build_planet_grid()


func _update_mini_map() -> void:
	mini_map.clear()
	for planet in planets:
		mini_map.append([planet.node.global_position, planet.color])


func _populate_ship_counter() -> void:
	ship_counts.clear()
	for key in environment.player_layers.keys():
		ship_counts[key] = 0


func _update_ship_limits() -> void:
	ship_limits.clear()
	for i in range(environment.number_of_players + 1):
		var text: String = environment.player_names[i]
		ship_limits[text] = 0
		for planet in planets:
			if planet.player == text:
				var base := environment.base_ship_limit
				base = int(float(base) * planet.scale * 1.1)
				base = int(float(base) / environment.limit_weight)
				ship_limits[text] += base


func _change_planet_hands(planet: Planet) -> void:
	if player["selected_planet"] == planet:
		planet.node.deselect()
	var by_player := {}
	var order := []
	for item in planet.enemy_ships:
		if item.dead or not item.in_orbit:
			continue
		if by_player.has(item.player):
			by_player[item.player].append(item)
		else:
			by_player[item.player] = [item]
			order.append(item.player)
	if order.size() < 1:
		return
	var lst := []
	for s in planet.ships:
		if s.player == planet.player:
			lst.append(s)
	for item2 in lst:
		planet.ships.erase(item2)
		planet.enemy_ships.append(item2)
	var num := 0
	var key: String = order[0]
	for k in order:
		if by_player[k].size() > num:
			key = k
			num = by_player[k].size()
	planet.player = key
	planet.node.change_color(environment.player_colors[key])
	var list2 := []
	for s in planet.enemy_ships:
		if s.player == planet.player:
			list2.append(s)
	for item4 in list2:
		planet.enemy_ships.erase(item4)
		planet.ships.append(item4)
		if not item4.dead:
			item4.defend()
	var list3 := []
	for src in planet_links.keys():
		var dst: Planet = planet_links[src]
		if src == planet:
			planet.node.erase_link()
			list3.append(src)
		elif dst == planet:
			if src.player != dst.player:
				src.node.erase_link()
				list3.append(src)
			else:
				src.node.change_link_color()
	for item5 in list3:
		planet_links.erase(item5)


func _check_end_scenario() -> int:
	var num := 0
	var num2 := 0
	for planet in planets:
		if planet.player == "Player1":
			num += 1
		elif planet.player != "neutral":
			num2 += 1
	if num == 0:
		if ship_counts["Player1"] < 1:
			return 2
	elif num2 == 0:
		for k in ship_counts.keys():
			if k != "Player1" and k != "neutral" and ship_counts[k] > 3:
				return 0
		return 1
	return 0


func _end_game(winner: bool) -> void:
	if not _game_over:
		_audio.stream = A.sfx("click_heavy_00")
		_audio.volume_db = linear_to_db(VOLUME)
		_audio.play()
		_game_over = true
		if winner and net_role != Net.Role.OFFLINE:
			Stats.add_to_counter("VersusWins", 1)
			Stats.flush()
		elif winner:
			var n := environment.number_of_players - 1
			match environment.ai_diff:
				0: Stats.add_to_counter("EasyWins", n)
				1: Stats.add_to_counter("MediumWins", n)
				2: Stats.add_to_counter("HardWins", n)
				3: Stats.add_to_counter("CheatingWins", n)
			Stats.flush()
	if level:
		level.show_end_game(winner)


func _populate_adjacency_matrix() -> void:
	for planet in planets:
		reverse_adjacency[planet] = []
	for planet2 in planets:
		adjacency[planet2] = _get_planets_in_range_base(planet2)
	for planet3 in planets:
		for item in adjacency[planet3]:
			reverse_adjacency[item].append(planet3)


func _get_planets_in_range_base(to_check: Planet) -> Array:
	var lst := []
	for planet in planets:
		if to_check != planet and to_check.node.global_position.distance_to(planet.node.global_position) < to_check.node.planet_range:
			lst.append(planet)
	return lst


# ------------------------------------------------------------------ player commands
# The ClickHandler goes through these so a versus client can forward them to the host.

## Send ships from `source` to `dest` (and optionally link them), as ClickHandler.Select did.
func command_send(source: Planet, dest: Planet, percent: float, link: bool) -> void:
	if net_role != Net.Role.CLIENT:
		_apply_send(source, dest, percent, link, local_player)
		return
	_cmd_seq += 1
	# predict the link changes so hover/drag visuals are right before the host confirms
	if get_planet_assignment(dest) == source:
		planet_links.erase(dest)
		_pending_links[dest] = _cmd_seq
	planet_links.erase(source)
	if link:
		planet_links[source] = dest
	_pending_links[source] = _cmd_seq
	Net.send_command([_cmd_seq, "send", source.id, dest.id, percent, link])


func command_unlink(source: Planet) -> void:
	if net_role != Net.Role.CLIENT:
		delete_link(source)
		return
	_cmd_seq += 1
	planet_links.erase(source)
	_pending_links[source] = _cmd_seq
	Net.send_command([_cmd_seq, "unlink", source.id])


func command_pause() -> void:
	if net_role == Net.Role.CLIENT:
		_cmd_seq += 1
		Net.send_command([_cmd_seq, "pause"])
	else:
		GameTime.time_scale = 1.0 if GameTime.paused() else 0.0


func _apply_send(source: Planet, dest: Planet, percent: float, link: bool, by: String) -> void:
	if source.player != by or source == dest:
		return
	if source.node.planet_range < source.node.global_position.distance_to(dest.node.global_position):
		return
	if get_planet_assignment(dest) == source:
		delete_link(dest)
	send_wave(source, dest, percent)
	delete_link(source)
	if link:
		establish_link(source, dest)


func _planet_by_id(id: Variant) -> Planet:
	var i := int(id)
	if i < 0 or i >= planets.size():
		return null
	return planets[i]


# ------------------------------------------------------------------ versus: host

func _host_on_command(cmd: Array) -> void:
	if cmd.size() < 2:
		return
	_remote_ack = maxi(_remote_ack, int(cmd[0]))
	match str(cmd[1]):
		"send":
			if cmd.size() < 6:
				return
			var src := _planet_by_id(cmd[2])
			var dst := _planet_by_id(cmd[3])
			if src and dst:
				_apply_send(src, dst, clampf(float(cmd[4]), 0.25, 1.0), bool(cmd[5]), "Player2")
		"unlink":
			var src := _planet_by_id(cmd[2]) if cmd.size() > 2 else null
			if src and src.player == "Player2":
				delete_link(src)
		"pause":
			if not _game_over:
				command_pause()


## The opponent disconnected: an A.I. takes over Player2.
func on_remote_left() -> void:
	if net_role != Net.Role.HOST:
		return
	ais[0].is_ai_enabled = true


func _host_send_snapshot() -> void:
	_snap_timer -= GameTime.unscaled_delta
	if _snap_timer > 0.0 or Net.remote_id == 0:
		return
	_snap_timer += 1.0 / Net.SNAPSHOT_RATE
	if _snap_timer < 0.0:
		_snap_timer = 0.0
	Net.send_snapshot(_build_snapshot())


static func _qp(v: float) -> int:
	return clampi(roundi(v * POS_SCALE), -32767, 32767)


## Layout (little endian):
##   u8 version, f64 host time, u8 flags (1 = paused), u32 command ack, u32 Player2 kills,
##   9 x (u16 ship count, u16 ship limit),
##   u16 planets, per planet: u8 owner, u8 flags (1 = countdown), s16 link target (-1 none),
##   u32 ships, per ship: u32 id, u8 owner, u8 flags (1 = fired), u16 planet, 3 x s16 position
##                        [+ 3 x s16 laser target when fired]
func _build_snapshot() -> PackedByteArray:
	var fired := 0
	for s in ships:
		if s.net_fired:
			fired += 1
	var names: Array = environment.player_names
	var b := PackedByteArray()
	b.resize(18 + names.size() * 4 + 2 + planets.size() * 4 + 4 + ships.size() * 14 + fired * 6)
	b.encode_u8(0, 1)
	b.encode_double(1, Time.get_ticks_usec() / 1000000.0)
	b.encode_u8(9, 1 if GameTime.paused() else 0)
	b.encode_u32(10, _remote_ack)
	b.encode_u32(14, _remote_kills)
	var o := 18
	for n in names:
		b.encode_u16(o, clampi(ship_counts.get(n, 0), 0, 65535))
		b.encode_u16(o + 2, clampi(ship_limits.get(n, 0), 0, 65535))
		o += 4
	b.encode_u16(o, planets.size())
	o += 2
	for p in planets:
		b.encode_u8(o, _player_index[p.player])
		b.encode_u8(o + 1, 1 if p.node._countdown_enabled else 0)
		var l = planet_links.get(p)
		b.encode_s16(o + 2, l.id if l != null else -1)
		o += 4
	b.encode_u32(o, ships.size())
	o += 4
	for s in ships:
		b.encode_u32(o, s.id)
		b.encode_u8(o + 4, _player_index[s.player_name])
		b.encode_u8(o + 5, 1 if s.net_fired else 0)
		b.encode_u16(o + 6, s.planet.id)
		var v: Vector3 = s.pos
		b.encode_s16(o + 8, _qp(v.x))
		b.encode_s16(o + 10, _qp(v.y))
		b.encode_s16(o + 12, _qp(v.z))
		o += 14
		if s.net_fired:
			s.net_fired = false
			b.encode_s16(o, _qp(s.laser_to.x))
			b.encode_s16(o + 2, _qp(s.laser_to.y))
			b.encode_s16(o + 4, _qp(s.laser_to.z))
			o += 6
	return b


## End of game with two humans (and possibly A.I.s): same rules as _check_end_scenario,
## evaluated for each human player.
func _check_end_versus() -> void:
	var owned := {}
	for planet in planets:
		owned[planet.player] = owned.get(planet.player, 0) + 1
	for h in human_players:
		if owned.get(h, 0) == 0:
			continue
		var others_alive := false
		for k in owned.keys():
			if k != h and k != "neutral":
				others_alive = true
		for k in ship_counts.keys():
			if k != h and k != "neutral" and ship_counts[k] > 3:
				others_alive = true
		if not others_alive:
			_end_game(h == "Player1")
			_send_remote_result(h == "Player2")
			return
	if owned.get("Player1", 0) == 0 and ship_counts["Player1"] < 1:
		_end_game(false)
	if owned.get("Player2", 0) == 0 and ship_counts["Player2"] < 1:
		_send_remote_result(false)


func _send_remote_result(won: bool) -> void:
	var r := 1 if won else 0
	if _remote_result == r:
		return
	_remote_result = r
	Net.send_game_over(won)


# ------------------------------------------------------------------ versus: client

func _client_build_map(data: Dictionary) -> void:
	if not planets.is_empty():
		return
	var cols: Dictionary = data.get("colors", {})
	for k in cols.keys():
		environment.player_colors[k] = cols[k]
	var dictionary: Dictionary = data["map"]
	_spawn_planets(dictionary)
	_populate_adjacency_matrix()
	_place_rig_at_home(dictionary)
	if level:
		level.set_player_color_disc(local_color())
	map_ready.emit()


func _client_on_snapshot(data: PackedByteArray) -> void:
	if planets.is_empty():
		return
	var snap := _parse_snapshot(data)
	if snap.is_empty():
		return
	GameTime.time_scale = 0.0 if snap["paused"] else 1.0
	for p in _pending_links.keys():
		if _pending_links[p] <= snap["ack"]:
			_pending_links.erase(p)
	var kills: int = snap["kills"]
	if kills > _kills_seen:
		add_to_ship_counter(kills - _kills_seen)
		_kills_seen = kills
	_latest_t = snap["t"]
	if _render_time < 0.0:
		_render_time = _latest_t - INTERP_DELAY
	_snaps.append(snap)
	if _snaps.size() > 20:
		_client_apply(_snaps.pop_front())


func _parse_snapshot(b: PackedByteArray) -> Dictionary:
	var names: Array = environment.player_names
	if b.size() < 18 + names.size() * 4 + 6 or b.decode_u8(0) != 1:
		return {}
	var snap := {
		"t": b.decode_double(1),
		"paused": b.decode_u8(9) == 1,
		"ack": b.decode_u32(10),
		"kills": b.decode_u32(14),
	}
	var o := 18
	var counts := {}
	var limits := {}
	for n in names:
		counts[n] = b.decode_u16(o)
		limits[n] = b.decode_u16(o + 2)
		o += 4
	snap["counts"] = counts
	snap["limits"] = limits
	var np := b.decode_u16(o)
	o += 2
	if np != planets.size() or b.size() < o + np * 4 + 4:
		return {}
	snap["planets"] = b.slice(o, o + np * 4)
	o += np * 4
	var ns := b.decode_u32(o)
	o += 4
	var recs := []
	var pos := {}
	for i in ns:
		if b.size() < o + 14:
			return {}
		var id := b.decode_u32(o)
		var fired := b.decode_u8(o + 5) & 1
		var v := Vector3(b.decode_s16(o + 8), b.decode_s16(o + 10), b.decode_s16(o + 12)) / POS_SCALE
		var rec := [id, b.decode_u8(o + 4), fired, b.decode_u16(o + 6), v, Vector3.ZERO]
		o += 14
		if fired:
			if b.size() < o + 6:
				return {}
			rec[5] = Vector3(b.decode_s16(o), b.decode_s16(o + 2), b.decode_s16(o + 4)) / POS_SCALE
			o += 6
		recs.append(rec)
		pos[id] = v
	snap["ships"] = recs
	snap["pos"] = pos
	return snap


func _client_process() -> void:
	if _render_time >= 0.0:
		_render_time += GameTime.unscaled_delta
		var target := _latest_t - INTERP_DELAY
		if absf(_render_time - target) > 0.5:
			_render_time = target
		else:
			_render_time += (target - _render_time) * 0.05
		while not _snaps.is_empty() and _snaps[0]["t"] <= _render_time:
			_client_apply(_snaps.pop_front())
		var nxt: Dictionary = _snaps[0] if not _snaps.is_empty() else {}
		var alpha := 0.0
		if not nxt.is_empty() and nxt["t"] > _cur_snap_t:
			alpha = clampf((_render_time - _cur_snap_t) / (nxt["t"] - _cur_snap_t), 0.0, 1.0)
		var npos: Dictionary = nxt.get("pos", {})
		for s in ships:
			if npos.has(s.id):
				var to: Vector3 = npos[s.id]
				s.pos = s.net_from.lerp(to, alpha)
				var dir: Vector3 = to - s.net_from
				if dir.length_squared() > 1e-8:
					s.basis = U.look_basis(s.pos, s.pos + dir, Vector3.UP, s.basis)
			else:
				s.pos = s.net_from
			s.laser_from = s.pos
	if GameTime.crossed(45):
		_update_mini_map()
	_render_ships()


func _client_apply(snap: Dictionary) -> void:
	_cur_snap_t = snap["t"]
	var names: Array = environment.player_names
	ship_counts = snap["counts"]
	ship_limits = snap["limits"]
	# planets: owner, countdown, links
	var pb: PackedByteArray = snap["planets"]
	for i in planets.size():
		var p: Planet = planets[i]
		var owner: String = names[mini(pb.decode_u8(i * 4), names.size() - 1)]
		if p.player != owner:
			_client_change_hands(p, owner)
		var cd := (pb.decode_u8(i * 4 + 1) & 1) == 1
		if cd != p.net_countdown:
			p.net_countdown = cd
			if cd:
				p.node.enable_countdown(true)
			else:
				p.node.disable_countdown()
	for i in planets.size():
		var p: Planet = planets[i]
		if _pending_links.has(p):
			continue
		var t := pb.decode_s16(i * 4 + 2)
		var want: Planet = _planet_by_id(t) if t >= 0 else null
		if planet_links.get(p) == want:
			continue
		if want == null:
			planet_links.erase(p)
			p.node.erase_link()
		else:
			planet_links[p] = want
			if p.player == local_player:
				p.node.draw_link_to_planet(want)
	# ships
	var seen := {}
	for rec in snap["ships"]:
		var id: int = rec[0]
		seen[id] = true
		var planet := _planet_by_id(rec[3])
		if planet == null:
			continue
		var s: Ship = _client_ships.get(id)
		if s == null:
			var pl: String = names[mini(rec[1], names.size() - 1)]
			s = Ship.new(self, planet, pl)
			s.id = id
			s.player_name = pl
			s.color = environment.player_colors[pl]
			s.impact_index = explosion_index(s.color)
			s.pos = rec[4]
			_client_ships[id] = s
			ships.append(s)
		s.net_from = rec[4]
		s.planet = planet
		s.current_planet = planet
		s.laser_enabled = rec[2] == 1
		if s.laser_enabled:
			s.laser_to = rec[5]
			planet.node.play_laser_sound()
	for id in _client_ships.keys():
		if seen.has(id):
			continue
		var s: Ship = _client_ships[id]
		_client_ships.erase(id)
		spawn_explosion(s.impact_index, s.pos)
		s.planet.node.play_explode_sound()
		s.dead = true
		ships.erase(s)
	# Planet.ships / enemy_ships (used for the countdown sounds)
	for p in planets:
		p.ships.clear()
		p.enemy_ships.clear()
	for s in ships:
		if s.player_name == s.planet.player:
			s.planet.ships.append(s)
		else:
			s.planet.enemy_ships.append(s)


func _client_change_hands(planet: Planet, owner: String) -> void:
	if player["selected_planet"] == planet:
		planet.node.deselect()
	planet.player = owner
	planet.node.change_color(environment.player_colors[owner])
	for src in planet_links.keys():
		if planet_links[src] == planet and src.player == owner and src.player == local_player:
			src.node.change_link_color()
