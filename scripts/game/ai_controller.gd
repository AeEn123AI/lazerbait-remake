class_name AIController
extends RefCounted
## Port of AIController.cs.

var player_name := ""
var is_ai_enabled := true
var update_ai_this_often := 1.0
var master # MasterController

var _distance_matrix := {}
var _sorted_distances := {}
var _player_spawn_rates := {}
var _last_actions := {}
var _last_graphed := {}
var _friend_planets: Array = []
var _enemy_planets: Array = []
var _total_planets: Array = []
var _turn_actions: Array = []
var _total_actions: Array = []
var _last_update_time := 0.0
var _first := true
var _original_update_ai_this_often := 1.0
var _distance_weight := 0.5
var _defense_threshold := 0.05
var _link_comfort_multiplier := 0.8
var _spawn_rate_weight := 2.0
var _attack_ratio_threshold := 1.01
var _graph_wait := 20.0


class Action:
	var source
	var type := 0 # 0 Attack, 1 Defend, 2 Link
	var timestamp := 0.0


func update() -> void:
	if not _check_time() or not is_ai_enabled or GameTime.paused():
		return
	if _first:
		_first = false
		_construct_planet_state()
		_populate_distance_matrix()
		_populate_sorted_distances()
		_player_spawn_rates = master.get_spawn_rates()
		_construct_last_actions()
		_construct_last_graphed()
		update_ai_this_often = master.environment.update_ai_this_often
		update_ai_this_often += update_ai_this_often * randf()
		_original_update_ai_this_often = update_ai_this_often
		_attack_ratio_threshold = master.environment.ai_attack_threshold
		_graph_wait = update_ai_this_often * 3.0
	_construct_planet_state()
	_turn_actions.clear()
	if Settings.ai_diff == 3:
		update_ai_this_often = _original_update_ai_this_often + float(_friend_planets.size()) * 0.3
	else:
		update_ai_this_often = _original_update_ai_this_often + float(_friend_planets.size()) * 0.5
	_graph_wait = update_ai_this_often * 5.0
	var now := GameTime.realtime()
	for friend_planet in _friend_planets:
		var num: float = _last_actions[friend_planet]
		if num + _graph_wait < now and friend_planet.ships.size() > 3 and friend_planet.enemy_ships.size() == 0:
			var planet = _graph_search_to_enemy(friend_planet)
			if planet != null:
				_send_wave(friend_planet, planet)
				_last_actions[friend_planet] = now
		if _should_planet_defend(friend_planet, 1.0):
			var action = _defend(friend_planet)
			if action != null:
				_turn_actions.append(action)
				_total_actions.append(action)
				_last_actions[friend_planet] = action.timestamp
		var link_result := _should_planet_link(friend_planet)
		if link_result.has("abort"):
			# The original threw ArgumentNullException here (GetPlanetAssignment(null)),
			# which ended this AI turn early.
			return
		if link_result["ok"]:
			var action2 = _establish_link(friend_planet, link_result["to_link"])
			_turn_actions.append(action2)
			_total_actions.append(action2)
			_last_actions[friend_planet] = action2.timestamp
		if _should_planet_erase_link(friend_planet):
			master.delete_link(friend_planet)
		var atk := _should_planet_attack(friend_planet)
		if atk["ok"]:
			var action3 = _attack(friend_planet, atk["target"], atk["percent"])
			_turn_actions.append(action3)
			_total_actions.append(action3)
			_last_actions[friend_planet] = action3.timestamp


func _graph_search_to_enemy(planet):
	var queue: Array = [[planet, []]]
	var seen := {planet: true}
	var path = null
	while queue.size() > 0:
		var kv: Array = queue.pop_front()
		var key = kv[0]
		var p: Array = kv[1]
		p.append(key)
		if key.player != player_name:
			path = p
			break
		for item in master.get_planets_in_range(key):
			if item != key and not seen.has(item):
				seen[item] = true
				queue.append([item, p.duplicate()])
	if path == null or path.size() == 1:
		return null
	return path[1]


func _construct_last_actions() -> void:
	_last_actions = {}
	for p in _total_planets:
		_last_actions[p] = 0.0


func _construct_last_graphed() -> void:
	_last_graphed = {}
	for p in _total_planets:
		_last_graphed[p] = null


func _populate_distance_matrix() -> void:
	_distance_matrix = {}
	for a in _total_planets:
		var row := {}
		for b in _total_planets:
			row[b] = a.position.distance_to(b.position)
		_distance_matrix[a] = row


func _populate_sorted_distances() -> void:
	_sorted_distances = {}
	for a in _total_planets:
		var lst := []
		for b in _distance_matrix[a].keys():
			lst.append([b, _distance_matrix[a][b]])
		lst.sort_custom(func(x, y): return x[1] < y[1])
		_sorted_distances[a] = lst


func _construct_planet_state() -> void:
	_friend_planets.clear()
	_enemy_planets.clear()
	_total_planets.clear()
	for p in master.get_planets():
		if p.player == player_name:
			_friend_planets.append(p)
	for p in master.get_planets():
		if p.player != player_name:
			_enemy_planets.append(p)
	_total_planets.append_array(_friend_planets)
	_total_planets.append_array(_enemy_planets)


func _check_time() -> bool:
	if _last_update_time + update_ai_this_often > GameTime.realtime():
		return false
	_last_update_time = GameTime.realtime()
	return true


func _send_wave(source, dest, percent := 1.0) -> void:
	if master.get_planet_assignment(dest) == source:
		master.delete_link(dest)
	master.send_wave(source, dest, percent)


func _calculate_win_probability(att_count: int, def_count: int, distance := 1.0, spawn_rate := 1.0) -> float:
	return float(att_count - 5) / float(def_count + 1) - distance * distance * _distance_weight + spawn_rate * _spawn_rate_weight


func _should_planet_defend(planet, distance := 1.0) -> bool:
	if planet.enemy_ships.size() < 10:
		return false
	var num := _calculate_win_probability(planet.enemy_ships.size(), planet.ships.size() + 10, distance, _player_spawn_rates[planet.player])
	return num > _defense_threshold


func _should_planet_link(planet) -> Dictionary:
	if master.get_planet_assignment(planet) != planet:
		return {"ok": false}
	if _any_neighbors_are_enemies(planet):
		return {"ok": false}
	var to_link = _graph_search_to_enemy(planet)
	var planet2 = to_link
	if planet2 == null:
		return {"abort": true}
	while master.get_planet_assignment(planet2) != planet2:
		if planet2 == planet:
			return {"ok": false}
		planet2 = master.get_planet_assignment(planet2)
	if master.get_planet_assignment(to_link) == planet:
		return {"ok": false}
	return {"ok": to_link != null, "to_link": to_link}


func _should_planet_attack(planet) -> Dictionary:
	if planet.ships.size() < 5 or planet.enemy_ships.size() > 5:
		return {"ok": false}
	for item in master.get_planets_in_range(planet):
		if not (item.player == planet.player):
			var num := 0
			for s in item.enemy_ships:
				if s.player != planet.player:
					num += 1
			if num <= item.ships.size() / 2:
				var percent := float(item.ships.size() * 2) / float(planet.ships.size())
				percent = percent if not (percent > 1.0) else 1.0
				return {"ok": true, "target": item, "percent": percent}
	return {"ok": false}


func _should_planet_erase_link(planet) -> bool:
	if master.get_planet_assignment(planet) != planet and planet.enemy_ships.size() > 0:
		return true
	if _any_neighbors_are_enemies(planet):
		return true
	return false


func _defend(to_defend):
	var planet = null
	var num := 0.0
	for item in _sorted_distances.get(to_defend, []):
		var key = item[0]
		if _friend_planets.has(key) and key.enemy_ships.size() == 0:
			var num2 := _calculate_win_probability(to_defend.enemy_ships.size(), to_defend.ships.size() + key.ships.size(), float(item[1]) * 2.0, 1.0)
			if num2 > num:
				num = num2
				planet = key
	if planet != null:
		_send_wave(planet, to_defend)
		var action := Action.new()
		action.source = to_defend
		action.type = 1
		action.timestamp = GameTime.realtime()
		return action
	return null


func _establish_link(source, dest) -> Action:
	master.send_wave(source, dest)
	master.establish_link(source, dest)
	var action := Action.new()
	action.source = source
	action.type = 2
	action.timestamp = GameTime.realtime()
	return action


func _attack(source, dest, percent: float) -> Action:
	_send_wave(source, dest, percent)
	var action := Action.new()
	action.source = source
	action.type = 0
	action.timestamp = GameTime.realtime()
	return action


func _any_neighbors_are_enemies(planet) -> bool:
	var lst: Array = master.get_planets_in_range(planet)
	lst.append_array(master.get_planets_in_reverse_range(planet))
	for item in lst:
		if item.player != player_name:
			return true
	return false
