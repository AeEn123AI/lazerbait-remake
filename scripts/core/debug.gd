extends Node
## Development / testing helpers, all driven by user command line arguments (after `--`):
##   --autotest=SECONDS     print match statistics periodically and quit after SECONDS
##   --ai-player1           let an AIController play for Player1 (for automated matches)
##   --timescale=N          run the simulation N times faster (testing only)
##   --shots=T:PATH,...     save screenshots of the main viewport at T seconds
##   --cam=x,y,z,yaw,pitch  desktop camera override (degrees), applied once the level is loaded
##   --settings=k=v;k=v     override Settings fields (e.g. player_setting_count=1)
##   --net-demo             versus: after a few seconds, send + link from the home planet
##                          to its nearest neighbour through MasterController.command_send

var autotest := -1.0
var ai_player1 := false
var shots: Array = []
var cam_override: Array = []
var _t := 0.0
var _next_report := 0.0
var _cam_applied := false
var _p1_ai = null
var demo_select := false
var cpu_particles := false
var desktop_menu := false
var explosion_test := false
var _boom_t := 0.0
var _demo_done := false
var net_demo := false
var _net_demo_done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			autotest = float(a.split("=")[1])
			Stats.persist = false
		elif a == "--explosion-test":
			explosion_test = true
		elif a == "--desktop-menu":
			desktop_menu = true
		elif a == "--cpu-particles":
			cpu_particles = true
		elif a == "--demo-select":
			demo_select = true
		elif a == "--net-demo":
			net_demo = true
		elif a == "--ai-player1":
			ai_player1 = true
			Stats.persist = false
		elif a.begins_with("--timescale="):
			GameTime.debug_speed = float(a.split("=")[1])
		elif a.begins_with("--shots="):
			for s in a.substr(8).split(","):
				var p := s.split(":")
				shots.append([float(p[0]), p[1]])
		elif a.begins_with("--cam="):
			for v in a.substr(6).split(","):
				cam_override.append(float(v))
		elif a.begins_with("--settings="):
			for kv in a.substr(11).split(";"):
				var p := kv.split("=")
				if p.size() == 2:
					var cur = Settings.get(p[0])
					if typeof(cur) == TYPE_INT:
						Settings.set(p[0], int(p[1]))
					elif typeof(cur) == TYPE_FLOAT:
						Settings.set(p[0], float(p[1]))
					elif typeof(cur) == TYPE_BOOL:
						Settings.set(p[0], p[1] == "true")


func _enter_tree() -> void:
	if "--cpu-particles" in OS.get_cmdline_user_args():
		get_tree().node_added.connect(_on_node_added)


## Software Vulkan (lavapipe/LLVM 15) crashes on Godot's GPU particle shaders; for screenshots
## on such machines swap them for CPUParticles3D.
func _on_node_added(n: Node) -> void:
	if n is GPUParticles3D:
		_swap_particles.call_deferred(n)


func _swap_particles(g: GPUParticles3D) -> void:
	if not is_instance_valid(g) or not g.is_inside_tree():
		return
	var c := CPUParticles3D.new()
	c.convert_from_particles(g)
	c.transform = g.transform
	c.visible = g.visible
	c.one_shot = g.one_shot
	c.emitting = g.emitting
	var par := g.get_parent()
	var idx := g.get_index()
	par.remove_child(g)
	par.add_child(c)
	par.move_child(c, idx)
	c.set_meta("from_gpu", true)
	g.queue_free()


func _ready_post() -> void:
	pass


func _master() -> MasterController:
	var main := get_tree().root.get_node_or_null("Main")
	if main == null or main.level == null:
		return null
	if main.level is GameLevel:
		return (main.level as GameLevel).master
	return null


func _process(delta: float) -> void:
	_t += delta
	var main := get_tree().root.get_node_or_null("Main")
	if not cam_override.is_empty() and not _cam_applied and main and main.level and main.rig and not main.rig.vr:
		if _t > 0.3:
			_cam_applied = true
			var rig: PlayerRig = main.rig
			var s := rig.scale_factor()
			rig.set_rig_position(Vector3(cam_override[0], cam_override[1] - PlayerRig.EYE_HEIGHT * s, cam_override[2]))
			rig.set_desktop_yaw_pitch(deg_to_rad(cam_override[3]), deg_to_rad(cam_override[4]))
	var m := _master()
	if ai_player1 and m and _p1_ai == null and m.planets.size() > 0:
		_p1_ai = AIController.new()
		_p1_ai.player_name = "Player1"
		_p1_ai.master = m
		_p1_ai.is_ai_enabled = true
		m.ais.append(_p1_ai)
	if desktop_menu and m and _t > 2.0 and main.rig.left:
		main.rig.left.desktop_pad_latched = true
	if explosion_test and m and _t > 1.5:
		_boom_t -= delta
		if _boom_t <= 0.0:
			_boom_t = 0.6
			var cam: Camera3D = main.rig.head
			var fwd := -cam.global_transform.basis.z
			var right := cam.global_transform.basis.x
			for i in 9:
				m.spawn_explosion(i, cam.global_position + fwd * 3.0 + right * (float(i) - 4.0) * 0.45)
	if net_demo and not _net_demo_done and m and m.planets.size() > 0 and _t > 6.0:
		_net_demo_done = true
		_net_demo(m)
	if demo_select and not _demo_done and m and _t > 2.5:
		_demo_done = true
		_demo(m)
	if autotest > 0.0:
		if _t >= _next_report:
			_next_report += 5.0
			_report(m)
		if _t >= autotest:
			_report(m)
			get_tree().quit()
	for s in shots.duplicate():
		if _t >= s[0]:
			shots.erase(s)
			var img := get_viewport().get_texture().get_image()
			img.save_png(s[1])
			print("[debug] saved ", s[1])
			if shots.is_empty() and autotest < 0.0:
				get_tree().quit()


func _report(m: MasterController) -> void:
	if m == null:
		print("[autotest] t=%.1f (no game)" % _t)
		return
	var owned := {}
	for p in m.planets:
		owned[p.player] = owned.get(p.player, 0) + 1
	var counts := {}
	for k in m.ship_counts.keys():
		if m.ship_counts[k] != 0:
			counts[k] = m.ship_counts[k]
	var orbit := 0
	for s in m.ships:
		if s.in_orbit:
			orbit += 1
	print("[perf] fps=%d" % Engine.get_frames_per_second())
	if m.net_role != Net.Role.OFFLINE:
		var links := []
		for src in m.planet_links.keys():
			links.append("%s:%d->%d" % [src.player, src.id, m.planet_links[src].id])
		print("[net] role=%d local=%s links=%s paused=%s snapshot=%dB" % [m.net_role, m.local_player, links, GameTime.paused(), m._build_snapshot().size() if m.net_role == Net.Role.HOST else 0])
	print("[autotest] t=%.1f game_t=%.1f planets=%d owned=%s ships=%d (orbit %d) counts=%s limits=%s links=%d over=%s" % [
		_t, GameTime.time, m.planets.size(), owned, m.ships.size(), orbit, counts, m.ship_limits, m.planet_links.size(), m._game_over])


func _net_demo(m: MasterController) -> void:
	for p in m.planets:
		if p.player == m.local_player:
			var near: Array = m.get_planets_in_range(p)
			near.sort_custom(func(a, b): return a.position.distance_to(p.position) < b.position.distance_to(p.position))
			if near.size() > 0:
				print("[net-demo] %s sends %d -> %d (%d ships there)" % [m.local_player, p.id, near[0].id, p.ships.size()])
				m.command_send(p, near[0], 1.0, true)
			return


## Select the home planet, hover a planet in range and draw a link to another one.
func _demo(m: MasterController) -> void:
	var home: Planet = null
	for p in m.planets:
		if p.player == "Player1":
			home = p
	if home == null:
		return
	var ch: ClickHandler = m.level.click_handler
	ch._select(home.node, false)
	var in_range: Array = m.get_planets_in_range(home)
	in_range.sort_custom(func(a, b): return a.position.distance_to(home.position) < b.position.distance_to(home.position))
	if in_range.size() >= 2:
		var target: Planet = in_range[1]
		target.node.on_pointer_enter(false)
		m.establish_link(home, in_range[0])
		home.node.draw_link_to_planet(in_range[0])
