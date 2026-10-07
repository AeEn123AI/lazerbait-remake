class_name Ship
extends RefCounted
## Ship.cs + ShipController.cs.
##
## The original moved orbiting ships with Rigidbody.MovePosition on an interpolated kinematic
## body while the physics step was 0.08 s, so an orbit advances one rotation step per physics
## tick and is interpolated in between. That mechanism is emulated here (body_prev/body_cur/
## pending target), together with Unity's trigger enter/exit semantics, so ship movement and
## combat play out like the original.

const DAMAGE_PER_BULLET := 20.0
const MAX_COLLISIONS := 2
const SPEED_VARIATION := 0.12
const FLOAT_ADJUST_PERIOD := 0.8
const TRIGGER_RADIUS := 0.75   # SphereCollider r=0.3 on a 2.5 scaled ship

# --- Ship.cs ---
var player := ""
var planet: Planet
var master

# --- ShipController.cs ---
var custom_tag := ""
var in_orbit := false
var rotational_speed := 200.0
var translational_speed := 4.0
var health := 200.0
var rate_of_fire := 0.4
var player_name := ""
var current_planet: Planet
var is_initialized := false
var color := Color.WHITE
var impact_index := 0

var planet_pos := Vector3.ZERO
var previous := Vector3.ZERO
var orbit_axis := Vector3(1, 1, -1)
var move_target := Vector3.ZERO
var velocity := Vector3.ZERO
var defending := false
var last_fired := 0.0
var colliding_ships: Array = []   # Array[Ship] (may hold duplicates / dead ships, like the original)
var cached_position := Vector3.ZERO
var newly_orbiting := false
var previous_update_time := 0.0
var delta_time := 0.0
var is_late_init := false
var float_adjust_time := 0.0
var dir_mult := 1.001
var last_taken_damage_from := ""
var p_vel1 := Vector3.ZERO
var p_vel2 := Vector3.ZERO
var p_vel3 := Vector3.ZERO

# --- emulated physics / rendering state ---
var pos := Vector3.ZERO          # transform.position
var basis := Basis.IDENTITY      # transform.rotation
var body_prev := Vector3.ZERO
var body_cur := Vector3.ZERO
var pending := false
var pending_target := Vector3.ZERO
var collider_enabled := true     # Collider.enabled && Rigidbody.detectCollisions
var dead := false
var laser_enabled := false
var laser_from := Vector3.ZERO
var laser_to := Vector3.ZERO
var overlap_ships := {}          # Ship -> true (current trigger pairs)
var overlap_planets := {}        # Planet -> true
var cell := Vector3i.ZERO
var id := 0

# --- versus mode (Net) ---
var net_fired := false           # host: fired since the last snapshot
var net_from := Vector3.ZERO     # client: position in the last applied snapshot


func _id_lt(o: Ship) -> bool:
	return id < o.id


func _init(p_master, plan: Planet, pl: String) -> void:
	master = p_master
	planet = plan
	player = pl


## ShipController.Start()
func start() -> void:
	rate_of_fire += rate_of_fire * (randf() / 10.0)
	health = 100.0
	cached_position = pos
	rotational_speed += (randf() - 0.5) * SPEED_VARIATION * rotational_speed
	translational_speed += (randf() - 0.5) * SPEED_VARIATION * translational_speed
	previous_update_time = 0.0
	is_initialized = true


func set_transform_position(p: Vector3) -> void:
	# Writing transform.position on the kinematic body teleports it.
	pos = p
	body_prev = p
	body_cur = p
	pending = false


func _late_init() -> void:
	planet_pos = current_planet.position
	move_target = planet_pos
	is_late_init = true
	basis = U.look_basis(pos, move_target, Vector3.UP, basis)


func custom_update(now: float) -> void:
	previous_update_time = previous_update_time if previous_update_time > 0.0 else now
	delta_time = now - previous_update_time
	if delta_time > 0.5:
		previous_update_time = now
	elif is_initialized and planet != null:
		if not is_late_init:
			_late_init()
		_calculate_velocity()
		_move()
		_check_health_and_die()
		_shoot(now)
		previous_update_time = now


func change_planet(new_planet: Planet) -> void:
	if not is_late_init:
		return
	var old := current_planet
	current_planet = new_planet
	var vector := planet_pos - pos
	vector *= new_planet.scale / old.scale
	vector *= 0.5
	planet_pos = new_planet.position
	if in_orbit:
		move_target = planet_pos - vector
	else:
		move_target = planet_pos
	in_orbit = false
	collider_enabled = true
	planet.ships.erase(self)
	if player_name == new_planet.player:
		new_planet.ships.append(self)
	else:
		new_planet.enemy_ships.append(self)
	planet = new_planet
	basis = U.look_basis(pos, new_planet.position, Vector3.UP, basis)


func defend() -> void:
	defending = true
	collider_enabled = true


## OnTriggerEnter with a planet collider
func on_trigger_enter_planet(p: Planet) -> void:
	if not is_initialized:
		return
	if p != current_planet:
		return
	var assignment: Planet = master.get_planet_assignment(p)
	if player_name == p.player and assignment != p:
		in_orbit = true
		change_planet(assignment)
		return
	if not in_orbit:
		newly_orbiting = true
		in_orbit = true
		_assign_orbit_axis(planet_pos)
		collider_enabled = planet.enemy_ships.size() > 0
	if defending and planet.enemy_ships.size() == 0:
		defending = false
		collider_enabled = false


func on_trigger_enter_ship(other: Ship) -> void:
	if not is_initialized:
		return
	if other.player_name != player_name:
		colliding_ships.append(other)


func on_trigger_exit_ship(other: Ship) -> void:
	if other.player_name != player_name:
		colliding_ships.erase(other)


func _rotate_around(center: Vector3, axis: Vector3, angle: float) -> void:
	if float_adjust_time + FLOAT_ADJUST_PERIOD < previous_update_time:
		float_adjust_time = previous_update_time
		var s := current_planet.scale
		if s * 1.0 + (1.3 - s) / 5.0 > planet_pos.distance_to(cached_position):
			dir_mult += 0.0002
		else:
			dir_mult -= 0.0001
	var q := Quaternion(axis.normalized(), deg_to_rad(angle))
	var v := cached_position - center
	v = (q * v) * dir_mult
	# Rigidbody.MovePosition -> applied at the next physics step
	pending = true
	pending_target = center + v


func _assign_orbit_axis(center: Vector3) -> void:
	var up_hint := Vector3(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0, randf() * 2.0 - 1.0)
	basis = U.look_basis(pos, center, up_hint, basis)
	var num2 := 1.0 if randf() - 0.5 >= 0.0 else -1.0
	orbit_axis = basis.y * num2


func _calculate_velocity() -> void:
	var v := cached_position - previous
	previous = cached_position
	var v2 := v / (delta_time + 1e-05)
	p_vel1 = p_vel2
	p_vel2 = p_vel3
	p_vel3 = v2
	velocity = (p_vel1 + p_vel2 + p_vel3) / 3.0


func _move() -> void:
	if in_orbit:
		var num := 0.011111 * rotational_speed
		_rotate_around(planet_pos, orbit_axis, num * 6.0)
		basis = U.look_basis(cached_position, velocity + cached_position, Vector3.UP, basis)
	else:
		var max_delta := delta_time * translational_speed
		set_transform_position(U.move_towards(cached_position, move_target, max_delta))
		if pos.distance_squared_to(move_target) < 1e-10:
			move_target = planet_pos
	cached_position = pos


func _check_health_and_die() -> void:
	if health < 0.0:
		master.spawn_explosion(impact_index, pos)
		current_planet.node.play_explode_sound()
		planet.enemy_ships.erase(self)
		planet.ships.erase(self)
		master.decrement_ship_count(player_name)
		laser_enabled = false
		is_initialized = false
		master.count_kill(player, last_taken_damage_from)
		master.destroy_ship(self)


func take_damage(damage: float, from_player: String) -> void:
	if defending:
		damage /= 3.0
	health -= damage
	last_taken_damage_from = from_player


func _shoot(now: float) -> void:
	if GameTime.crossed(5):
		laser_enabled = false
	if not (last_fired + rate_of_fire < now):
		return
	last_fired = now
	if in_orbit and planet.enemy_ships.size() == 0:
		collider_enabled = false
		defending = false
	elif in_orbit and colliding_ships.size() < MAX_COLLISIONS:
		collider_enabled = true
		defending = true
	elif colliding_ships.size() < 100:
		collider_enabled = true
		defending = true
	else:
		collider_enabled = false
		defending = true
	if not collider_enabled and colliding_ships.size() == 0:
		return
	var target: Ship = null
	while colliding_ships.size() > 0 and target == null:
		var c: Ship = colliding_ships[0]
		if c == null or c.dead:
			colliding_ships.remove_at(0)
		else:
			target = c
	if target != null:
		laser_enabled = true
		laser_from = pos
		laser_to = target.pos
		net_fired = true
		current_planet.node.play_laser_sound()
		target.take_damage(DAMAGE_PER_BULLET, player)
