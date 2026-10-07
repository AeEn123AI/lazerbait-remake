extends Node
## Replacement for steamCounters (Steam stats/leaderboards). Steamworks isn't available,
## so the same counters are kept locally in user://lazerbait-stats.json and the
## leaderboard boards show the local profile's entry.

const STATS_PATH := "user://lazerbait-stats.json"

# Same keys and insertion order as steamCounters.baseCounters
const KEYS := ["ShipKills", "EasyWins", "MediumWins", "HardWins", "CheatingWins", "VersusWins"]
const DISPLAY_NAMES := {
	"ShipKills": "Ships Destroyed",
	"EasyWins": "Easy AIs Defeated",
	"MediumWins": "Medium AIs Defeated",
	"HardWins": "Hard AIs Defeated",
	"CheatingWins": "Cheating AIs Defeated",
	"VersusWins": "Versus Wins", # remake addition (networked versus mode)
}

var base_counters := {"ShipKills": 0, "EasyWins": 0, "MediumWins": 0, "HardWins": 0, "CheatingWins": 0, "VersusWins": 0}
var _updates: Array = []
var _dirty := false
var _save_timer := 0.0
var persist := true # disabled by automated test runs (Debug)


func _ready() -> void:
	_load()


func add_to_counter(key: String, value: int) -> void:
	_updates.append([key, value])


func _apply_updates() -> void:
	if _updates.is_empty():
		return
	for u in _updates:
		base_counters[u[0]] = int(base_counters.get(u[0], 0)) + int(u[1])
	_updates.clear()
	_dirty = true


func get_counter(key: String) -> int:
	_apply_updates()
	return int(base_counters.get(key, 0))


## Returns display name -> value, in the original's order.
func get_all_counters() -> Array:
	_apply_updates()
	var out := []
	for k in KEYS:
		out.append([DISPLAY_NAMES[k], int(base_counters[k])])
	return out


func player_name() -> String:
	var n := OS.get_environment("USER")
	if n.is_empty():
		n = OS.get_environment("USERNAME")
	if n.is_empty():
		n = "You"
	return n


func _process(delta: float) -> void:
	# steamCounters pushed stats every 900 frames; we just flush periodically.
	_save_timer += delta
	if _save_timer > 10.0:
		_save_timer = 0.0
		flush()


func flush() -> void:
	_apply_updates()
	if not _dirty or not persist:
		return
	_dirty = false
	var f := FileAccess.open(STATS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(base_counters, "\t"))


func _load() -> void:
	if not FileAccess.file_exists(STATS_PATH):
		return
	var f := FileAccess.open(STATS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		for k in KEYS:
			if parsed.has(k):
				base_counters[k] = int(parsed[k])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		flush()
