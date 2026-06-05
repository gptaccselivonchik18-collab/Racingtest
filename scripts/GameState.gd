extends Node

signal money_changed(new_amount: int)
signal car_changed(car_id: String)
signal settings_changed

const SAVE_PATH := "user://neon_asphalt_rush_save.json"

var money: int = 0
var selected_car: String = "street_starter"
var unlocked_cars: Dictionary = {}
var best_times: Dictionary = {}
var settings: Dictionary = {
	"music_volume": 0.55,
	"sfx_volume": 0.75,
	"steering_sensitivity": 1.0,
	"graphics_quality": "Medium"
}

var cars: Dictionary = {
	"street_starter": {
		"name": "Street Starter", "tagline": "Balanced starter street racer.",
		"max_speed": 58.0, "acceleration": 18.0, "handling": 2.35, "braking": 27.0,
		"drift_control": 0.58, "nitro_power": 22.0, "mass": 1.00, "price": 0, "unlocked": true,
		"color": Color(0.08, 0.70, 1.00), "accent": Color(1.00, 0.95, 0.18), "shape": "hatch"
	},
	"sport_viper": {
		"name": "Sport Viper", "tagline": "Fast acceleration, high top speed, nervous steering.",
		"max_speed": 68.0, "acceleration": 24.0, "handling": 1.85, "braking": 25.0,
		"drift_control": 0.48, "nitro_power": 27.0, "mass": 0.92, "price": 2600, "unlocked": false,
		"color": Color(1.00, 0.14, 0.32), "accent": Color(0.05, 0.03, 0.05), "shape": "super"
	},
	"iron_muscle": {
		"name": "Iron Muscle", "tagline": "Heavy muscle car: brutal launch, stable body, weak brakes.",
		"max_speed": 62.0, "acceleration": 25.0, "handling": 1.70, "braking": 19.0,
		"drift_control": 0.42, "nitro_power": 22.0, "mass": 1.35, "price": 4200, "unlocked": false,
		"color": Color(0.96, 0.46, 0.08), "accent": Color(0.06, 0.06, 0.07), "shape": "muscle"
	},
	"drift_ghost": {
		"name": "Drift Ghost", "tagline": "Medium top speed, best sideways control and nitro recovery.",
		"max_speed": 60.0, "acceleration": 20.0, "handling": 2.65, "braking": 25.0,
		"drift_control": 0.88, "nitro_power": 20.0, "mass": 0.98, "price": 5200, "unlocked": false,
		"color": Color(0.84, 0.86, 0.92), "accent": Color(0.75, 0.16, 1.00), "shape": "drift"
	},
	"hyper_nova": {
		"name": "Hyper Nova", "tagline": "Fastest car, savage nitro, difficult high-speed control.",
		"max_speed": 82.0, "acceleration": 27.0, "handling": 1.55, "braking": 23.0,
		"drift_control": 0.54, "nitro_power": 38.0, "mass": 0.86, "price": 9800, "unlocked": false,
		"color": Color(0.20, 0.10, 0.96), "accent": Color(0.00, 1.00, 0.80), "shape": "hyper"
	}
}

var tracks: Dictionary = {
	"city_night": {"name": "City Night", "difficulty": 1, "reward_multiplier": 1.00, "mood": "Neon streets, lamps, buildings, billboards and medium turns."},
	"desert_highway": {"name": "Desert Highway", "difficulty": 2, "reward_multiplier": 1.18, "mood": "Long straights, sand, stones, cactus and speed sections."},
	"mountain_road": {"name": "Mountain Road", "difficulty": 3, "reward_multiplier": 1.38, "mood": "Tight mountain road, barriers, trees and sharper turns."}
}

func _ready() -> void:
	load_game()

func load_game() -> void:
	unlocked_cars.clear()
	for id in cars.keys():
		unlocked_cars[id] = bool(cars[id].get("unlocked", false))
	unlocked_cars["street_starter"] = true
	if not FileAccess.file_exists(SAVE_PATH):
		save_game()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	money = int(parsed.get("money", money))
	selected_car = str(parsed.get("selected_car", selected_car))
	var saved_unlocked: Dictionary = parsed.get("unlocked_cars", {})
	for id in saved_unlocked.keys():
		if cars.has(id):
			unlocked_cars[id] = bool(saved_unlocked[id])
	unlocked_cars["street_starter"] = true
	if not unlocked_cars.get(selected_car, false):
		selected_car = "street_starter"
	best_times = parsed.get("best_times", {})
	var saved_settings: Dictionary = parsed.get("settings", {})
	for key in saved_settings.keys():
		if settings.has(key):
			settings[key] = saved_settings[key]

func save_game() -> void:
	var data := {"money": money, "selected_car": selected_car, "unlocked_cars": unlocked_cars, "best_times": best_times, "settings": settings}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))

func reset_progress() -> void:
	money = 0
	selected_car = "street_starter"
	best_times.clear()
	unlocked_cars.clear()
	for id in cars.keys():
		unlocked_cars[id] = id == "street_starter"
	save_game()
	emit_signal("money_changed", money)
	emit_signal("car_changed", selected_car)
	emit_signal("settings_changed")

func is_car_unlocked(id: String) -> bool:
	return bool(unlocked_cars.get(id, false))

func get_car(id: String) -> Dictionary:
	return cars[id] if cars.has(id) else cars["street_starter"]

func get_track(id: String) -> Dictionary:
	return tracks[id] if tracks.has(id) else tracks["city_night"]

func select_car(id: String) -> bool:
	if not cars.has(id) or not is_car_unlocked(id):
		return false
	selected_car = id
	save_game()
	emit_signal("car_changed", selected_car)
	return true

func buy_car(id: String) -> bool:
	if not cars.has(id) or is_car_unlocked(id):
		return false
	var price := int(cars[id].get("price", 0))
	if money < price:
		return false
	money -= price
	unlocked_cars[id] = true
	selected_car = id
	save_game()
	emit_signal("money_changed", money)
	emit_signal("car_changed", selected_car)
	return true

func set_setting(key: String, value) -> void:
	if settings.has(key):
		settings[key] = value
	save_game()
	emit_signal("settings_changed")

func award_race(track_id: String, result: Dictionary) -> int:
	var track := get_track(track_id)
	var multiplier := float(track.get("reward_multiplier", 1.0))
	var finished := bool(result.get("finished", true))
	var elapsed := float(result.get("time", 999.0))
	var max_speed := float(result.get("max_speed_kmh", 0.0))
	var drift_score := int(result.get("drift_score", 0))
	var score := int(result.get("score", 0))
	var checkpoint_bonus := int(result.get("checkpoints", 0)) * 65
	var finish_bonus := 550 if finished else 120
	var time_bonus := max(0, int(700.0 - elapsed * 5.0)) if finished else 0
	var speed_bonus := int(max_speed * 2.0)
	var drift_bonus := int(drift_score * 0.16)
	var earned := int(float(finish_bonus + time_bonus + speed_bonus + drift_bonus + checkpoint_bonus + score / 12) * multiplier)
	earned = max(40, earned)
	money += earned
	if finished:
		var previous = best_times.get(track_id, null)
		if previous == null or elapsed < float(previous):
			best_times[track_id] = elapsed
	save_game()
	emit_signal("money_changed", money)
	return earned

func format_time(seconds: float) -> String:
	var total := int(seconds)
	var mins := int(total / 60)
	var secs := total % 60
	var millis := int((seconds - floor(seconds)) * 1000.0)
	return "%02d:%02d.%03d" % [mins, secs, millis]

func car_ids() -> Array:
	return ["street_starter", "sport_viper", "iron_muscle", "drift_ghost", "hyper_nova"]

func track_ids() -> Array:
	return ["city_night", "desert_highway", "mountain_road"]
