class_name Planet
extends RefCounted
## Port of Planet.cs (plain data).

var node: PlanetController
var position := Vector3.ZERO
var ships: Array = []        # Array[Ship] (Ship.planet == this, same player as the planet... usually)
var enemy_ships: Array = []  # Array[Ship]
var master # MasterController
var player := "neutral"
var color := Color.WHITE
var is_decaying := false
var decay_start_time := 0.0
var health := 0.0
var last_changed_hands := 0.0

# remake bookkeeping
var scale := 1.0             # transform.localScale.x
var spawn_timer := 0.0       # ShipSpawner coroutine
var id := 0
var net_countdown := false # versus client: host's countdown state in the last snapshot


func _init(ma, go: PlanetController, pl: String, col: Color) -> void:
	color = col
	master = ma
	node = go
	player = pl
	position = go.global_position
	go.parent = self
