extends Node
## Port of MenuSettings (static game settings) + SettingsFile persistence.
## The original saved to Application.persistentDataPath + "/lazerbait-settings.json";
## we save the same fields to user://lazerbait-settings.json, plus remake-only options.

const SETTINGS_PATH := "user://lazerbait-settings.json"

# --- MenuSettings (values applied when "Start" is pressed) ---
var ship_translational_speed := 0.0
var ship_rotational_speed := 0.0
var number_of_players := 0
var number_of_ships := 0
var game_speed := 0.0
var player_color := Color(0, 1, 1, 1) # Color.cyan
var ai_diff := 0
var planet_count := 0
var min_x := 0.0
var max_x := 0.0
var min_z := 0.0
var max_z := 0.0

# --- menu selector state ---
var ship_setting_count := 0
var speed_setting_count := 0
var player_setting_count := 0
var color_settings_count := 0
var ai_settings_count := 0
var planet_settings_count := 0
var quality_index := 0

# --- remake-only options ---
var passthrough := false        # VR passthrough (mixed reality); optional, off by default
var music_muted := false        # persists the in-game "Mute Music" toggle within a session only (original behaviour)

const QUALITY_NAMES := ["Low", "Medium", "High"]  # QualitySettings.names from the original build


func _ready() -> void:
	pass


## MenuClickHandler.clearMenuSettings()
func clear_menu_settings() -> void:
	ship_translational_speed = 0.0
	ship_rotational_speed = 0.0
	number_of_players = 0
	number_of_ships = 0
	game_speed = 0.0
	player_color = Color(0, 1, 1, 1)
	ai_diff = 0
	planet_count = 0
	min_x = 0.0
	max_x = 0.0
	min_z = 0.0
	max_z = 0.0


static func _col_to_dict(c: Color) -> Dictionary:
	return {"r": c.r, "g": c.g, "b": c.b, "a": c.a}


static func _dict_to_col(d: Variant, fallback: Color) -> Color:
	if typeof(d) != TYPE_DICTIONARY:
		return fallback
	return Color(float(d.get("r", fallback.r)), float(d.get("g", fallback.g)), float(d.get("b", fallback.b)), float(d.get("a", fallback.a)))


func save() -> void:
	var data := {
		"shipTranslationalSpeed": ship_translational_speed,
		"shipRotationalSpeed": ship_rotational_speed,
		"numberOfPlayers": number_of_players,
		"numberOfShips": number_of_ships,
		"gameSpeed": game_speed,
		"playerColor": _col_to_dict(player_color),
		"aiDiff": ai_diff,
		"planetCount": planet_count,
		"minX": min_x,
		"maxX": max_x,
		"minZ": min_z,
		"maxZ": max_z,
		"shipSettingCount": ship_setting_count,
		"speedSettingCount": speed_setting_count,
		"playerSettingCount": player_setting_count,
		"colorSettingsCount": color_settings_count,
		"aiSettingsCount": ai_settings_count,
		"planetSettingsCount": planet_settings_count,
		"qualityIndex": quality_index,
		"passthrough": passthrough,
	}
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	ship_translational_speed = float(d.get("shipTranslationalSpeed", ship_translational_speed))
	ship_rotational_speed = float(d.get("shipRotationalSpeed", ship_rotational_speed))
	number_of_players = int(d.get("numberOfPlayers", number_of_players))
	number_of_ships = int(d.get("numberOfShips", number_of_ships))
	game_speed = float(d.get("gameSpeed", game_speed))
	player_color = _dict_to_col(d.get("playerColor"), player_color)
	ai_diff = int(d.get("aiDiff", ai_diff))
	planet_count = int(d.get("planetCount", planet_count))
	min_x = float(d.get("minX", min_x))
	max_x = float(d.get("maxX", max_x))
	min_z = float(d.get("minZ", min_z))
	max_z = float(d.get("maxZ", max_z))
	ship_setting_count = clampi(int(d.get("shipSettingCount", ship_setting_count)), 0, 2)
	speed_setting_count = clampi(int(d.get("speedSettingCount", speed_setting_count)), 0, 2)
	player_setting_count = clampi(int(d.get("playerSettingCount", player_setting_count)), 0, 2)
	color_settings_count = clampi(int(d.get("colorSettingsCount", color_settings_count)), 0, 7)
	ai_settings_count = clampi(int(d.get("aiSettingsCount", ai_settings_count)), 0, 3)
	planet_settings_count = clampi(int(d.get("planetSettingsCount", planet_settings_count)), 0, 3)
	quality_index = clampi(int(d.get("qualityIndex", quality_index)), 0, QUALITY_NAMES.size() - 1)
	passthrough = bool(d.get("passthrough", passthrough))
